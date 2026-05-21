"""
Image Processor Module

Handles background removal and color reduction for embroidery conversion.

Dependencies:
    - rembg: background removal using U2Net model
    - opencv-python (cv2): image processing and color quantization
    - Pillow (PIL): image I/O and format handling
    - numpy: array operations
"""

import io
import logging
from typing import Optional

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# Supported input formats
SUPPORTED_EXTENSIONS = {"jpg", "jpeg", "png", "bmp", "webp"}
MAX_FILE_SIZE_BYTES = 20 * 1024 * 1024  # 20 MB


class ImageProcessor:
    """
    Processes images for embroidery conversion.

    Steps:
    1. Validate input (format, size)
    2. Remove background using rembg
    3. Reduce colors using K-means clustering (OpenCV)
    4. Return processed PNG bytes with transparency
    """

    def __init__(self, use_rembg: bool = True) -> None:
        self._use_rembg = use_rembg
        self._rembg_session: Optional[object] = None

    def _get_rembg_session(self):
        """Lazy-load the rembg session to avoid slow startup."""
        if self._rembg_session is None and self._use_rembg:
            try:
                from rembg import new_session
                self._rembg_session = new_session("u2net")
                logger.info("rembg session loaded (u2net)")
            except ImportError:
                logger.warning("rembg not available — background removal disabled")
                self._use_rembg = False
        return self._rembg_session

    def process_image(
        self,
        image_bytes: bytes,
        max_colors: int = 8,
    ) -> bytes:
        """
        Remove background and reduce colors from an image.

        Args:
            image_bytes: Raw image bytes (JPG, PNG, BMP, or WEBP).
            max_colors: Maximum number of colors after reduction (1–32).

        Returns:
            Processed image as PNG bytes with transparent background.

        Raises:
            ValueError: If the image is invalid or too large.
            RuntimeError: If processing fails.
        """
        # ── Validate ────────────────────────────────────────────────────────
        if len(image_bytes) > MAX_FILE_SIZE_BYTES:
            size_mb = len(image_bytes) / (1024 * 1024)
            raise ValueError(
                f"Arquivo muito grande: {size_mb:.1f} MB. "
                f"O limite é {MAX_FILE_SIZE_BYTES // (1024 * 1024)} MB."
            )

        max_colors = max(1, min(32, max_colors))

        # ── Load image ──────────────────────────────────────────────────────
        try:
            pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
        except Exception as e:
            raise ValueError(f"Não foi possível abrir a imagem: {e}") from e

        logger.info(
            "Processing image: %dx%d, %d bytes",
            pil_image.width,
            pil_image.height,
            len(image_bytes),
        )

        # ── Remove background ───────────────────────────────────────────────
        if self._use_rembg:
            pil_image = self._remove_background(pil_image, image_bytes)
        else:
            logger.info("Skipping background removal (rembg not available)")

        # ── Reduce colors ───────────────────────────────────────────────────
        pil_image = self._reduce_colors(pil_image, max_colors)

        # ── Encode as PNG ───────────────────────────────────────────────────
        output = io.BytesIO()
        pil_image.save(output, format="PNG", optimize=True)
        result_bytes = output.getvalue()

        logger.info(
            "Processing complete: %d bytes output, %d colors",
            len(result_bytes),
            max_colors,
        )
        return result_bytes

    def _remove_background(self, pil_image: Image.Image, original_bytes: bytes) -> Image.Image:
        """Remove the background using rembg."""
        try:
            from rembg import remove

            session = self._get_rembg_session()
            result_bytes = remove(original_bytes, session=session)
            return Image.open(io.BytesIO(result_bytes)).convert("RGBA")
        except Exception as e:
            logger.warning("Background removal failed: %s — using original", e)
            return pil_image

    def _reduce_colors(self, pil_image: Image.Image, max_colors: int) -> Image.Image:
        """
        Reduce the number of colors using K-means clustering.

        Preserves transparency: only non-transparent pixels are clustered.
        """
        # Separate alpha channel
        rgba = np.array(pil_image, dtype=np.uint8)
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]

        # Get mask of non-transparent pixels
        mask = alpha > 10  # pixels with alpha > 10 are considered visible

        if not mask.any():
            logger.warning("Image has no visible pixels after background removal")
            return pil_image

        # Extract visible pixels for clustering
        visible_pixels = rgb[mask].astype(np.float32)

        # K-means clustering
        n_clusters = min(max_colors, len(np.unique(visible_pixels.reshape(-1, 3), axis=0)))
        n_clusters = max(1, n_clusters)

        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 20, 1.0)
        _, labels, centers = cv2.kmeans(
            visible_pixels,
            n_clusters,
            None,
            criteria,
            attempts=3,
            flags=cv2.KMEANS_RANDOM_CENTERS,
        )

        # Replace each visible pixel with its cluster center color
        centers = np.uint8(centers)
        quantized_rgb = rgb.copy()
        quantized_rgb[mask] = centers[labels.flatten()]

        # Reconstruct RGBA
        result = np.dstack([quantized_rgb, alpha])
        return Image.fromarray(result, mode="RGBA")
