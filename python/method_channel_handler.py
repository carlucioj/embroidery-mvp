"""
MethodChannel Handler

Handles JSON-based communication between Flutter Desktop and Python.

Protocol:
    Flutter sends a JSON line to stdin:
        {"id": "1", "method": "processImage", "args": {"imageBytes": "<base64>", "maxColors": 8}}

    Python responds with a JSON line to stdout:
        {"id": "1", "result": "<base64 PNG bytes>"}
        or
        {"id": "1", "error": "Error message"}

    Each message is a single line terminated by newline.
"""

import base64
import json
import logging
import sys
from typing import Any

from image_processor import ImageProcessor
from embroidery_converter import EmbroideryConverter

logger = logging.getLogger(__name__)


class MethodChannelHandler:
    """
    Reads JSON requests from stdin and writes JSON responses to stdout.

    Runs in a loop until stdin is closed or an unrecoverable error occurs.
    """

    def __init__(self) -> None:
        self._processor = ImageProcessor()
        self._converter = EmbroideryConverter()

    def run(self) -> None:
        """Main loop: read requests, dispatch, write responses."""
        logger.info("MethodChannel handler started — waiting for requests")

        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            try:
                request = json.loads(line)
            except json.JSONDecodeError as e:
                self._write_error(None, f"Invalid JSON: {e}")
                continue

            request_id = request.get("id")
            method = request.get("method", "")
            args = request.get("args", {})

            try:
                result = self._dispatch(method, args)
                self._write_result(request_id, result)
            except (ValueError, RuntimeError) as e:
                logger.warning("Request %s failed: %s", request_id, e)
                self._write_error(request_id, str(e))
            except Exception as e:
                logger.error("Unexpected error for request %s: %s", request_id, e, exc_info=True)
                self._write_error(request_id, "Erro interno no processamento.")

    def _dispatch(self, method: str, args: dict) -> Any:
        """Route a method call to the appropriate handler."""
        if method == "processImage":
            return self._handle_process_image(args)
        elif method == "convertToEmbroidery":
            return self._handle_convert_to_embroidery(args)
        elif method == "validateCapabilities":
            return self._handle_validate_capabilities()
        else:
            raise ValueError(f"Método desconhecido: {method}")

    def _handle_process_image(self, args: dict) -> str:
        """Process an image and return base64-encoded PNG bytes."""
        image_b64 = args.get("imageBytes")
        if not image_b64:
            raise ValueError("imageBytes é obrigatório.")

        image_bytes = base64.b64decode(image_b64)
        max_colors = int(args.get("maxColors", 8))
        remove_background = bool(args.get("removeBackground", True))
        mode = str(args.get("mode", "basic"))

        result = self._processor.process_image(
            image_bytes=image_bytes,
            max_colors=max_colors,
            remove_background=remove_background,
            mode=mode,
        )

        return base64.b64encode(result["image_bytes"]).decode("ascii")

    def _handle_convert_to_embroidery(self, args: dict) -> dict:
        """Convert a processed image to an embroidery file."""
        image_b64 = args.get("imageBytes")
        if not image_b64:
            raise ValueError("imageBytes é obrigatório.")

        image_bytes = base64.b64decode(image_b64)
        output_format = args.get("format", "DST")
        width_mm = float(args.get("widthMm", 100))
        height_mm = float(args.get("heightMm", 100))
        fabric_id = args.get("fabricId", "cotton")

        stitch_type = args.get("stitchType", "fill")

        result = self._converter.convert(
            image_bytes=image_bytes,
            output_format=output_format,
            width_mm=width_mm,
            height_mm=height_mm,
            fabric_id=fabric_id,
            stitch_type=stitch_type,
        )

        # Encode file bytes as base64 for JSON transport
        return {
            "fileBytes": base64.b64encode(result["file_bytes"]).decode("ascii"),
            "totalStitches": result["total_stitches"],
            "colorChanges": result["color_changes"],
            "estimatedMinutes": result["estimated_minutes"],
            "colors": result["colors"],
            "stitchPaths": result["stitch_paths"],
            "colorChangesList": result["color_changes_list"],
            "validation": result["validation"],
        }

    def _handle_validate_capabilities(self) -> bool:
        """Check that the Python backend is operational."""
        try:
            # Quick smoke test: process a 1x1 white pixel
            from PIL import Image
            import io
            img = Image.new("RGBA", (1, 1), (255, 255, 255, 255))
            buf = io.BytesIO()
            img.save(buf, format="PNG")
            self._processor.process_image(buf.getvalue(), max_colors=1)  # result ignored
            return True
        except Exception as e:
            logger.warning("Capability check failed: %s", e)
            return False

    def _write_result(self, request_id: Any, result: Any) -> None:
        """Write a success response to stdout."""
        response = {"id": request_id, "result": result}
        print(json.dumps(response), flush=True)

    def _write_error(self, request_id: Any, message: str) -> None:
        """Write an error response to stdout."""
        response = {"id": request_id, "error": message}
        print(json.dumps(response), flush=True)
