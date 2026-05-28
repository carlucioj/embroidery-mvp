# -*- mode: python ; coding: utf-8 -*-
#
# PyInstaller spec — Embroidery MVP Python engine (HTTP server mode).
#
# Usage (from the python/ directory, with venv active):
#   pyinstaller embroidery_backend.spec
#
# Output: dist/embroidery_backend/
#   embroidery_backend.exe  ← entry point (no terminal window)
#   _internal/              ← Python runtime + all dependencies
#
# The Flutter app expects the engine at:
#   <flutter_exe_dir>\engine\embroidery_backend.exe
#
# rembg model (~170 MB) is NOT bundled — it downloads automatically to
# ~/.u2net/ on the first call to /process-image.

import sys
from pathlib import Path

block_cipher = None

a = Analysis(
    ["api_server.py"],
    pathex=["."],
    binaries=[],
    datas=[],
    hiddenimports=[
        # pyembroidery uses dynamic format registration
        "pyembroidery",
        # uvicorn relies on importlib for these — PyInstaller can't auto-detect
        "uvicorn.logging",
        "uvicorn.loops",
        "uvicorn.loops.auto",
        "uvicorn.protocols",
        "uvicorn.protocols.http",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.websockets",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.lifespan",
        "uvicorn.lifespan.on",
        # anyio async backend
        "anyio",
        "anyio._backends._asyncio",
        # starlette internals used by FastAPI
        "starlette.routing",
        "starlette.middleware",
        "starlette.middleware.cors",
        "starlette.responses",
        "starlette.staticfiles",
        # image processing
        "cv2",
        "PIL",
        "PIL.Image",
        "numpy",
        # rembg — imported lazily, ensure it's included
        "rembg",
        "rembg.sessions",
        "rembg.sessions.u2net",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "tkinter",
        "matplotlib",
        "scipy",
        "pandas",
        "IPython",
        "jupyter",
        "notebook",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="embroidery_backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    # console=False → no terminal window pops up when Flutter spawns the engine.
    # Logs go to stderr (captured by the parent process if needed).
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="embroidery_backend",
)
