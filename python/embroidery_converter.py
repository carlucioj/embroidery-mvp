"""
Embroidery Converter Module

Converts processed images to embroidery files using pyembroidery.

Fill algorithm: diagonal tatami fill (boustrophedon) + contour outline.
This replaces the v1 horizontal scanline approach which produced striped output.

Outline algorithm: vtracer (if installed) or cv2.findContours (fallback).
vtracer converts the binary mask to smooth SVG polygons, producing cleaner
embroidery outlines without pixel-staircase jaggedness.

Supported output formats:
    DST, PES, JEF, EXP, HUS, VIP, VP3, XXX, SEW, CSD, EMB, OFM

Dependencies (required):
    - pyembroidery: embroidery file format library
    - Pillow (PIL): image I/O
    - numpy: array operations
    - opencv-python-headless: contour extraction and mask rotation

Dependencies (optional):
    - vtracer: smooth polygon outline tracing (pip install vtracer)
      Falls back to cv2.findContours if not installed.
"""

import cv2
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

# Fill angle (degrees). 45° gives the classic diagonal tatami look.
FILL_ANGLE_DEG = 45.0

# Max gap (in embroidery units) before inserting a TRIM+JUMP
TRIM_THRESHOLD_EU = 30  # 3 mm


class EmbroideryConverter:
    """
    Converts a processed RGBA image to an embroidery design file.

    Pipeline:
    1. Parse the image and extract unique colors.
    2. For each color region:
       a. Tatami fill: diagonal scanlines alternating direction (boustrophedon).
       b. Contour outline: smooth polygon via vtracer (or cv2 fallback).
    3. Write the design using pyembroidery.
    """

    def convert(
        self,
        image_bytes: bytes,
        output_format: str,
        width_mm: float,
        height_mm: float,
        fabric_id: str,
        stitch_type: str = "fill",
    ) -> dict[str, Any]:
        """
        Convert a processed image to an embroidery file.

        Args:
            image_bytes: Processed PNG image bytes (RGBA with transparency).
            output_format: Target format extension (e.g., "DST", "PES").
            width_mm: Desired design width in millimeters.
            height_mm: Desired design height in millimeters.
            fabric_id: Fabric type ID ("knit", "cotton", or "towel").
            stitch_type: How to stitch each color region:
                - "fill"    — diagonal tatami fill (45°) + contour outline
                - "outline" — running stitch along boundary only
                - "satin"   — dense horizontal fill (boustrophedon at 0°), no outline

        Returns:
            dict with keys:
                - file_bytes (bytes): The embroidery file bytes.
                - total_stitches (int): Total stitch count.
                - color_changes (int): Number of color changes.
                - estimated_minutes (float): Estimated embroidery time.
                - colors (list[int]): ARGB color values used.
                - stitch_paths (list[dict]): Stitch path data for canvas preview.
                - color_changes_list (list[dict]): Color change events.
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
        stitch_spacing_px = max(1, round(stitch_length_mm * 10))  # 10 px per mm

        try:
            pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
        except Exception as e:
            raise ValueError(f"Não foi possível abrir a imagem: {e}") from e

        # Scale image to target dimensions (10 px per mm)
        target_w_px = max(1, int(width_mm * 10))
        target_h_px = max(1, int(height_mm * 10))
        # NEAREST preserves quantized color boundaries — LANCZOS would create new anti-aliased colors
        pil_image = pil_image.resize((target_w_px, target_h_px), Image.NEAREST)

        rgba = np.array(pil_image, dtype=np.uint8)
        alpha = rgba[:, :, 3]
        rgb = rgba[:, :, :3]

        mask = alpha > 10
        if not mask.any():
            raise ValueError(
                "A imagem não tem pixels visíveis. "
                "Execute a limpeza de arte antes de gerar o bordado."
            )

        visible_pixels = rgb[mask]
        unique_colors = np.unique(visible_pixels, axis=0)

        pattern = pyembroidery.EmbPattern()
        pattern.metadata("name", "Embroidery MVP Design")

        total_stitches = 0
        color_change_count = 0
        stitch_paths: list[dict] = []
        color_changes_list: list[dict] = []
        argb_colors: list[int] = []

        for color_idx, color_rgb in enumerate(unique_colors):
            r, g, b = int(color_rgb[0]), int(color_rgb[1]), int(color_rgb[2])
            argb = (0xFF << 24) | (r << 16) | (g << 8) | b
            argb_colors.append(argb)

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

            color_mask = (
                mask
                & (rgb[:, :, 0] == r)
                & (rgb[:, :, 1] == g)
                & (rgb[:, :, 2] == b)
            )

            # Generate stitches based on requested type
            if stitch_type == "outline":
                fill_pts = []
                outline_pts = _vectorize_outline(color_mask, stitch_spacing_px)
            elif stitch_type == "satin":
                # Dense horizontal fill (0°) — approximates satin for narrow shapes
                fill_pts = _tatami_fill(color_mask, max(1, stitch_spacing_px // 2), 0.0)
                outline_pts = []
            else:
                # Default: "fill" — diagonal tatami + smooth contour outline
                fill_pts = _tatami_fill(color_mask, stitch_spacing_px, FILL_ANGLE_DEG)
                outline_pts = _vectorize_outline(color_mask, stitch_spacing_px)

            preview_points: list[float] = []
            prev_eu: tuple[int, int] | None = None

            for segment in (fill_pts, outline_pts):
                first_in_segment = True
                for i in range(0, len(segment) - 1, 2):
                    px, py = segment[i], segment[i + 1]
                    eu_x = int(px * UNITS_PER_MM / 10)
                    eu_y = int(py * UNITS_PER_MM / 10)

                    if prev_eu is not None:
                        dx = eu_x - prev_eu[0]
                        dy = eu_y - prev_eu[1]
                        dist = math.isqrt(dx * dx + dy * dy)
                        if dist > TRIM_THRESHOLD_EU or first_in_segment:
                            pattern.add_command(pyembroidery.TRIM)
                            pattern.add_command(pyembroidery.JUMP)

                    pattern.add_stitch_absolute(pyembroidery.STITCH, eu_x, eu_y)
                    preview_points.extend([float(eu_x), float(eu_y)])
                    total_stitches += 1
                    prev_eu = (eu_x, eu_y)
                    first_in_segment = False

            stitch_paths.append({
                "colorIndex": color_idx,
                "stitchCount": len(preview_points) // 2,
                "points": preview_points,
            })

        pattern.add_command(pyembroidery.END)

        # Write to temp file and read back bytes
        with tempfile.NamedTemporaryFile(suffix=f".{fmt.lower()}", delete=False) as tmp:
            tmp_path = tmp.name

        try:
            pyembroidery.write(pattern, tmp_path)
            with open(tmp_path, "rb") as f:
                file_bytes = f.read()
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        estimated_minutes = total_stitches / 500.0

        validation = self._validate_output(
            fmt=fmt,
            file_bytes=file_bytes,
            total_stitches=total_stitches,
            color_count=len(unique_colors),
        )

        logger.info(
            "Conversion complete: %d stitches, %d colors, %d color changes, "
            "format=%s, estimated=%.1f min, validation=%s",
            total_stitches,
            len(unique_colors),
            color_change_count,
            fmt,
            estimated_minutes,
            validation["severity"],
        )

        return {
            "file_bytes": file_bytes,
            "total_stitches": total_stitches,
            "color_changes": color_change_count,
            "estimated_minutes": estimated_minutes,
            "colors": argb_colors,
            "stitch_paths": stitch_paths,
            "color_changes_list": color_changes_list,
            "validation": validation,
        }

    def _validate_output(
        self,
        fmt: str,
        file_bytes: bytes,
        total_stitches: int,
        color_count: int,
    ) -> dict[str, Any]:
        """Validate generated output against embroidery machine specs."""
        issues: list[dict[str, str]] = []

        if color_count == 0:
            issues.append({
                "code": "NO_COLORS",
                "message": "Nenhuma cor encontrada no design.",
                "severity": "error",
            })
        elif color_count > 64:
            issues.append({
                "code": "TOO_MANY_COLORS",
                "message": f"{color_count} cores encontradas. O limite máximo suportado é 64.",
                "severity": "error",
            })
        elif color_count > 16:
            issues.append({
                "code": "COLORS_EXCEED_CONSUMER_LIMIT",
                "message": (
                    f"{color_count} cores — máquinas Brother/Babylock consumer suportam até 16. "
                    "Reduza as cores na tela de limpeza de imagem."
                ),
                "severity": "warning",
            })

        if total_stitches == 0:
            issues.append({
                "code": "NO_STITCHES",
                "message": "Nenhum ponto foi gerado. Verifique se a imagem tem pixels visíveis.",
                "severity": "error",
            })
        elif total_stitches > 500_000:
            issues.append({
                "code": "STITCH_COUNT_HIGH",
                "message": (
                    f"{total_stitches:,} pontos — pode exceder o limite de algumas máquinas (500K). "
                    "Reduza o tamanho do design ou o número de cores."
                ),
                "severity": "warning",
            })

        if fmt == "PES" and (len(file_bytes) < 4 or file_bytes[:4] != b"#PES"):
            issues.append({
                "code": "PES_MAGIC_INVALID",
                "message": "Arquivo .PES gerado sem cabeçalho correto (#PES). O arquivo pode estar corrompido.",
                "severity": "error",
            })

        has_error = any(i["severity"] == "error" for i in issues)
        has_warning = any(i["severity"] == "warning" for i in issues)
        overall = "error" if has_error else ("warning" if has_warning else "ok")

        return {"severity": overall, "issues": issues}


# ── Fill algorithms ────────────────────────────────────────────────────────────


def _tatami_fill(
    color_mask: np.ndarray,
    stitch_spacing_px: int,
    angle_deg: float = 45.0,
) -> list[float]:
    """
    Generate tatami-style diagonal fill stitches (boustrophedon).

    Rotates the mask so fill lines align with the horizontal axis, then scans
    row-by-row alternating direction. Result: connected diagonal zigzag instead
    of the striped look produced by independent horizontal scanlines.
    """
    h, w = color_mask.shape
    if not color_mask.any():
        return []

    cx, cy = w / 2.0, h / 2.0

    rot_mat = cv2.getRotationMatrix2D((cx, cy), angle_deg, 1.0)
    inv_rot = cv2.getRotationMatrix2D((cx, cy), -angle_deg, 1.0)

    rotated = cv2.warpAffine(
        color_mask.astype(np.uint8) * 255,
        rot_mat,
        (w, h),
        flags=cv2.INTER_NEAREST,
    )

    path_points: list[float] = []
    flip = False

    for y in range(0, h, stitch_spacing_px):
        row = rotated[y]
        xs_valid = np.where(row > 127)[0]
        if len(xs_valid) == 0:
            continue

        # Split connected x-runs to avoid stitching over transparent gaps
        runs = _split_runs(xs_valid, stitch_spacing_px * 3)

        for xs_run in runs:
            sampled = xs_run[::stitch_spacing_px]
            if flip:
                sampled = sampled[::-1]

            for x in sampled:
                # Back-project to original image coordinates
                x_orig = inv_rot[0, 0] * x + inv_rot[0, 1] * y + inv_rot[0, 2]
                y_orig = inv_rot[1, 0] * x + inv_rot[1, 1] * y + inv_rot[1, 2]
                xi, yi = int(round(x_orig)), int(round(y_orig))

                if 0 <= xi < w and 0 <= yi < h:
                    path_points.extend([float(xi), float(yi)])

        flip = not flip

    return path_points


def _trace_outline(
    color_mask: np.ndarray,
    stitch_spacing_px: int,
) -> list[float]:
    """
    Trace the outer contour of a color region as running stitches.

    Samples the contour at stitch_spacing_px intervals so the resulting
    stitches match the fill density.
    """
    mask_u8 = color_mask.astype(np.uint8) * 255

    # Dilate slightly so the outline sits just outside the fill
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    mask_u8 = cv2.dilate(mask_u8, kernel, iterations=1)

    contours, _ = cv2.findContours(mask_u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

    path_points: list[float] = []

    for contour in contours:
        if len(contour) < 2:
            continue

        pts = contour.reshape(-1, 2)
        prev = pts[0].astype(float)
        path_points.extend([float(pts[0][0]), float(pts[0][1])])
        accumulated = 0.0

        for pt in pts[1:]:
            pt_f = pt.astype(float)
            accumulated += float(np.linalg.norm(pt_f - prev))
            if accumulated >= stitch_spacing_px:
                path_points.extend([float(pt[0]), float(pt[1])])
                accumulated = 0.0
            prev = pt_f

        # Close the contour
        if len(path_points) >= 2:
            path_points.extend([float(pts[0][0]), float(pts[0][1])])

    return path_points


def _vectorize_outline(
    color_mask: np.ndarray,
    stitch_spacing_px: int,
) -> list[float]:
    """
    Trace the outer contour as running stitches.

    Attempts to use vtracer (smooth polygon paths) when available.
    Falls back to cv2.findContours if vtracer is not installed or fails.

    vtracer produces cleaner outlines by fitting polygons to the raster mask,
    eliminating the pixel-staircase jaggedness of cv2 contours.
    """
    try:
        import vtracer as _vtracer  # optional dependency
    except ImportError:
        return _trace_outline(color_mask, stitch_spacing_px)

    try:
        binary_img = Image.fromarray((color_mask.astype(np.uint8) * 255), mode='L')
        buf = io.BytesIO()
        binary_img.save(buf, format='PNG')

        svg_str = _vtracer.convert_raw_image_to_svg(
            buf.getvalue(),
            colormode='binary',
            # Ignore noise specks smaller than ~half a stitch spacing
            filter_speckle=max(2, stitch_spacing_px // 2),
            # Polygon mode: emits only M/L/Z commands — no bezier splines.
            # Keeps the parser simple and avoids over-smoothing fine details.
            mode='none',
            corner_threshold=60,   # lower = more corners kept
            length_threshold=4.0,  # minimum segment length (px) to preserve
            path_precision=2,      # decimal places in SVG coordinates
        )

        polygons = _parse_svg_polygons(svg_str)
        if not polygons:
            return _trace_outline(color_mask, stitch_spacing_px)

        path_points: list[float] = []
        for polygon in polygons:
            if len(polygon) < 2:
                continue
            n = len(polygon)
            for i in range(n):
                x0, y0 = polygon[i]
                x1, y1 = polygon[(i + 1) % n]
                path_points.extend(
                    _discretize_segment(x0, y0, x1, y1, stitch_spacing_px)
                )
            # Close the contour back to the start point
            if path_points:
                path_points.extend([polygon[0][0], polygon[0][1]])

        return path_points if path_points else _trace_outline(color_mask, stitch_spacing_px)

    except Exception as exc:
        logger.debug("vtracer outline failed (%s) — falling back to cv2", exc)
        return _trace_outline(color_mask, stitch_spacing_px)


def _parse_svg_polygons(svg_str: str) -> list[list[tuple[float, float]]]:
    """
    Extract polygon point lists from SVG path `d` attributes.

    vtracer polygon mode (mode='none') emits only M (moveto), L (lineto),
    and Z (closepath) commands — both absolute and relative variants.
    """
    import re

    number_pat = r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?'
    polygons: list[list[tuple[float, float]]] = []

    for d_attr in re.findall(r'\bd="([^"]+)"', svg_str):
        tokens = re.findall(rf'[MmLlZz]|{number_pat}', d_attr)
        polygon: list[tuple[float, float]] = []
        cmd = 'M'
        i = 0

        while i < len(tokens):
            t = tokens[i]
            if t in 'MmLlZz':
                cmd = t
                i += 1
                continue

            if cmd in ('Z', 'z'):
                i += 1
                continue

            # Expect two consecutive numbers for a coordinate pair
            if i + 1 < len(tokens) and tokens[i + 1] not in 'MmLlZz':
                x, y = float(tokens[i]), float(tokens[i + 1])
                # Relative commands offset from current position
                if cmd in ('m', 'l') and polygon:
                    x += polygon[-1][0]
                    y += polygon[-1][1]
                polygon.append((x, y))
                i += 2
            else:
                i += 1  # skip malformed token

        if len(polygon) >= 3:
            polygons.append(polygon)

    return polygons


def _discretize_segment(
    x0: float, y0: float,
    x1: float, y1: float,
    spacing: int,
) -> list[float]:
    """Sample stitch points along a line segment at `spacing` pixel intervals."""
    dx, dy = x1 - x0, y1 - y0
    length = math.sqrt(dx * dx + dy * dy)
    if length < 1e-6:
        return [x0, y0]

    steps = max(1, int(length / spacing))
    pts: list[float] = []
    for k in range(steps):
        t = k / steps
        pts.append(x0 + dx * t)
        pts.append(y0 + dy * t)
    return pts


def _split_runs(xs: np.ndarray, max_gap: int) -> list[np.ndarray]:
    """Split a sorted array of x-coords into contiguous runs separated by gaps > max_gap."""
    if len(xs) == 0:
        return []

    splits = np.where(np.diff(xs) > max_gap)[0] + 1
    return np.split(xs, splits)


def _stitch_length_for_density(density: float) -> float:
    """
    Calculate stitch length in mm from density (stitches/mm²).

    Higher density → shorter stitches.
    """
    if density <= 0:
        return DEFAULT_STITCH_LENGTH_MM
    # Approximate: length ≈ 1 / sqrt(density)
    return max(1.5, min(5.0, 1.0 / math.sqrt(density / 10.0)))
