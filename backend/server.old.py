"""
People Counter Backend  v6
YOLOv8 + ReID adaptativo

Suporta 3 modos de ReID (detecta automaticamente o que está instalado):
  1. torchreid  (osnet_x0_25) — melhor qualidade, Python <= 3.12
  2. boxmot     (clip-reid)   — suporta Python 3.13, muito bom
  3. Fallback   ghost buffer  — só posição, sem ReID visual

Instale com:  bash install.sh
"""

import asyncio, base64, json, math, time, datetime
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional

import cv2
import numpy as np
import websockets
from ultralytics import YOLO

# ─── Detecta qual ReID está disponível ────────────────────────────────────────
REID_MODE = "none"

try:
    import torch
    import torchvision.transforms as T
    import torchreid as _torchreid_mod
    REID_MODE = "torchreid"
    print("[ReID] torchreid disponível")
except ImportError:
    pass

if REID_MODE == "none":
    try:
        import torch
        from boxmot import DeepOCSORT          # usa clip-reid internamente
        REID_MODE = "boxmot"
        print("[ReID] boxmot disponível")
    except ImportError:
        pass

if REID_MODE == "none":
    try:
        import torch
        import torchvision.transforms as T
        REID_MODE = "torchvision"              # usa ResNet50 como extrator simples
        print("[ReID] torchvision (ResNet50) disponível")
    except ImportError:
        print("[ReID] Nenhuma lib de ReID encontrada — usando ghost buffer posicional")

# ─── Config ───────────────────────────────────────────────────────────────────
WEBSOCKET_HOST  = "0.0.0.0"
WEBSOCKET_PORT  = 8765
CAMERA_INDEX    = 0
FRAME_WIDTH     = 640
FRAME_HEIGHT    = 480
JPEG_QUALITY    = 70
TARGET_FPS      = 15
MODEL_PATH      = "yolov8n.pt"
COUNT_LINE_Y    = 0.55

GHOST_TTL_SEC   = 5.0
GHOST_DIST_PX   = 130

REID_THRESHOLD  = 0.60    # similaridade cosseno mínima (0.5=permissivo, 0.75=rigoroso)
GALLERY_MAX_AGE = 300.0   # segundos sem ver → remove da galeria
GALLERY_UPDATE_INTERVAL = 30  # frames entre atualizações da galeria por pessoa ativa

# ─── Estruturas ───────────────────────────────────────────────────────────────
@dataclass
class Ghost:
    logical_id:  int
    last_cx:     float
    last_cy:     float
    last_side:   str
    counted_in:  bool
    counted_out: bool
    lost_at:     float
    track_ids:   list = field(default_factory=list)

@dataclass
class GalleryEntry:
    logical_id:  int
    feature_vec: np.ndarray
    last_seen:   float
    seen_count:  int = 1

# ─── Estado Global ────────────────────────────────────────────────────────────
model             = None
reid_extractor    = None      # função: crop_bgr → np.ndarray | None

track_history:    dict = defaultdict(list)
track_to_logical: dict = {}
ghosts:           dict = {}
gallery:          list = []

counted_in_lids:  set = set()
counted_out_lids: set = set()
all_seen_lids:    set = set()

total_in  = 0
total_out = 0
_next_lid = 1
event_log        = []
connected_clients = set()

frame_counters: dict = defaultdict(int)  # lid → frames desde última atualização


# ─── Helpers ──────────────────────────────────────────────────────────────────
def ts_now(): return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
def _new_lid():
    global _next_lid; lid = _next_lid; _next_lid += 1; return lid
def _side(cy, ly): return "below" if cy >= ly else "above"
def _dist(ax,ay,bx,by): return math.sqrt((ax-bx)**2+(ay-by)**2)


# ─── Inicializa ReID ──────────────────────────────────────────────────────────
def _build_reid_torchreid():
    import torchreid
    import torch, torchvision.transforms as T
    m = torchreid.models.build_model(name='osnet_x0_25', num_classes=1000, pretrained=True)
    m.eval()
    device = "cuda" if torch.cuda.is_available() else "cpu"
    m = m.to(device)
    tfm = T.Compose([
        T.ToPILImage(),
        T.Resize((256,128)),
        T.ToTensor(),
        T.Normalize([0.485,0.456,0.406],[0.229,0.224,0.225]),
    ])
    def extract(crop_bgr):
        if crop_bgr is None or crop_bgr.size == 0: return None
        try:
            rgb    = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
            tensor = tfm(rgb).unsqueeze(0).to(device)
            with torch.no_grad(): feat = m(tensor)
            feat = feat.cpu().numpy().flatten()
            return feat / (np.linalg.norm(feat) + 1e-12)
        except: return None
    print("[✓] ReID: osnet_x0_25 (torchreid)")
    return extract

def _build_reid_torchvision():
    """Extrator simples com ResNet50 — não precisa de torchreid."""
    import torch, torchvision.models as models, torchvision.transforms as T
    m = models.resnet50(weights=models.ResNet50_Weights.DEFAULT)
    # Remove a última camada de classificação — usa penúltima como embedding
    m = torch.nn.Sequential(*list(m.children())[:-1])
    m.eval()
    device = "cuda" if torch.cuda.is_available() else "cpu"
    m = m.to(device)
    tfm = T.Compose([
        T.ToPILImage(),
        T.Resize((256,128)),
        T.ToTensor(),
        T.Normalize([0.485,0.456,0.406],[0.229,0.224,0.225]),
    ])
    def extract(crop_bgr):
        if crop_bgr is None or crop_bgr.size == 0: return None
        try:
            rgb    = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
            tensor = tfm(rgb).unsqueeze(0).to(device)
            with torch.no_grad(): feat = m(tensor)
            feat = feat.cpu().numpy().flatten()
            return feat / (np.linalg.norm(feat) + 1e-12)
        except: return None
    print("[✓] ReID: ResNet50 (torchvision) — funciona no Python 3.13")
    return extract

def _build_reid_none():
    print("[✓] ReID: desativado — usando ghost buffer por posição")
    return None


def load_model():
    global model, reid_extractor
    print(f"[*] Carregando YOLOv8 ({MODEL_PATH})...")
    model = YOLO(MODEL_PATH)
    print("[✓] YOLOv8 pronto!")

    if REID_MODE == "torchreid":
        try:    reid_extractor = _build_reid_torchreid()
        except Exception as e:
            print(f"[!] torchreid falhou ({e}), tentando torchvision...")
            try:    reid_extractor = _build_reid_torchvision()
            except: reid_extractor = _build_reid_none()
    elif REID_MODE in ("boxmot", "torchvision"):
        try:    reid_extractor = _build_reid_torchvision()
        except: reid_extractor = _build_reid_none()
    else:
        reid_extractor = _build_reid_none()


# ─── Galeria ReID ─────────────────────────────────────────────────────────────
def _gallery_match(feat) -> Optional[int]:
    if feat is None or not gallery: return None
    now  = time.time()
    best_sim, best_lid = -1.0, None
    for e in gallery:
        if now - e.last_seen > GALLERY_MAX_AGE: continue
        sim = float(np.dot(feat, e.feature_vec))
        if sim > best_sim: best_sim, best_lid = sim, e.logical_id
    if best_sim >= REID_THRESHOLD:
        print(f"[REID] match lid#{best_lid}  sim={best_sim:.3f}")
        return best_lid
    return None

def _gallery_update(lid, feat):
    if feat is None: return
    now = time.time()
    for e in gallery:
        if e.logical_id == lid:
            alpha = 0.3
            e.feature_vec = alpha*feat + (1-alpha)*e.feature_vec
            e.feature_vec /= (np.linalg.norm(e.feature_vec)+1e-12)
            e.last_seen = now; e.seen_count += 1; return
    gallery.append(GalleryEntry(logical_id=lid, feature_vec=feat.copy(), last_seen=now))

def _gallery_expire():
    now = time.time()
    before = len(gallery)
    gallery[:] = [e for e in gallery if now - e.last_seen <= GALLERY_MAX_AGE]
    if len(gallery) < before:
        print(f"[GALLERY] {before-len(gallery)} entradas expiradas")

def _extract(frame, x1, y1, x2, y2, h, w):
    if reid_extractor is None: return None
    pad  = 12
    crop = frame[max(0,y1-pad):min(h,y2+pad), max(0,x1-pad):min(w,x2+pad)]
    return reid_extractor(crop)


# ─── Ghost buffer ─────────────────────────────────────────────────────────────
def _find_ghost(cx, cy, side):
    now = time.time()
    best, best_d = None, float("inf")
    for g in ghosts.values():
        if now - g.lost_at > GHOST_TTL_SEC: continue
        if g.last_side != side: continue
        d = _dist(cx, cy, g.last_cx, g.last_cy)
        if d < GHOST_DIST_PX and d < best_d: best_d, best = d, g
    return best

def _expire_ghosts():
    now = time.time()
    for lid in list(ghosts):
        if now - ghosts[lid].lost_at > GHOST_TTL_SEC: del ghosts[lid]


# ─── Processa frame ───────────────────────────────────────────────────────────
def process_frame(frame: np.ndarray):
    global total_in, total_out
    h, w = frame.shape[:2]
    line_y = int(h * COUNT_LINE_Y)

    results = model.track(frame, persist=True, classes=[0],
                          conf=0.4, iou=0.5, tracker="bytetrack.yaml", verbose=False)

    annotated = frame.copy()
    cv2.line(annotated, (0, line_y), (w, line_y), (0,255,255), 2)
    cv2.putText(annotated, "LINHA DE CONTAGEM", (10, line_y-8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0,255,255), 1)

    current_raw: set = set()

    if results[0].boxes is not None and results[0].boxes.id is not None:
        boxes = results[0].boxes.xyxy.cpu().numpy()
        ids   = results[0].boxes.id.cpu().numpy().astype(int)
        confs = results[0].boxes.conf.cpu().numpy()

        for box, raw_id, conf in zip(boxes, ids, confs):
            raw_id = int(raw_id)
            x1,y1,x2,y2 = map(int, box)
            cx,cy = (x1+x2)/2, (y1+y2)/2
            current_raw.add(raw_id)
            side = _side(cy, line_y)

            # ── Resolve logical_id ────────────────────────────────────────────
            if raw_id not in track_to_logical:
                lid = None

                # 1) Ghost posicional (instantâneo, sem custo)
                ghost = _find_ghost(cx, cy, side)
                if ghost:
                    lid = ghost.logical_id
                    ghosts.pop(lid, None)
                    track_to_logical[raw_id] = lid
                    print(f"[GHOST] raw#{raw_id} → lid#{lid}")

                # 2) ReID visual
                if lid is None and reid_extractor:
                    feat = _extract(frame, x1,y1,x2,y2, h,w)
                    matched = _gallery_match(feat)
                    if matched:
                        lid = matched
                        track_to_logical[raw_id] = lid
                        _gallery_update(lid, feat)

                # 3) Pessoa nova
                if lid is None:
                    lid = _new_lid()
                    track_to_logical[raw_id] = lid
                    all_seen_lids.add(lid)
                    feat = _extract(frame, x1,y1,x2,y2, h,w)
                    _gallery_update(lid, feat)
                    print(f"[NEW] raw#{raw_id} → lid#{lid}  unique={len(all_seen_lids)}")
            else:
                lid = track_to_logical[raw_id]
                ghosts.pop(lid, None)
                # Atualiza galeria periodicamente
                frame_counters[lid] += 1
                if reid_extractor and frame_counters[lid] % GALLERY_UPDATE_INTERVAL == 0:
                    feat = _extract(frame, x1,y1,x2,y2, h,w)
                    _gallery_update(lid, feat)

            # ── Histórico ─────────────────────────────────────────────────────
            track_history[lid].append((cx, cy))
            if len(track_history[lid]) > 30: track_history[lid].pop(0)

            # ── Contagem na linha ──────────────────────────────────────────────
            hist = track_history[lid]
            if len(hist) >= 2:
                pcy, ccy = hist[-2][1], hist[-1][1]
                if pcy < line_y <= ccy and lid not in counted_in_lids:
                    counted_in_lids.add(lid); total_in += 1
                    event_log.append({"id":lid,"direction":"in","label":"Entrada",
                                      "timestamp":ts_now(),"unix":time.time(),"seq":total_in})
                    print(f"[IN]  lid#{lid}  total_in={total_in}")
                elif pcy > line_y >= ccy and lid not in counted_out_lids:
                    counted_out_lids.add(lid); total_out += 1
                    event_log.append({"id":lid,"direction":"out","label":"Saída",
                                      "timestamp":ts_now(),"unix":time.time(),"seq":total_out})
                    print(f"[OUT] lid#{lid}  total_out={total_out}")

            # ── Desenha ───────────────────────────────────────────────────────
            color = (0,200,100) if lid in counted_in_lids else (100,150,255)
            cv2.rectangle(annotated, (x1,y1),(x2,y2), color, 2)
            lbl = f"P#{lid}  {conf:.0%}"
            (lw,lh),_ = cv2.getTextSize(lbl, cv2.FONT_HERSHEY_SIMPLEX,0.52,1)
            cv2.rectangle(annotated,(x1,y1-lh-8),(x1+lw+4,y1),color,-1)
            cv2.putText(annotated,lbl,(x1+2,y1-4),cv2.FONT_HERSHEY_SIMPLEX,0.52,(255,255,255),1)
            pts = track_history[lid]
            for i in range(1,len(pts)):
                a=i/len(pts); c=tuple(int(x*a) for x in color)
                cv2.line(annotated,(int(pts[i-1][0]),int(pts[i-1][1])),(int(pts[i][0]),int(pts[i][1])),c,2)

    # ── IDs sumidos → ghosts ──────────────────────────────────────────────────
    for raw_id, lid in list(track_to_logical.items()):
        if raw_id not in current_raw:
            hist = track_history.get(lid,[])
            lx,ly = (hist[-1] if hist else (0.0,0.0))
            if lid not in ghosts:
                ghosts[lid] = Ghost(logical_id=lid,last_cx=lx,last_cy=ly,
                    last_side=_side(ly,line_y),
                    counted_in=lid in counted_in_lids,
                    counted_out=lid in counted_out_lids,
                    lost_at=time.time(), track_ids=[raw_id])
            del track_to_logical[raw_id]

    # Ghosts visíveis no vídeo
    now = time.time()
    for lid,g in list(ghosts.items()):
        age = now - g.lost_at
        if age > GHOST_TTL_SEC: continue
        alpha = 1.0 - age/GHOST_TTL_SEC
        gx,gy = int(g.last_cx),int(g.last_cy)
        cv2.circle(annotated,(gx,gy),int(18*alpha),(0,140,255),2)
        cv2.putText(annotated,f"?P#{lid}",(gx+6,gy-6),cv2.FONT_HERSHEY_SIMPLEX,0.38,(0,140,255),1)

    _expire_ghosts(); _gallery_expire()

    # ── HUD ───────────────────────────────────────────────────────────────────
    inside = max(0, total_in-total_out)
    total_unique = len(all_seen_lids)
    reid_label = {"torchreid":"OSNet","torchvision":"ResNet50","boxmot":"BoxMOT"}.get(REID_MODE,"OFF")
    if reid_extractor is None: reid_label = "OFF"

    overlay = annotated.copy()
    cv2.rectangle(overlay,(0,0),(255,165),(20,20,20),-1)
    cv2.addWeighted(overlay,0.65,annotated,0.35,0,annotated)
    cv2.putText(annotated,f"PESSOAS   : {total_unique}",(12,32), cv2.FONT_HERSHEY_SIMPLEX,0.65,(255,180,50), 2)
    cv2.putText(annotated,f"ENTRADAS  : {total_in}",   (12,62), cv2.FONT_HERSHEY_SIMPLEX,0.65,(100,255,100),2)
    cv2.putText(annotated,f"SAIDAS    : {total_out}",  (12,92), cv2.FONT_HERSHEY_SIMPLEX,0.65,(100,180,255),2)
    cv2.putText(annotated,f"NO LOCAL  : {inside}",     (12,122),cv2.FONT_HERSHEY_SIMPLEX,0.65,(255,220,50), 2)
    cv2.putText(annotated,f"ReID:{reid_label}  Galeria:{len(gallery)}  Ghost:{len(ghosts)}",(12,150),
                cv2.FONT_HERSHEY_SIMPLEX,0.38,(180,180,180),1)

    return annotated, {
        "total_unique":  total_unique,
        "total_in":      total_in,
        "total_out":     total_out,
        "inside":        inside,
        "active_tracks": len(current_raw),
        "ghost_count":   len(ghosts),
        "gallery_size":  len(gallery),
        "reid_active":   reid_extractor is not None,
        "reid_mode":     reid_label,
        "timestamp":     time.time(),
        "recent_events": event_log[-5:],
        "log_size":      len(event_log),
    }


# ─── WebSocket ────────────────────────────────────────────────────────────────
async def handle_client(websocket):
    connected_clients.add(websocket)
    cap = cv2.VideoCapture(CAMERA_INDEX)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)

    if not cap.isOpened():
        await websocket.send(json.dumps({"error":"Câmera não encontrada"}))
        connected_clients.discard(websocket); return

    await websocket.send(json.dumps({
        "type":"full_log","event_log":event_log,"total_in":total_in,"total_out":total_out
    }))

    fi = 1.0/TARGET_FPS
    try:
        while True:
            t0 = time.time()
            ret, frame = cap.read()
            if not ret: break
            ann, stats = process_frame(frame)
            _, buf = cv2.imencode(".jpg", ann, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
            await websocket.send(json.dumps({"frame":base64.b64encode(buf).decode(),"stats":stats}))
            await asyncio.sleep(max(0, fi-(time.time()-t0)))
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        cap.release(); connected_clients.discard(websocket)

async def main():
    load_model()
    print(f"\n[*] ws://{WEBSOCKET_HOST}:{WEBSOCKET_PORT}")
    print(f"[*] REID_THRESHOLD={REID_THRESHOLD}  GHOST_TTL={GHOST_TTL_SEC}s\n")
    async with websockets.serve(handle_client, WEBSOCKET_HOST, WEBSOCKET_PORT):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
