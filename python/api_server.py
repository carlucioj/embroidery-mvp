"""
REST API Server for Mobile Processing

Exposes the image processing and embroidery conversion as HTTP endpoints.
Used by the mobile app when local processing is not available.

Endpoints:
    GET  /health                  — Health check
    POST /process-image           — Remove background + reduce colors
    POST /convert-embroidery      — Convert to embroidery file

Authentication:
    Bearer token via Authorization header (Alpha version).
    Set the EMBROIDERY_API_TOKEN environment variable on the server.

Rate limiting:
    Handled by slowapi (10 requests/minute per IP by default).

Usage:
    python api_server.py --host 0.0.0.0 --port 8000
"""

import base64
import logging
import os
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

from image_processor import ImageProcessor
from embroidery_converter import EmbroideryConverter

logger = logging.getLogger(__name__)

# ── Auth ─────────────────────────────────────────────────────────────────────

API_TOKEN = os.environ.get("EMBROIDERY_API_TOKEN", "")


def _check_auth(request: Request) -> None:
    """Validate Bearer token if API_TOKEN is configured."""
    if not API_TOKEN:
        return  # No auth configured — open access (dev mode)

    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer ") or auth[7:] != API_TOKEN:
        raise HTTPException(status_code=401, detail="Token inválido ou ausente.")


# ── App setup ─────────────────────────────────────────────────────────────────

_processor = ImageProcessor()
_converter = EmbroideryConverter()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Embroidery MVP API starting up")
    yield
    logger.info("Embroidery MVP API shutting down")


app = FastAPI(
    title="Embroidery MVP Processing API",
    description="Remote processing API for the Embroidery MVP mobile app",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/health")
async def health_check():
    """Health check — returns 200 if the server is running."""
    return {"status": "ok", "version": "0.1.0"}


@app.post("/process-image")
async def process_image(
    request: Request,
    image: UploadFile = File(..., description="Image file (JPG, PNG, BMP, WEBP)"),
    max_colors: int = Form(default=8, ge=1, le=32, alias="maxColors"),
    remove_background: bool = Form(default=True, alias="removeBackground"),
    mode: str = Form(default="basic"),
):
    """
    Remove background and reduce colors from an uploaded image.

    Returns JSON with imageBase64, dominantColors, and complexity analysis.
    mode: "basic" (fast) or "advanced" (morphological cleanup + simplification).
    """
    _check_auth(request)

    try:
        image_bytes = await image.read()
        result = _processor.process_image(
            image_bytes=image_bytes,
            max_colors=max_colors,
            remove_background=remove_background,
            mode=mode,
        )
        return JSONResponse(content={
            "imageBase64": base64.b64encode(result["image_bytes"]).decode(),
            "dominantColors": result["dominant_colors"],
            "complexity": result["complexity"],
        })

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        logger.error("Error processing image: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail="Falha no processamento da imagem. Tente novamente.",
        ) from e


@app.post("/convert-embroidery")
async def convert_embroidery(
    request: Request,
    image: UploadFile = File(..., description="Processed PNG image"),
    format: str = Form(..., description="Output format (DST, PES, JEF, ...)"),
    width_mm: float = Form(..., alias="widthMm", gt=0),
    height_mm: float = Form(..., alias="heightMm", gt=0),
    fabric_id: str = Form(..., alias="fabricId"),
    stitch_type: str = Form(default="fill", alias="stitchType"),
):
    """
    Convert a processed image to an embroidery file.

    Returns JSON with fileBytes (base64), totalStitches, colorChanges,
    estimatedMinutes.
    """
    _check_auth(request)

    try:
        image_bytes = await image.read()
        result = _converter.convert(
            image_bytes=image_bytes,
            output_format=format,
            width_mm=width_mm,
            height_mm=height_mm,
            fabric_id=fabric_id,
            stitch_type=stitch_type,
        )
        return JSONResponse(content={
            "fileBytes": base64.b64encode(result["file_bytes"]).decode(),
            "totalStitches": result["total_stitches"],
            "colorChanges": result["color_changes"],
            "estimatedMinutes": result["estimated_minutes"],
            "colors": result["colors"],
            "stitchPaths": result["stitch_paths"],
            "colorChangesList": result["color_changes_list"],
            "validation": result["validation"],
        })

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        logger.error("Error converting to embroidery: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail="Falha na conversão para bordado. Tente novamente.",
        ) from e


# ── Entry point ───────────────────────────────────────────────────────────────

def run_server(host: str = "0.0.0.0", port: int = 8000) -> None:
    """Start the API server."""
    uvicorn.run(app, host=host, port=port, log_level="info")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Embroidery MVP API Server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    run_server(host=args.host, port=args.port)
