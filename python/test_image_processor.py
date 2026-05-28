"""
Tests for image_processor.py — complexity analysis, cleanup, and process_image().
Run with: python test_image_processor.py
"""

import io
import sys
import traceback

import cv2
import numpy as np
from PIL import Image

from image_processor import ImageProcessor, _SCORE_SIMPLE, _SCORE_MEDIUM


# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_png(rgba_array: np.ndarray) -> bytes:
    img = Image.fromarray(rgba_array, mode="RGBA")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _solid_rgba(r, g, b, a=255, size=(100, 100)) -> np.ndarray:
    """Solid-color RGBA image."""
    arr = np.zeros((*size, 4), dtype=np.uint8)
    arr[:, :] = [r, g, b, a]
    return arr


def _two_color_rgba(size=(100, 100)) -> np.ndarray:
    """Half red, half blue — 2 unique colors."""
    arr = np.zeros((*size, 4), dtype=np.uint8)
    half = size[1] // 2
    arr[:, :half] = [255, 0, 0, 255]
    arr[:, half:] = [0, 0, 255, 255]
    return arr


def _noisy_rgba(n_colors=12, size=(200, 200)) -> np.ndarray:
    """Many small scattered color regions — high complexity."""
    rng = np.random.default_rng(42)
    arr = np.zeros((*size, 4), dtype=np.uint8)
    colors = [(rng.integers(50, 255), rng.integers(50, 255), rng.integers(50, 255))
              for _ in range(n_colors)]
    for y in range(size[0]):
        for x in range(size[1]):
            c = colors[(y * size[1] + x) % n_colors]
            arr[y, x] = [*c, 255]
    return arr


# ── Test functions ────────────────────────────────────────────────────────────

def test_process_image_returns_dict():
    proc = ImageProcessor(use_rembg=False)
    arr = _solid_rgba(255, 0, 0)
    result = proc.process_image(_make_png(arr), max_colors=2, remove_background=False)

    assert isinstance(result, dict), f"Expected dict, got {type(result)}"
    assert "image_bytes" in result, "Missing key: image_bytes"
    assert "dominant_colors" in result, "Missing key: dominant_colors"
    assert "complexity" in result, "Missing key: complexity"
    assert isinstance(result["image_bytes"], bytes), "image_bytes must be bytes"
    print("[OK] process_image returns dict with correct keys")


def test_process_image_basic_vs_advanced():
    proc = ImageProcessor(use_rembg=False)
    arr = _noisy_rgba(n_colors=8)
    png = _make_png(arr)

    basic = proc.process_image(png, max_colors=4, remove_background=False, mode="basic")
    advanced = proc.process_image(png, max_colors=4, remove_background=False, mode="advanced")

    assert basic["image_bytes"] is not None
    assert advanced["image_bytes"] is not None
    assert "complexity" in basic
    assert "complexity" in advanced
    print("[OK] process_image works for both basic and advanced modes")


def test_complexity_simple():
    proc = ImageProcessor(use_rembg=False)
    # 1 color solid — minimum complexity
    arr = _solid_rgba(100, 200, 50)
    rgba = np.array(Image.fromarray(arr, mode="RGBA"))
    c = proc.analyze_complexity(rgba)

    assert c["level"] == "simple", f"Expected simple, got {c['level']} (score={c['score']})"
    assert c["score"] <= _SCORE_SIMPLE, f"Score {c['score']} > {_SCORE_SIMPLE}"
    assert c["unique_colors"] == 1
    print(f"[OK] 1-color image = simple (score={c['score']}, colors={c['unique_colors']})")


def test_complexity_two_colors():
    proc = ImageProcessor(use_rembg=False)
    arr = _two_color_rgba()
    rgba = np.array(Image.fromarray(arr, mode="RGBA"))
    c = proc.analyze_complexity(rgba)

    # region_count = alpha-connected blobs, not color regions.
    # Two adjacent colors with no transparency gap = 1 alpha blob.
    assert c["unique_colors"] == 2, f"Expected 2 unique colors, got {c['unique_colors']}"
    assert c["region_count"] >= 1, f"Expected >=1 region, got {c['region_count']}"
    print(f"[OK] 2-color image analyzed (score={c['score']}, regions={c['region_count']})")


def test_complexity_all_fields_present():
    proc = ImageProcessor(use_rembg=False)
    arr = _two_color_rgba()
    rgba = np.array(Image.fromarray(arr, mode="RGBA"))
    c = proc.analyze_complexity(rgba)

    required = {"level", "score", "unique_colors", "edge_density", "region_count", "avg_region_area_px"}
    missing = required - set(c.keys())
    assert not missing, f"Missing complexity keys: {missing}"
    assert c["level"] in ("simple", "medium", "complex")
    assert 0 <= c["score"] <= 135
    assert 0.0 <= c["edge_density"] <= 1.0
    print(f"[OK] complexity dict has all required fields")


def test_complexity_empty_image():
    proc = ImageProcessor(use_rembg=False)
    # Fully transparent image
    arr = np.zeros((100, 100, 4), dtype=np.uint8)
    c = proc.analyze_complexity(arr)

    assert c["level"] == "simple"
    assert c["score"] == 0
    assert c["unique_colors"] == 0
    print("[OK] fully transparent image returns complexity=simple/score=0")


def test_extract_dominant_colors():
    proc = ImageProcessor(use_rembg=False)
    arr = _two_color_rgba()
    rgba = np.array(Image.fromarray(arr, mode="RGBA"))
    colors = proc._extract_dominant_colors(rgba)

    assert len(colors) == 2, f"Expected 2 dominant colors, got {len(colors)}"
    # Colors should be ARGB ints (alpha = 0xFF)
    for c in colors:
        assert (c >> 24) & 0xFF == 0xFF, f"Expected alpha=0xFF in ARGB {hex(c)}"
    print(f"[OK] _extract_dominant_colors returns {len(colors)} ARGB ints")


def test_morphological_cleanup_preserves_large_regions():
    proc = ImageProcessor(use_rembg=False)
    # Large solid square — cleanup should not remove it
    arr = _solid_rgba(200, 50, 50, size=(150, 150))
    pil = Image.fromarray(arr, mode="RGBA")
    cleaned = proc._morphological_cleanup(pil)
    cleaned_arr = np.array(cleaned)

    visible_before = int((arr[:, :, 3] > 10).sum())
    visible_after = int((cleaned_arr[:, :, 3] > 10).sum())

    # Large region should survive; allow up to 5% loss from border effects
    assert visible_after >= visible_before * 0.95, (
        f"Too many pixels removed: {visible_before} -> {visible_after}"
    )
    print(f"[OK] morphological cleanup preserves large regions "
          f"({visible_before} -> {visible_after} visible pixels)")


def test_simplify_regions_keeps_main_shape():
    proc = ImageProcessor(use_rembg=False)
    arr = _solid_rgba(50, 150, 200, size=(120, 120))
    pil = Image.fromarray(arr, mode="RGBA")
    simplified = proc._simplify_regions(pil)
    simplified_arr = np.array(simplified)

    visible_after = int((simplified_arr[:, :, 3] > 10).sum())
    assert visible_after > 0, "simplify_regions removed all pixels from a solid image"
    print(f"[OK] _simplify_regions keeps main shape ({visible_after} visible pixels)")


def test_process_image_complexity_in_dict():
    proc = ImageProcessor(use_rembg=False)
    arr = _two_color_rgba(size=(150, 150))
    result = proc.process_image(_make_png(arr), max_colors=4, remove_background=False)
    c = result["complexity"]

    assert isinstance(c, dict)
    assert c["level"] in ("simple", "medium", "complex")
    assert isinstance(c["score"], int)
    print(f"[OK] process_image embeds complexity: level={c['level']}, score={c['score']}")


def test_dominant_colors_in_result():
    proc = ImageProcessor(use_rembg=False)
    arr = _two_color_rgba(size=(100, 100))
    result = proc.process_image(_make_png(arr), max_colors=2, remove_background=False)

    colors = result["dominant_colors"]
    assert isinstance(colors, list), f"dominant_colors should be list, got {type(colors)}"
    assert len(colors) >= 1, "Expected at least 1 dominant color"
    print(f"[OK] dominant_colors in result: {len(colors)} colors")


# ── Runner ────────────────────────────────────────────────────────────────────

TESTS = [
    test_process_image_returns_dict,
    test_process_image_basic_vs_advanced,
    test_complexity_simple,
    test_complexity_two_colors,
    test_complexity_all_fields_present,
    test_complexity_empty_image,
    test_extract_dominant_colors,
    test_morphological_cleanup_preserves_large_regions,
    test_simplify_regions_keeps_main_shape,
    test_process_image_complexity_in_dict,
    test_dominant_colors_in_result,
]

if __name__ == "__main__":
    passed = 0
    failed = 0
    for test in TESTS:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"[FAIL] {test.__name__}: {e}")
            traceback.print_exc()
            failed += 1

    print(f"\n{'='*50}")
    print(f"Results: {passed} passed, {failed} failed out of {len(TESTS)} tests")
    sys.exit(0 if failed == 0 else 1)
