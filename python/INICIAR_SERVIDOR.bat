@echo off
title Embroidery MVP — Servidor Python
color 0A
echo ============================================
echo  Embroidery MVP — Servidor de Processamento
echo  http://localhost:8000
echo ============================================
echo.

REM Use venv Python if available, otherwise fallback to global
set VENV_PYTHON=%~dp0.venv\Scripts\python.exe
if exist "%VENV_PYTHON%" (
    set PYTHON=%VENV_PYTHON%
    echo Usando ambiente virtual: .venv
) else (
    set PYTHON=python
    echo AVISO: ambiente virtual nao encontrado, usando Python global.
    echo Para criar: python -m venv .venv
    echo.
)

echo Python:
"%PYTHON%" --version
echo.

REM Pre-download rembg model
echo [1/2] Carregando modelo de IA (rembg)...
echo (Primeira vez baixa ~170MB - aguarde)
"%PYTHON%" -c "from rembg import new_session; new_session('u2net'); print('Modelo OK.')" 2>&1
echo.

REM Start server
echo [2/2] Iniciando servidor...
echo.
echo ============================================
echo  SERVIDOR ATIVO: http://localhost:8000
echo.
echo  Deixe esta janela aberta enquanto usa o app.
echo  Para parar: feche esta janela ou Ctrl+C
echo ============================================
echo.

"%PYTHON%" api_server.py --host 0.0.0.0 --port 8000

echo.
echo Servidor encerrado.
pause
