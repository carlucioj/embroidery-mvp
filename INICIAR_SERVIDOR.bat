@echo off
chcp 65001 >nul
title Embroidery MVP — Servidor Python

echo ============================================================
echo  Embroidery MVP — Iniciando servidor Python (localhost:8000)
echo ============================================================
echo.

cd /d "%~dp0python"

if not exist ".venv\Scripts\python.exe" (
    echo [ERRO] Ambiente virtual nao encontrado.
    echo Execute primeiro:
    echo   cd python
    echo   python -m venv .venv
    echo   .\.venv\Scripts\Activate.ps1
    echo   pip install rembg opencv-python-headless pyembroidery Pillow numpy fastapi uvicorn
    pause
    exit /b 1
)

echo Servidor iniciando em http://localhost:8000
echo Mantenha esta janela aberta enquanto usa o app.
echo Pressione Ctrl+C para parar.
echo.

.venv\Scripts\python.exe api_server.py
pause
