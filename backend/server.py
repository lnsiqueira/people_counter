"""
People Counter Backend  v11
Recebe frames do camera_client.py via HTTP POST /push_frame
Processa com YOLO + ReID
Envia resultado via WebSocket /ws para o Flutter

Arquitetura:
  camera_client.py (local) → POST /push_frame → server.py (Azure)
  Flutter Web              ← WebSocket /ws    ← server.py (Azure)
"""

import asyncio, base64, json, math, time, datetime, os
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional

import cv2
import numpy as np
from aiohttp import web
from ultralytics import YOLO

# ─── ReID ─────────────────────────────────────────────────────────────────────
REID_MODE = "none"
try:
    import torch, torchvision.transforms as T, torchvision.models as models
    REID_MODE = "torchvision"
    print("[ReID] torchvision disponível")
except ImportError:
    print("[ReID] torch não encontrado")

# ─── Config ───────────────────────────────────────────────────────────────────
PORT           = int(os.environ.get("PORT", 8000))
JPEG_QUALITY   = 70
COUNT_LINE_Y   = 0.55
GHOST_TTL_SEC  = 6.0
GHOST_DIST_PX  = 180
REID_THRESHOLD = 0.60
GALLERY_MAX_AGE = 300.0
GALLERY_UPDATE_INTERVAL = 30

# ─── Estruturas ───────────────────────────────────────────────────────────────
@dataclass
class Ghost:
    logical_id: int; last_cx: float; last_cy: float
    last_side: str; counted_in: bool; counted_out: bool
    lost_at: float; track_ids: list = field(default_factory=list)

@dataclass
class GalleryEntry:
    logical_id: int; feature_vec: np.ndarray
    last_seen: float; seen_count: int = 1

# ─── Estado Global ────────────────────────────────────────────────────────────
model = None; reid_extractor = None
track_history    = defaultdict(list)
track_to_logical: dict = {}
ghosts:           dict = {}
gallery:          list = []
counted_in_lids:  set  = set()
counted_out_lids: set  = set()
all_seen_lids:    set  = set()
total_in = 0; total_out = 0; _next_lid = 1
event_log: list = []
ws_clients: set = set()          # clientes Flutter conectados
frame_counters = defaultdict(int)
latest_frame: Optional[bytes] = None   # último frame anotado (para novos clientes)

# ─── Helpers ──────────────────────────────────────────────────────────────────
def ts_now(): return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
def _new_lid():
    global _next_lid; lid = _next_lid; _next_lid += 1; return lid
def _side(cy, ly): return "below" if cy >= ly else "above"
def _dist(ax,ay,bx,by): return math.sqrt((ax-bx)**2+(ay-by)**2)

# ─── ReID ─────────────────────────────────────────────────────────────────────
def load_reid():
    global reid_extractor
    if REID_MODE != "torchvision": return
    try:
        import ssl
        try:
            import certifi
            ssl._create_default_https_context = lambda: ssl.create_default_context(cafile=certifi.where())
        except ImportError:
            ssl._create_default_https_context = ssl._create_unverified_context

        m = models.resnet50(weights=models.ResNet50_Weights.DEFAULT)
        m = torch.nn.Sequential(*list(m.children())[:-1])
        m.eval()
        device = "cuda" if torch.cuda.is_available() else "cpu"
        m = m.to(device)
        tfm = T.Compose([T.ToPILImage(), T.Resize((256,128)), T.ToTensor(),
                         T.Normalize([0.485,0.456,0.406],[0.229,0.224,0.225])])
        def extract(crop_bgr):
            if crop_bgr is None or crop_bgr.size == 0: return None
            try:
                rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
                t   = tfm(rgb).unsqueeze(0).to(device)
                with torch.no_grad(): feat = m(t)
                feat = feat.cpu().numpy().flatten()
                return feat / (np.linalg.norm(feat)+1e-12)
            except: return None
        reid_extractor = extract
        print("[✓] ReID: ResNet50 pronto")
    except Exception as e:
        print(f"[!] ReID falhou: {e}")

def _gallery_match(feat):
    if feat is None or not gallery: return None
    now = time.time(); best_sim, best_lid = -1.0, None
    for e in gallery:
        if now - e.last_seen > GALLERY_MAX_AGE: continue
        sim = float(np.dot(feat, e.feature_vec))
        if sim > best_sim: best_sim, best_lid = sim, e.logical_id
    return best_lid if best_sim >= REID_THRESHOLD else None

def _gallery_update(lid, feat):
    if feat is None: return
    now = time.time()
    for e in gallery:
        if e.logical_id == lid:
            a=0.3; e.feature_vec=a*feat+(1-a)*e.feature_vec
            e.feature_vec/=(np.linalg.norm(e.feature_vec)+1e-12)
            e.last_seen=now; e.seen_count+=1; return
    gallery.append(GalleryEntry(logical_id=lid,feature_vec=feat.copy(),last_seen=now))

def _gallery_expire():
    now=time.time(); gallery[:] = [e for e in gallery if now-e.last_seen<=GALLERY_MAX_AGE]

def _extract(frame,x1,y1,x2,y2,h,w):
    if reid_extractor is None: return None
    p=12; crop=frame[max(0,y1-p):min(h,y2+p),max(0,x1-p):min(w,x2+p)]
    return reid_extractor(crop)

def _find_ghost(cx,cy,side):
    now=time.time(); best,best_d=None,float("inf")
    for g in ghosts.values():
        if now-g.lost_at>GHOST_TTL_SEC: continue
        if g.last_side!=side: continue
        d=_dist(cx,cy,g.last_cx,g.last_cy)
        if d<GHOST_DIST_PX and d<best_d: best_d,best=d,g
    return best

def _expire_ghosts():
    now=time.time()
    for lid in list(ghosts):
        if now-ghosts[lid].lost_at>GHOST_TTL_SEC: del ghosts[lid]

def load_model():
    global model
    print("[*] Carregando YOLOv8...")
    model = YOLO("yolov8n.pt")
    print("[✓] YOLOv8 pronto!")
    load_reid()

# ─── Processa frame ───────────────────────────────────────────────────────────
def process_frame(frame: np.ndarray):
    global total_in, total_out, latest_frame
    h,w = frame.shape[:2]
    line_y = int(h*COUNT_LINE_Y)

    results = model.track(frame, persist=True, classes=[0],
                          conf=0.5, iou=0.7, tracker="bytetrack.yaml", verbose=False)

    annotated = frame.copy()
    cv2.line(annotated,(0,line_y),(w,line_y),(0,255,255),2)
    cv2.putText(annotated,"LINHA DE CONTAGEM",(10,line_y-8),
                cv2.FONT_HERSHEY_SIMPLEX,0.5,(0,255,255),1)

    current_raw: set = set()

    if results[0].boxes is not None and results[0].boxes.id is not None:
        boxes = results[0].boxes.xyxy.cpu().numpy()
        ids   = results[0].boxes.id.cpu().numpy().astype(int)
        confs = results[0].boxes.conf.cpu().numpy()

        # Dedup boxes sobrepostos
        keep=[]
        for i in range(len(boxes)):
            dup=False
            for j in keep:
                b1,b2=boxes[i],boxes[j]
                ix1=max(b1[0],b2[0]);iy1=max(b1[1],b2[1])
                ix2=min(b1[2],b2[2]);iy2=min(b1[3],b2[3])
                if ix2>ix1 and iy2>iy1:
                    inter=(ix2-ix1)*(iy2-iy1)
                    a1=(b1[2]-b1[0])*(b1[3]-b1[1]); a2=(b2[2]-b2[0])*(b2[3]-b2[1])
                    if inter/(a1+a2-inter+1e-6)>0.6:
                        dup=True
                        if confs[i]>confs[j]: keep.remove(j); keep.append(i)
                        break
            if not dup: keep.append(i)
        boxes=boxes[keep]; ids=ids[keep]; confs=confs[keep]

        for box,raw_id,conf in zip(boxes,ids,confs):
            raw_id=int(raw_id)
            x1,y1,x2,y2=map(int,box)
            cx,cy=(x1+x2)/2,(y1+y2)/2
            current_raw.add(raw_id)
            side=_side(cy,line_y)

            if raw_id not in track_to_logical:
                lid=None
                ghost=_find_ghost(cx,cy,side)
                if ghost:
                    lid=ghost.logical_id; ghosts.pop(lid,None)
                    track_to_logical[raw_id]=lid
                if lid is None and reid_extractor:
                    feat=_extract(frame,x1,y1,x2,y2,h,w)
                    m=_gallery_match(feat)
                    if m: lid=m; track_to_logical[raw_id]=lid; _gallery_update(lid,feat)
                if lid is None:
                    lid=_new_lid(); track_to_logical[raw_id]=lid
                    all_seen_lids.add(lid)
                    _gallery_update(lid,_extract(frame,x1,y1,x2,y2,h,w))
            else:
                lid=track_to_logical[raw_id]; ghosts.pop(lid,None)
                frame_counters[lid]+=1
                if reid_extractor and frame_counters[lid]%GALLERY_UPDATE_INTERVAL==0:
                    _gallery_update(lid,_extract(frame,x1,y1,x2,y2,h,w))

            track_history[lid].append((cx,cy))
            if len(track_history[lid])>30: track_history[lid].pop(0)

            hist=track_history[lid]
            if len(hist)>=2:
                pcy,ccy=hist[-2][1],hist[-1][1]
                if pcy<line_y<=ccy and lid not in counted_in_lids:
                    counted_in_lids.add(lid); total_in+=1
                    event_log.append({"id":lid,"direction":"in","label":"Entrada",
                                      "timestamp":ts_now(),"unix":time.time(),"seq":total_in})
                elif pcy>line_y>=ccy and lid not in counted_out_lids:
                    counted_out_lids.add(lid); total_out+=1
                    event_log.append({"id":lid,"direction":"out","label":"Saída",
                                      "timestamp":ts_now(),"unix":time.time(),"seq":total_out})

            color=(0,200,100) if lid in counted_in_lids else (100,150,255)
            cv2.rectangle(annotated,(x1,y1),(x2,y2),color,2)
            lbl=f"P#{lid} {conf:.0%}"
            (lw,lh),_=cv2.getTextSize(lbl,cv2.FONT_HERSHEY_SIMPLEX,0.52,1)
            cv2.rectangle(annotated,(x1,y1-lh-8),(x1+lw+4,y1),color,-1)
            cv2.putText(annotated,lbl,(x1+2,y1-4),cv2.FONT_HERSHEY_SIMPLEX,0.52,(255,255,255),1)
            pts=track_history[lid]
            for i in range(1,len(pts)):
                a=i/len(pts); c=tuple(int(x*a) for x in color)
                cv2.line(annotated,(int(pts[i-1][0]),int(pts[i-1][1])),(int(pts[i][0]),int(pts[i][1])),c,2)

    for raw_id,lid in list(track_to_logical.items()):
        if raw_id not in current_raw:
            hist=track_history.get(lid,[])
            lx,ly=(hist[-1] if hist else (0.0,0.0))
            if lid not in ghosts:
                ghosts[lid]=Ghost(logical_id=lid,last_cx=lx,last_cy=ly,
                    last_side=_side(ly,line_y),counted_in=lid in counted_in_lids,
                    counted_out=lid in counted_out_lids,lost_at=time.time(),track_ids=[raw_id])
            del track_to_logical[raw_id]

    _expire_ghosts(); _gallery_expire()

    inside=max(0,total_in-total_out)
    overlay=annotated.copy()
    cv2.rectangle(overlay,(0,0),(255,155),(20,20,20),-1)
    cv2.addWeighted(overlay,0.65,annotated,0.35,0,annotated)
    cv2.putText(annotated,f"PESSOAS  : {len(all_seen_lids)}",(12,32),cv2.FONT_HERSHEY_SIMPLEX,0.65,(255,180,50),2)
    cv2.putText(annotated,f"ENTRADAS : {total_in}",(12,62),cv2.FONT_HERSHEY_SIMPLEX,0.65,(100,255,100),2)
    cv2.putText(annotated,f"SAIDAS   : {total_out}",(12,92),cv2.FONT_HERSHEY_SIMPLEX,0.65,(100,180,255),2)
    cv2.putText(annotated,f"NO LOCAL : {inside}",(12,122),cv2.FONT_HERSHEY_SIMPLEX,0.65,(255,220,50),2)

    # Salva frame anotado em memória
    _, buf = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
    latest_frame = base64.b64encode(buf).decode()

    return {
        "total_unique":  len(all_seen_lids),
        "total_in":      total_in,
        "total_out":     total_out,
        "inside":        inside,
        "active_tracks": len(current_raw),
        "ghost_count":   len(ghosts),
        "gallery_size":  len(gallery),
        "reid_active":   reid_extractor is not None,
        "reid_mode":     "ResNet50" if reid_extractor else "OFF",
        "timestamp":     time.time(),
        "recent_events": event_log[-5:],
        "log_size":      len(event_log),
    }

# ─── HTTP: recebe frame da câmera local ───────────────────────────────────────
async def push_frame(request):
    """camera_client.py faz POST aqui com o frame em base64"""
    try:
        data  = await request.json()
        b64   = data.get("frame", "")
        buf   = base64.b64decode(b64)
        arr   = np.frombuffer(buf, np.uint8)
        frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if frame is None:
            return web.Response(status=400, text="Frame inválido")

        stats = process_frame(frame)

        # Transmite para todos os clientes Flutter conectados
        if ws_clients and latest_frame:
            payload = json.dumps({"frame": latest_frame, "stats": stats})
            await asyncio.gather(
                *[ws.send_str(payload) for ws in list(ws_clients) if not ws.closed],
                return_exceptions=True
            )

        return web.json_response(stats)
    except Exception as e:
        print(f"[!] push_frame erro: {e}")
        return web.Response(status=500, text=str(e))

# ─── HTTP health check ────────────────────────────────────────────────────────
async def http_health(request):
    return web.Response(text="OK — People Counter API")

# ─── WebSocket: Flutter conecta aqui ─────────────────────────────────────────
async def ws_handler(request):
    ws = web.WebSocketResponse(max_msg_size=0)
    await ws.prepare(request)
    ws_clients.add(ws)
    print(f"[+] Flutter conectado  ({len(ws_clients)} clientes)")

    # Envia log histórico ao conectar
    await ws.send_str(json.dumps({
        "type":      "full_log",
        "event_log": event_log,
        "total_in":  total_in,
        "total_out": total_out,
    }))

    # Mantém conexão aberta até o cliente fechar
    async for _ in ws:
        pass

    ws_clients.discard(ws)
    print(f"[-] Flutter desconectado  ({len(ws_clients)} clientes)")
    return ws

# ─── Main ─────────────────────────────────────────────────────────────────────
async def main():
    load_model()

    app = web.Application(client_max_size=10*1024*1024)  # 10MB para frames
    app.router.add_get("/",            http_health)
    app.router.add_get("/health",      http_health)
    app.router.add_get("/ws",          ws_handler)       # Flutter conecta aqui
    app.router.add_post("/push_frame", push_frame)        # câmera local envia aqui

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()

    print(f"\n[✓] Servidor rodando na porta {PORT}")
    print(f"[✓] Flutter  → ws://localhost:{PORT}/ws")
    print(f"[✓] Câmera   → POST http://localhost:{PORT}/push_frame")
    print(f"\n    Azure:  wss://people-counter-api.azurewebsites.net/ws\n")

    await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
