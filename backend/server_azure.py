"""
People Counter — Azure Relay Server (ultra leve)
Só recebe frames anotados + stats do camera_client e repassa para o Flutter via WebSocket
Sem YOLO, sem torch, sem dependências pesadas

Dependências: aiohttp apenas
"""

import asyncio, json, time, os
from aiohttp import web

PORT = int(os.environ.get("PORT", 8000))

ws_clients: set = set()
latest_payload: str = ""   # último frame+stats (para cliente que conecta depois)
event_log: list = []

async def http_health(request):
    return web.Response(text=f"OK — People Counter Relay — clientes: {len(ws_clients)}")

async def push_frame(request):
    """camera_client.py faz POST aqui com frame anotado + stats"""
    global latest_payload
    try:
        data = await request.json()

        # Guarda eventos no log
        for ev in data.get("stats", {}).get("recent_events", []):
            key = f"{ev['id']}_{ev['direction']}_{int(ev['unix'])}"
            if not any(f"{e['id']}_{e['direction']}_{int(e['unix'])}" == key for e in event_log):
                event_log.append(ev)

        # Monta payload para o Flutter
        payload = json.dumps({
            "frame": data.get("frame", ""),
            "stats": data.get("stats", {}),
        })
        latest_payload = payload

        # Envia para todos os clientes Flutter conectados
        if ws_clients:
            await asyncio.gather(
                *[ws.send_str(payload) for ws in list(ws_clients) if not ws.closed],
                return_exceptions=True,
            )

        return web.json_response({"ok": True, "clients": len(ws_clients)})
    except Exception as e:
        return web.Response(status=500, text=str(e))

async def ws_handler(request):
    """Flutter conecta aqui"""
    ws = web.WebSocketResponse(max_msg_size=0)
    await ws.prepare(request)
    ws_clients.add(ws)
    print(f"[+] Flutter conectado ({len(ws_clients)} clientes)")

    # Envia log histórico
    await ws.send_str(json.dumps({
        "type":      "full_log",
        "event_log": event_log,
        "total_in":  0,
        "total_out": 0,
    }))

    # Se já tem frame, envia imediatamente
    if latest_payload:
        await ws.send_str(latest_payload)

    async for _ in ws:
        pass

    ws_clients.discard(ws)
    print(f"[-] Flutter desconectado ({len(ws_clients)} clientes)")
    return ws

async def main():
    app = web.Application(client_max_size=10*1024*1024)
    app.router.add_get("/",            http_health)
    app.router.add_get("/health",      http_health)
    app.router.add_get("/ws",          ws_handler)
    app.router.add_post("/push_frame", push_frame)

    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, "0.0.0.0", PORT).start()

    print(f"\n[✓] Relay rodando na porta {PORT}")
    print(f"[✓] Flutter  → wss://people-counter-api.azurewebsites.net/ws")
    print(f"[✓] Câmera   → POST https://people-counter-api.azurewebsites.net/push_frame\n")

    await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
