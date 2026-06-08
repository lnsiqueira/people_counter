# 🎯 People Counter AI

Contador de pessoas em tempo real usando **YOLOv8 + ByteTrack** no backend Python
e **Flutter** como interface visual.

---

## 📁 Estrutura

```
people_counter/
├── backend/
│   ├── server.py          ← Servidor WebSocket + IA
│   └── requirements.txt
└── flutter_app/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── models/
        ├── services/
        ├── widgets/
        └── screens/
```

---

## 🚀 Como Rodar

### 1. Backend (Python)

```bash
cd backend

# Criar ambiente virtual (recomendado)
python -m venv venv
source venv/bin/activate        # Linux/Mac
# venv\Scripts\activate         # Windows

# Instalar dependências
pip install -r requirements.txt

# Rodar servidor
python server.py
```

O servidor irá:
- Baixar automaticamente o modelo `yolov8n.pt` na primeira execução
- Abrir a webcam do notebook (índice 0)
- Iniciar WebSocket em `ws://localhost:8765`

### 2. Flutter

```bash
cd flutter_app

# Instalar dependências
flutter pub get

# Rodar
flutter run -d chrome          # Web
flutter run -d macos           # macOS desktop
flutter run -d windows         # Windows desktop
flutter run                    # Device/emulador conectado
```

---

## ⚙️ Configurações (backend/server.py)

| Variável         | Padrão | Descrição                            |
|------------------|--------|--------------------------------------|
| `CAMERA_INDEX`   | `0`    | Índice da câmera (0 = padrão)        |
| `COUNT_LINE_Y`   | `0.55` | Posição vertical da linha (0.0-1.0)  |
| `TARGET_FPS`     | `15`   | FPS alvo de processamento            |
| `JPEG_QUALITY`   | `70`   | Qualidade do frame transmitido       |
| `MODEL_PATH`     | `yolov8n.pt` | Modelo YOLO (`n`=nano, `s`=small...) |

---

## 🧠 Como funciona a contagem

```
Câmera → YOLOv8 detecta pessoas → ByteTrack atribui ID único
                                         ↓
                          Pessoa cruza linha virtual?
                          ↙                    ↘
                    De cima↓baixo           De baixo↑cima
                    → total_in++            → total_out++

               No local = total_in - total_out
```

Cada ID é contado **apenas uma vez**, evitando recontagem da mesma pessoa.

---

## 📱 Interface Flutter

- **Feed de vídeo** ao vivo com bounding boxes e trilhas
- **4 contadores**: Entradas / Saídas / No Local / IDs Ativos
- **Barra de ocupação** com alerta de lotação
- **Status de conexão** WebSocket em tempo real
- Layout responsivo (mobile e desktop)

---

## 🔧 Melhorias sugeridas

- [ ] Múltiplas câmeras (array de streams)
- [ ] Persistência em banco de dados (SQLite/PostgreSQL)
- [ ] Gráfico histórico de fluxo por hora
- [ ] Alertas push quando lotação crítica
- [ ] Exportar relatório CSV
- [ ] Linha de contagem configurável pela UI
