"""
Embroidery MVP — Python Backend Entry Point

This module serves as the entry point for the Python backend.
It can run in two modes:

1. MethodChannel mode (Desktop): Listens on stdin/stdout for Flutter
   MethodChannel calls and processes them synchronously.

2. HTTP server mode (Mobile API): Starts a FastAPI server that exposes
   REST endpoints for remote processing.

Usage:
    # MethodChannel mode (default, used by Flutter Desktop)
    python main.py

    # HTTP server mode
    python main.py --server --host 0.0.0.0 --port 8000
"""

import sys
import argparse
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[logging.StreamHandler(sys.stderr)],
)

logger = logging.getLogger(__name__)


def run_method_channel_mode() -> None:
    """Run in MethodChannel mode for Flutter Desktop integration."""
    from method_channel_handler import MethodChannelHandler

    logger.info("Starting in MethodChannel mode")
    handler = MethodChannelHandler()
    handler.run()


def run_http_server_mode(host: str, port: int) -> None:
    """Run as HTTP server for Mobile API."""
    import uvicorn
    from fastapi import FastAPI, File, UploadFile, Form
    from fastapi.responses import JSONResponse, Response
    import base64

    from image_processor import ImageProcessor
    from embroidery_converter import EmbroideryConverter

    app = FastAPI(
        title="Embroidery MVP Processing API",
        description="Remote processing API for the Embroidery MVP mobile app",
        version="0.1.0",
    )

    processor = ImageProcessor()
    converter = EmbroideryConverter()

    @app.get("/health")
    async def health_check():
        """Health check endpoint."""
        return {"status": "ok", "version": "0.1.0"}

    @app.post("/process-image")
    async def process_image(
        image: UploadFile = File(...),
        max_colors: int = Form(default=8),
        remove_background: bool = Form(default=True, alias="removeBackground"),
    ):
        """
        Remove background and reduce colors from an uploaded image.

        Returns the processed image as PNG bytes.
        """
        try:
            image_bytes = await image.read()
            result = processor.process_image(
                image_bytes=image_bytes,
                max_colors=max_colors,
                remove_background=remove_background,
            )
            return Response(
                content=result,
                media_type="image/png",
            )
        except ValueError as e:
            return JSONResponse(
                status_code=400,
                content={"error": str(e)},
            )
        except Exception as e:
            logger.error("Error processing image: %s", e, exc_info=True)
            return JSONResponse(
                status_code=500,
                content={"error": "Falha no processamento da imagem"},
            )

    @app.post("/convert-embroidery")
    async def convert_embroidery(
        image: UploadFile = File(...),
        format: str = Form(...),
        width_mm: float = Form(..., alias="widthMm"),
        height_mm: float = Form(..., alias="heightMm"),
        fabric_id: str = Form(..., alias="fabricId"),
        stitch_type: str = Form(default="fill", alias="stitchType"),
    ):
        """
        Convert a processed image to an embroidery file.

        Returns JSON with fileBytes (base64), totalStitches, colorChanges,
        estimatedMinutes, colors, stitchPaths, colorChangesList, validation.
        """
        try:
            image_bytes = await image.read()
            result = converter.convert(
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
            return JSONResponse(
                status_code=400,
                content={"error": str(e)},
            )
        except Exception as e:
            logger.error("Error converting to embroidery: %s", e, exc_info=True)
            return JSONResponse(
                status_code=500,
                content={"error": "Falha na conversão para bordado"},
            )

    logger.info("Starting HTTP server on %s:%d", host, port)
    uvicorn.run(app, host=host, port=port)


def main() -> None:
    """Parse arguments and start the appropriate mode."""
    parser = argparse.ArgumentParser(
        description="Embroidery MVP Python Backend",
    )
    parser.add_argument(
        "--server",
        action="store_true",
        help="Run as HTTP server (for Mobile API)",
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="HTTP server host (default: 0.0.0.0)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="HTTP server port (default: 8000)",
    )

    args = parser.parse_args()

    if args.server:
        run_http_server_mode(host=args.host, port=args.port)
    else:
        run_method_channel_mode()


if __name__ == "__main__":
    main()
