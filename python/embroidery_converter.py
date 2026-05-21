"""
Embroidery Converter Module

Converts processed images to embroidery files using pyembroidery.

Supported output formats:
    DST, PES, JEF, EXP, HUS, VIP, VP3, XXX, SEW, CSD, EMB, OFM

Dependencies:
    - pyembroidery: embroidery file format library
    - Pillow (PIL): image I/O
    - numpy: array operations
"""

import io
import logging
import math
import tempfile
import os
from typing import Any

import numpy as np
import pyembroidery
from PIL import Image

logger = logging.getLogger(__name__)

# Supported output formats
SUPPORTED_FORMATS = {
    "DST", "PES", "JEF", "EXP", "HUS", "VIP",
    "VP3", "XXX", "SEW", "CSD", "EMB", "OFM",
}

# Fabric stitch density (stitches per mm²) — midpoint of each range
FABRIC_DENSITY = {
    "knit":   4.0,   # 3.5–4.5
    "cotton": 5.0,   # 4.5–5.5
    "towel":  6.25,  # 5.5–7.0
}

# Default stitch length in mm
DEFAULT_STITCH_LENGTH_MM = 3.0

# Embroidery unit: 1 unit = 0.1 mm
UNITS_PER_MM = 10


class EmbroideryConverter:
    """
    Converts a processed RGBA image to an embroidery design file.

    The conversion pipeline:
    1. Parse the image and extract unique colors
    2. For each color, trace the filled regions as stitch paths
    3. Apply density and stitch length based on fabric type
    4. Write the design to the requested format using pyembroidery
    """

    def convert(
        self,
        image_bytes: bytes,
        output_format: str,
        width_mm: float,
        height_mm: float,
        fabric_id: str,
    ) -> dict[str, Any]:
        """
        Convert a processed image to an embroidery file.

        Args:
            image_bytes: Processed PNG image bytes (RGBA with transparency).
            output_format: Target format extension (e.g., "DST", "PES").
            width_mm: Desired design width in millimeters.
            height_mm: Desired design height in millimeters.
            fabric_id: Fabric type ID ("knit", "cotton", or "towel").

        Returns:
            dict with keys:
                - file_bytes (bytes): The embroidery file bytes.
                - total_stitches (int): Total stitch count.
                - color_changes (int): Number of color changes.
                - estimated_minutes (float): Estimated embroidery time.
                - colors (list[int]): ARGB color values used.
                - stitch_paths (list[dict]): Stitch path data for preview.
                - color_changes_list (list[dict]): Color change events.

        Raises:
            ValueError: If parameters are invalid.
            RuntimeError: If conversion fails.
        """
        fmt = output_format.upper()
        if fmt not in SUPPORTED_FORMATS:
            raise ValueError(
                f"Formato não suportado: {output_format}. "
                f"Use: {', '.join(sorted(SUPPORTED_FORMATS))}"
            )

        if width_mm <= 0 or height_mm <= 0:
            raise ValueError("As dimensões do design devem ser maiores que zero.")

        density = FABRIC_DENSITY.get(fabric_id, FABRIC_DENSITY["cotton"])
        stitch_length_mm = _stitch_length_for_density(density)

        # Load image
        try:
            pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
        except Exception as e:
            raise ValueError(f"Não foi possível abrir a imagem: {e}") from e

        # Scale image to target dimensions
        target_w_px = max(1, int(width_mm * 10))   # 10 px per mm
        target_h_px = max(1, int(height_mm * 10))
        pil_image = pil_image.resize((target_w_px, target_h_px), Image.LANCZOS)

        rgba = np.array(pil_image, dtype=np.uint8)
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]

        # Find unique colors (ignoring transparent pixels)
        mask = alpha > 10
        if not mask.any():
            raise ValueError(
                "A imagem não tem pixels visíveis. "
                "Execute a limpeza de arte antes de gerar o bordado."
            )

        visible_pixels = rgb[mask]
        unique_colors = np.unique(visible_pixels, axis=0)

        # Build pyembroidery pattern
        pattern = pyembroidery.EmbPattern()
        pattern.metadata("name", "Embroidery MVP Design")

        stitch_length_units = int(stitch_length_mm * UNITS_PER_MM)
        total_stitches = 0
        color_change_count = 0
        stitch_paths = []
        color_changes_list = []
        argb_colors = []

        for color_idx, color_rgb in enumerate(unique_colors):
            r, g, b = int(color_rgb[0]), int(color_rgb[1]), int(color_rgb[2])
            argb = (0xFF << 24) | (r << 16) | (g << 8) | b
            argb_colors.append(argb)

            # Add color to pattern
            pattern.add_thread({
                "color": (r << 16) | (g << 8) | b,
                "name": f"Color {color_idx + 1}",
            })

            if color_idx > 0:
                pattern.add_command(pyembroidery.COLOR_CHANGE)
                color_changes_list.append({
                    "stitchIndex": total_stitches,
                    "fromColorIndex": color_idx - 1,
                    "toColorIndex": color_idx,
                })
                color_change_count += 1

            # Find pixels of this color
            color_mask = (
                mask &
                (rgb[:, :, 0] == r) &
                (rgb[:, :, 1] == g) &
                (rgb[:, :, 2] == b)
            )

            # Generate fill stitches by scanning rows
            path_points = []
            ys, xs = np.where(color_mask)

            if len(ys) == 0:
                continue

            # Group by row and create horizontal stitch runs
            row_groups: dict[int, list[int]] = {}
            for y, x in zip(ys.tolist(), xs.tolist()):
                row_groups.setdefault(y, []).append(x)

            stitch_spacing_px = max(1, int(stitch_length_units / UNITS_PER_MM))
            path_stitch_count = 0

            for row_y in sorted(row_groups.keys()):
                row_xs = sorted(row_groups[row_y])
                # Sample stitches along the row
                for x in row_xs[::stitch_spacing_px]:
                    # Convert pixel coords to embroidery units
                    eu_x = int(x * UNITS_PER_MM / 10)
                    eu_y = int(row_y * UNITS_PER_MM / 10)
                    pattern.add_stitch_absolute(pyembroidery.STITCH, eu_x, eu_y)
                    path_points.extend([float(eu_x), float(eu_y)])
                    path_stitch_count += 1
                    total_stitches += 1

            stitch_paths.append({
                "colorIndex": color_idx,
                "stitchCount": path_stitch_count,
                "points": path_points,
            })

        pattern.add_command(pyembroidery.END)

        # Write to temp file and read back bytes
        with tempfile.NamedTemporaryFile(
            suffix=f".{fmt.lower()}", delete=False
        ) as tmp:
            tmp_path = tmp.name

        try:
            pyembroidery.write(pattern, tmp_path)
            with open(tmp_path, "rb") as f:
                file_bytes = f.read()
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        # Estimate embroidery time: ~500 stitches per minute
        estimated_minutes = total_stitches / 500.0

        logger.info(
            "Conversion complete: %d stitches, %d colors, %d color changes, "
            "format=%s, estimated=%.1f min",
            total_stitches,
            len(unique_colors),
            color_change_count,
            fmt,
            estimated_minutes,
        )

        return {
            "file_bytes": file_bytes,
            "total_stitches": total_stitches,
            "color_changes": color_change_count,
            "estimated_minutes": estimated_minutes,
            "colors": argb_colors,
            "stitch_paths": stitch_paths,
            "color_changes_list": color_changes_list,
        }


def _stitch_length_for_density(density: float) -> float:
    """
    Calculate stitch length in mm from density (stitches/mm²).

    Higher density → shorter stitches.
    """
    if density <= 0:
        return DEFAULT_STITCH_LENGTH_MM
    # Approximate: length ≈ 1 / sqrt(density)
    return max(1.5, min(5.0, 1.0 / math.sqrt(density / 10.0)))
