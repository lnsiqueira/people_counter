"""
Camera Client — roda no computador LOCAL com a câmera
Captura frames e envia para o Azure App Service via HTTP POST

Instalação (bem leve):
  pip install opencv-python requests

Uso:
  python camera_client.py --server https://people-counter-api.azurewebsites.net
"""

import cv2, requests, base64, time, argparse, json

# ─── Config ───────────────────────────────────────────────────────────────────
CAMERA_INDEX  = 0
FRAME_WIDTH   = 640
FRAME_HEIGHT  = 480
JPEG_QUALITY  = 70
TARGET_FPS    = 10

def main(server_url: str):
    push_url = f"{server_url}/push_frame"
    print(f"[*] Enviando frames para: {push_url}")

    cap = cv2.VideoCapture(CAMERA_INDEX)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)

    if not cap.isOpened():
        print("[!] Câmera não encontrada")
        return

    print(f"[✓] Câmera aberta — enviando {TARGET_FPS} fps")
    interval = 1.0 / TARGET_FPS
    session  = requests.Session()

    while True:
        t0 = time.time()
        ret, frame = cap.read()
        if not ret:
            print("[!] Falha ao capturar frame"); break

        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
        b64    = base64.b64encode(buf).decode()

        try:
            r = session.post(push_url, json={"frame": b64}, timeout=2)
            if r.status_code == 200:
                stats = r.json()
                print(f"\r[→] Pessoas:{stats.get('total_unique',0)}  "
                      f"In:{stats.get('total_in',0)}  "
                      f"Out:{stats.get('total_out',0)}  "
                      f"Local:{stats.get('inside',0)}  ", end="")
        except requests.exceptions.ConnectionError:
            print("\n[!] Sem conexão com o servidor, tentando novamente...")
            time.sleep(2)
        except Exception as e:
            print(f"\n[!] Erro: {e}")

        elapsed = time.time() - t0
        time.sleep(max(0, interval - elapsed))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="https://people-counter-api.azurewebsites.net",
                        help="URL do servidor Azure")
    args = parser.parse_args()
    main(args.server)
