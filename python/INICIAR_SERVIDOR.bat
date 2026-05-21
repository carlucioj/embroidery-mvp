@echo off
title Embroidery MVP — Servidor Python
color 0A
echo ============================================
echo  Embroidery MVP — Servidor de Processamento
echo  http://localhost:8000
echo ============================================
echo.

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    color 0C
    echo ERRO: Python nao encontrado.
    echo.
    echo Instale Python 3.11+ em: https://python.org/downloads
    echo Marque "Add Python to PATH" durante a instalacao.
    echo.
    pause
    exit /b 1
)

echo Python encontrado:
python --version
echo.

REM Install dependencies
echo [1/3] Instalando dependencias...
pip install fastapi uvicorn python-multipart pillow numpy opencv-python "rembg[cpu]" pyembroidery --quiet
echo Dependencias OK.
echo.

REM Pre-download rembg model
echo [2/3] Carregando modelo de IA (rembg)...
echo (Primeira vez baixa ~170MB - aguarde)
python -c "from rembg import new_session; new_session('u2net'); print('Modelo OK.')" 2>&1
echo.

REM Start server
echo [3/3] Iniciando servidor...
echo.
echo ============================================
echo  SERVIDOR ATIVO: http://localhost:8000
echo.
echo  Deixe esta janela aberta enquanto usa o app.
echo  Para parar: feche esta janela ou Ctrl+C
echo ============================================
echo.

python api_server.py --host 0.0.0.0 --port 8000

echo.
echo Servidor encerrado.
pause
