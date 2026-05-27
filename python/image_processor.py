"""
Image Processor Module

Handles background removal, color reduction, and complexity analysis
for embroidery conversion.
"""

import io
import logging
from typing import Any, Optional

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

SUPPORTED_EXTENSIONS = {"jpg", "jpeg", "png", "bmp", "webp"}
MAX_FILE_SIZE_BYTES = 20 * 1024 * 1024  # 20 MB

_SCORE_SIMPLE = 30
_SCORE_MEDIUM = 60


class ImageProcessor:
    """
    Processes images for embroidery conversion.

    Steps:
    1. Validate input (format, size)
    2. Remove background using rembg (optional)
    3. Reduce colors using K-means clustering
    4. Optionally apply morphological cleanup + region simplification (mode="advanced")
    5. Analyze complexity and extract dominant colors
    """

    def __init__(self, use_rembg: bool = True) -> None:
        self._use_rembg = use_rembg
        self._rembg_session: Optional[object] = None

    def _get_rembg_session(self):
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
        remove_background: bool = True,
        mode: str = "basic",
    ) -> dict[str, Any]:
        """
        Remove background and reduce colors from an image.

        Args:
            image_bytes: Raw image bytes (JPG, PNG, BMP, or WEBP).
            max_colors: Maximum number of colors after reduction (1–32).
            remove_background: Whether to apply rembg background removal.
            mode: "basic" (fast) or "advanced" (morphological cleanup + simplification).

        Returns:
            dict with:
              - image_bytes: PNG bytes with transparent background
              - dominant_colors: list of ARGB ints (one per unique quantized color)
              - complexity: dict with level, score, unique_colors, edge_density,
                            region_count, avg_region_area_px
        """
        if len(image_bytes) > MAX_FILE_SIZE_BYTES:
            size_mb = len(image_bytes) / (1024 * 1024)
            raise ValueError(
                f"Arquivo muito grande: {size_mb:.1f} MB. "
                f"O limite é {MAX_FILE_SIZE_BYTES // (1024 * 1024)} MB."
            )

        max_colors = max(1, min(32, max_colors))

        try:
            pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
        except Exception as e:
            raise ValueError(f"Não foi possível abrir a imagem: {e}") from e

        logger.info(
            "Processing image: %dx%d, %d bytes, mode=%s",
            pil_image.width, pil_image.height, len(image_bytes), mode,
        )

        if self._use_rembg and remove_background:
            pil_image = self._remove_background(pil_image, image_bytes)

        pil_image = self._reduce_colors(pil_image, max_colors)

        if mode == "light":
            # Light: small 3×3 kernel — removes pixel-level noise without erasing thin strokes
            pil_image = self._morphological_cleanup(pil_image, kernel_size=3)
        elif mode == "advanced":
            # Advanced: larger 5×5 kernel + polygon simplification — best for photos
            pil_image = self._morphological_cleanup(pil_image, kernel_size=5)
            pil_image = self._simplify_regions(pil_image)

        rgba = np.array(pil_image, dtype=np.uint8)
        complexity = self.analyze_complexity(rgba)
        dominant_colors = self._extract_dominant_colors(rgba)

        output = io.BytesIO()
        pil_image.save(output, format="PNG", optimize=True)
        result_bytes = output.getvalue()

        logger.info(
            "Processing complete: %d bytes, %d colors, complexity=%s (score=%d)",
            len(result_bytes), max_colors, complexity["level"], complexity["score"],
        )

        return {
            "image_bytes": result_bytes,
            "dominant_colors": dominant_colors,
            "complexity": complexity,
        }

    def analyze_complexity(self, rgba: np.ndarray) -> dict[str, Any]:
        """
        Score image complexity (0–135) from a quantized RGBA array.

        Metrics:
          - unique_colors: number of distinct RGB colors in visible pixels
          - edge_density: fraction of visible pixels that are edges (Canny)
          - region_count: number of connected components
          - avg_region_area_px: average area of each region in pixels
        """
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]
        mask = alpha > 10

        if not mask.any():
            return {
                "level": "simple",
                "score": 0,
                "unique_colors": 0,
                "edge_density": 0.0,
                "region_count": 0,
                "avg_region_area_px": 0.0,
            }

        visible = rgb[mask]
        packed = (
            visible[:, 0].astype(np.int32) * 65536
            + visible[:, 1].astype(np.int32) * 256
            + visible[:, 2].astype(np.int32)
        )
        unique_colors = int(np.unique(packed).shape[0])

        gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        edges = cv2.Canny(gray, 50, 150)
        visible_pixel_count = int(mask.sum())
        edge_pixels = int((edges[mask] > 0).sum())
        edge_density = edge_pixels / max(visible_pixel_count, 1)

        mask_u8 = (mask * 255).astype(np.uint8)
        n_labels, _, stats, _ = cv2.connectedComponentsWithStats(mask_u8, connectivity=8)
        region_count = max(0, n_labels - 1)
        areas = stats[1:, cv2.CC_STAT_AREA] if region_count > 0 else np.array([0])
        avg_region_area_px = float(areas.mean()) if len(areas) > 0 else 0.0

        score = 0

        if unique_colors <= 4:
            score += 0
        elif unique_colors <= 8:
            score += 20
        elif unique_colors <= 12:
            score += 35
        else:
            score += 50

        if edge_density < 0.08:
            score += 0
        elif edge_density < 0.15:
            score += 15
        elif edge_density < 0.25:
            score += 25
        else:
            score += 35

        if region_count < 10:
            score += 0
        elif region_count < 30:
            score += 10
        elif region_count < 100:
            score += 20
        else:
            score += 30

        if avg_region_area_px > 2000:
            score += 0
        elif avg_region_area_px > 500:
            score += 5
        elif avg_region_area_px > 100:
            score += 10
        else:
            score += 20

        if score <= _SCORE_SIMPLE:
            level = "simple"
        elif score <= _SCORE_MEDIUM:
            level = "medium"
        else:
            level = "complex"

        return {
            "level": level,
            "score": score,
            "unique_colors": unique_colors,
            "edge_density": round(edge_density, 4),
            "region_count": region_count,
            "avg_region_area_px": round(avg_region_area_px, 1),
        }

    def _morphological_cleanup(self, pil_image: Image.Image, kernel_size: int = 5) -> Image.Image:
        """Remove noisy pixels per color using open+close with an ellipse kernel.

        kernel_size=3 → light (preserves thin strokes)
        kernel_size=5 → heavy (removes more noise, may erase thin strokes)
        """
        rgba = np.array(pil_image, dtype=np.uint8)
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]
        mask = alpha > 10

        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))

        visible = rgb[mask]
        packed = (
            visible[:, 0].astype(np.int32) * 65536
            + visible[:, 1].astype(np.int32) * 256
            + visible[:, 2].astype(np.int32)
        )
        unique_packed = np.unique(packed)

        result_alpha = alpha.copy()
        for packed_color in unique_packed:
            r = int((packed_color >> 16) & 0xFF)
            g = int((packed_color >> 8) & 0xFF)
            b = int(packed_color & 0xFF)
            color_mask = (
                (rgb[:, :, 0] == r) & (rgb[:, :, 1] == g) & (rgb[:, :, 2] == b) & mask
            ).astype(np.uint8) * 255

            cleaned = cv2.morphologyEx(color_mask, cv2.MORPH_OPEN, kernel)
            cleaned = cv2.morphologyEx(cleaned, cv2.MORPH_CLOSE, kernel)

            # Pixels removed by open: make transparent
            removed = (color_mask > 0) & (cleaned == 0)
            result_alpha[removed] = 0

        result = np.dstack([rgb, result_alpha])
        return Image.fromarray(result, mode="RGBA")

    def _simplify_regions(self, pil_image: Image.Image) -> Image.Image:
        """Smooth region boundaries using polygon approximation (approxPolyDP).

        Uses RETR_TREE to retrieve the full contour hierarchy so that holes
        (inner contours) are preserved — e.g. the inside of letters "O", "B",
        donuts, etc. Outer contours are filled with 255; inner contours (holes)
        are erased back to 0.
        """
        rgba = np.array(pil_image, dtype=np.uint8)
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]
        mask = alpha > 10

        visible = rgb[mask]
        packed = (
            visible[:, 0].astype(np.int32) * 65536
            + visible[:, 1].astype(np.int32) * 256
            + visible[:, 2].astype(np.int32)
        )
        unique_packed = np.unique(packed)

        result_rgb = np.zeros_like(rgb)
        result_mask = np.zeros(rgb.shape[:2], dtype=np.uint8)

        for packed_color in unique_packed:
            r = int((packed_color >> 16) & 0xFF)
            g = int((packed_color >> 8) & 0xFF)
            b = int(packed_color & 0xFF)
            color_mask = (
                (rgb[:, :, 0] == r) & (rgb[:, :, 1] == g) & (rgb[:, :, 2] == b) & mask
            ).astype(np.uint8) * 255

            # RETR_TREE preserves the full contour hierarchy.
            # hierarchy shape: (1, N, 4) — [next, prev, first_child, parent]
            contours, hierarchy = cv2.findContours(
                color_mask, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE
            )
            if not contours or hierarchy is None:
                continue

            simplified = np.zeros(rgb.shape[:2], dtype=np.uint8)
            hier = hierarchy[0]  # shape (N, 4)

            for j, contour in enumerate(contours):
                epsilon = 0.02 * cv2.arcLength(contour, True)
                approx = cv2.approxPolyDP(contour, epsilon, True)
                # Contours with no parent (hier[j][3] == -1) are outer boundaries.
                # Contours with a parent are holes — fill with 0 to punch through.
                fill_value = 0 if hier[j][3] >= 0 else 255
                cv2.fillPoly(simplified, [approx], fill_value)

            result_rgb[simplified > 0] = [r, g, b]
            result_mask = np.maximum(result_mask, simplified)

        final_alpha = np.where(result_mask > 0, alpha, np.uint8(0))
        result = np.dstack([result_rgb, final_alpha])
        return Image.fromarray(result, mode="RGBA")

    def _extract_dominant_colors(self, rgba: np.ndarray) -> list[int]:
        """Return ARGB ints for each unique quantized color (up to 16)."""
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]
        mask = alpha > 10
        if not mask.any():
            return []
        visible = rgb[mask]
        unique_colors = np.unique(visible, axis=0)
        result = []
        for color in unique_colors[:16]:
            r, g, b = int(color[0]), int(color[1]), int(color[2])
            argb = (0xFF << 24) | (r << 16) | (g << 8) | b
            result.append(argb)
        return result

    def _remove_background(self, pil_image: Image.Image, original_bytes: bytes) -> Image.Image:
        try:
            from rembg import remove
            session = self._get_rembg_session()
            result_bytes = remove(original_bytes, session=session)
            return Image.open(io.BytesIO(result_bytes)).convert("RGBA")
        except Exception as e:
            logger.warning("Background removal failed: %s — using original", e)
            return pil_image

    def _reduce_colors(self, pil_image: Image.Image, max_colors: int) -> Image.Image:
        """Reduce colors using K-means clustering. Preserves transparency."""
        rgba = np.array(pil_image, dtype=np.uint8)
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]
        mask = alpha > 10

        if not mask.any():
            logger.warning("Image has no visible pixels after background removal")
            return pil_image

        visible_pixels = rgb[mask].astype(np.float32)
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

        centers = np.uint8(centers)
        quantized_rgb = rgb.copy()
        quantized_rgb[mask] = centers[labels.flatten()]

        result = np.dstack([quantized_rgb, alpha])
        return Image.fromarray(result, mode="RGBA")
