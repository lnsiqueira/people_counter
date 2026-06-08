#!/bin/bash
# Script de instalação — roda uma vez
set -e

echo "=== People Counter — Instalação ==="
echo ""

# Verifica versão do Python
PY_VERSION=$(python3 --version 2>&1)
echo "Python: $PY_VERSION"

# Instala dependências base primeiro (ordem importa!)
echo ""
echo "[1/4] Instalando numpy, scipy, Pillow..."
pip install "numpy>=1.26.0" "scipy>=1.11.0" "Pillow>=10.0.0" "six>=1.16.0" "h5py>=3.9.0"

echo ""
echo "[2/4] Instalando PyTorch..."
pip install "torch>=2.0.0" "torchvision>=0.15.0"

echo ""
echo "[3/4] Instalando ultralytics, opencv, websockets..."
pip install "ultralytics>=8.2.0" "opencv-python>=4.9.0" "websockets>=12.0"

echo ""
echo "[4/4] Instalando torchreid..."
# Torchreid precisa do numpy já instalado para fazer o build
pip install git+https://github.com/KaiyangZhou/deep-person-reid.git \
  --no-build-isolation 2>/dev/null || {
    echo ""
    echo "[!] torchreid falhou (comum no Python 3.13)"
    echo "    Usando alternativa: boxmot (mais leve e suporta Python 3.13)"
    pip install boxmot
  }

echo ""
echo "=== Instalação concluída! ==="
echo "    Rode: python server.py"
