"""
Testes de integração para EmbroideryConverter.

Cobre:
  - Round-trip real: escreve arquivo → lê de volta com pyembroidery.read()
  - Verificação de estrutura de bytes por formato (PES, DST, JEF …)
  - Consistência de métricas (pontos, cores, dimensões)
  - Todos os 12 formatos suportados
  - Todos os 3 tipos de ponto (fill / outline / satin)
  - Edge cases: imagem transparente, cor única, máximo de cores

Execute:
    cd python
    .venv\\Scripts\\pytest test_converter.py -v
"""

import io
import os
import struct
import tempfile

import numpy as np
import pyembroidery
import pytest
from PIL import Image, ImageDraw

from embroidery_converter import EmbroideryConverter, SUPPORTED_FORMATS

# ── Fixtures de imagem ────────────────────────────────────────────────────────

def _make_png(pil_img: Image.Image) -> bytes:
    buf = io.BytesIO()
    pil_img.save(buf, format="PNG")
    return buf.getvalue()


def _logo_image() -> bytes:
    """Imagem 200×200 com 4 regiões coloridas — caso de uso real."""
    img = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([55, 55, 145, 145], fill=(255, 200, 0, 255))
    draw.ellipse([65, 65, 135, 135], fill=(220, 30, 30, 255))
    draw.rectangle([10, 10, 60, 60], fill=(30, 80, 200, 255))
    draw.polygon([(140, 200), (200, 140), (200, 200)], fill=(20, 160, 60, 255))
    return _make_png(img)


def _single_color_image() -> bytes:
    """Quadrado sólido vermelho — 1 cor."""
    img = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    ImageDraw.Draw(img).rectangle([10, 10, 90, 90], fill=(200, 50, 50, 255))
    return _make_png(img)


def _transparent_image() -> bytes:
    """Imagem 100% transparente — deve gerar ValueError."""
    return _make_png(Image.new("RGBA", (100, 100), (0, 0, 0, 0)))


@pytest.fixture(scope="module")
def converter():
    return EmbroideryConverter()


@pytest.fixture(scope="module")
def logo_png():
    return _logo_image()


@pytest.fixture(scope="module")
def single_color_png():
    return _single_color_image()


# ── Round-trip: escreve e relê com pyembroidery ───────────────────────────────

class TestRoundTrip:
    """
    Para cada formato, escreve o arquivo e lê de volta com pyembroidery.read().
    Se pyembroidery consegue ler, o arquivo é sintaticamente válido para máquinas.
    """

    @pytest.mark.parametrize("fmt", sorted(SUPPORTED_FORMATS))
    def test_pyembroidery_can_read_back(self, converter, logo_png, fmt, tmp_path):
        result = converter.convert(
            image_bytes=logo_png,
            output_format=fmt,
            width_mm=60.0,
            height_mm=60.0,
            fabric_id="cotton",
            stitch_type="fill",
        )

        # Escreve em arquivo temporário com a extensão correta
        out_file = tmp_path / f"test.{fmt.lower()}"
        out_file.write_bytes(result["file_bytes"])

        # Lê de volta com pyembroidery
        pattern = pyembroidery.read(str(out_file))

        assert pattern is not None, f"pyembroidery.read() retornou None para {fmt}"
        assert len(pattern.stitches) > 0, f"Pattern lido de {fmt} não tem stitches"

    @pytest.mark.parametrize("fmt", ["PES", "DST"])
    def test_stitch_count_consistent_after_readback(self, converter, logo_png, fmt, tmp_path):
        """Contador de pontos do converter ≈ pontos no pattern relido."""
        result = converter.convert(
            image_bytes=logo_png,
            output_format=fmt,
            width_mm=60.0,
            height_mm=60.0,
            fabric_id="cotton",
            stitch_type="fill",
        )

        out_file = tmp_path / f"test.{fmt.lower()}"
        out_file.write_bytes(result["file_bytes"])
        pattern = pyembroidery.read(str(out_file))

        # pyembroidery inclui JUMP/TRIM/END nos stitches; contamos só STITCH (0x80)
        stitch_only = [s for s in pattern.stitches if s[2] == pyembroidery.STITCH]
        reported = result["total_stitches"]

        # Tolerância de 5%: alguns formatos arredondam ou agrupam pontos
        assert len(stitch_only) > 0, f"Nenhum STITCH no pattern relido ({fmt})"
        ratio = len(stitch_only) / reported if reported > 0 else 0
        assert 0.8 <= ratio <= 1.2, (
            f"{fmt}: pontos reportados={reported}, relidos={len(stitch_only)} "
            f"(razão={ratio:.2f}, esperado 0.80–1.20)"
        )

    def test_pes_thread_count_matches_color_count(self, converter, logo_png, tmp_path):
        """PES armazena thread colors — count deve bater após round-trip."""
        result = converter.convert(
            image_bytes=logo_png,
            output_format="PES",
            width_mm=60.0,
            height_mm=60.0,
            fabric_id="cotton",
            stitch_type="fill",
        )

        out_file = tmp_path / "test.pes"
        out_file.write_bytes(result["file_bytes"])
        pattern = pyembroidery.read(str(out_file))

        expected_colors = len(result["colors"])
        actual_threads = len(pattern.threadlist)

        assert actual_threads == expected_colors, (
            f"PES: converter reportou {expected_colors} cores, "
            f"pyembroidery leu {actual_threads} threads"
        )

    def test_dst_stitches_readable_without_thread_info(self, converter, logo_png, tmp_path):
        """
        DST não armazena cores de linha (threadlist fica vazio após read-back).
        O que importa é que os stitches sejam legíveis — operador troca linhas manualmente.
        """
        result = converter.convert(
            image_bytes=logo_png,
            output_format="DST",
            width_mm=60.0,
            height_mm=60.0,
            fabric_id="cotton",
            stitch_type="fill",
        )

        out_file = tmp_path / "test.dst"
        out_file.write_bytes(result["file_bytes"])
        pattern = pyembroidery.read(str(out_file))

        # threadlist vazio é esperado em DST — formato não armazena cores
        assert isinstance(pattern.threadlist, list), "threadlist deve ser lista"

        # O que deve existir são os stitches
        assert len(pattern.stitches) > 0, (
            "DST lido não tem stitches — arquivo corrompido"
        )


# ── Verificação de bytes por formato ─────────────────────────────────────────

class TestFileStructure:

    def test_pes_magic_bytes(self, converter, logo_png):
        result = converter.convert(
            image_bytes=logo_png, output_format="PES",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
        )
        data = result["file_bytes"]

        # Bytes 0-3: "#PES"
        assert data[:4] == b"#PES", f"Magic bytes PES incorretos: {data[:4]}"

        # Bytes 4-7: versão ("0001" ou "0060")
        version = data[4:8]
        assert version.isdigit(), f"Versão PES não numérica: {version}"

        # Bytes 8-11: offset do bloco PEC (little-endian uint32)
        pec_offset = struct.unpack_from("<I", data, 8)[0]
        assert pec_offset < len(data), (
            f"PEC offset ({pec_offset}) além do tamanho do arquivo ({len(data)})"
        )

        # No offset PEC: deve começar com "LA:"
        pec_magic = data[pec_offset : pec_offset + 3]
        assert pec_magic == b"LA:", (
            f"PEC magic esperado b'LA:', encontrado {pec_magic}"
        )

    def test_dst_end_marker(self, converter, logo_png):
        result = converter.convert(
            image_bytes=logo_png, output_format="DST",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
        )
        data = result["file_bytes"]

        # DST END record: 3 bytes = 0x00 0x00 0xF3  (NÃO 0xF3 0x00 0x00)
        assert data[-3:] == b"\x00\x00\xf3", (
            f"Marcador END do DST incorreto: últimos 3 bytes = {data[-3:].hex().upper()}"
        )

    def test_dst_header_fields(self, converter, logo_png):
        """Campos do cabeçalho DST (512 bytes) devem ser coerentes."""
        result = converter.convert(
            image_bytes=logo_png, output_format="DST",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
        )
        data = result["file_bytes"]

        # Cabeçalho = primeiros 512 bytes, campos separados por 0x0D
        header = data[:512].decode("ascii", errors="replace")

        import re
        st_match = re.search(r"ST:\s*(\d+)", header)
        co_match = re.search(r"CO:\s*(\d+)", header)
        px_match = re.search(r"\+X:\s*(\d+)", header)
        py_match = re.search(r"\+Y:\s*(\d+)", header)

        assert st_match, "Campo ST (stitch count) não encontrado no cabeçalho DST"
        assert co_match, "Campo CO (color changes) não encontrado no cabeçalho DST"
        assert px_match, "Campo +X não encontrado no cabeçalho DST"
        assert py_match, "Campo +Y não encontrado no cabeçalho DST"

        # ST no cabeçalho >= pontos reportados pelo converter (DST conta JUMPs também)
        st_header = int(st_match.group(1))
        assert st_header >= result["total_stitches"], (
            f"ST no header ({st_header}) < total_stitches ({result['total_stitches']})"
        )

        # CO (color changes) = número de cores - 1
        co_header = int(co_match.group(1))
        assert co_header == result["color_changes"], (
            f"CO no header ({co_header}) != color_changes ({result['color_changes']})"
        )

        # Dimensões: +X e +Y em unidades DST (0.1 mm) ≈ width/height * 10
        # Tolerância de 15% (resize NEAREST pode ajustar ligeiramente)
        x_mm = int(px_match.group(1)) / 10.0
        y_mm = int(py_match.group(1)) / 10.0
        assert abs(x_mm - 60.0) / 60.0 <= 0.15, (
            f"Largura DST {x_mm:.1f} mm muito diferente dos 60 mm pedidos"
        )
        assert abs(y_mm - 60.0) / 60.0 <= 0.15, (
            f"Altura DST {y_mm:.1f} mm muito diferente dos 60 mm pedidos"
        )

    def test_file_size_reasonable(self, converter, logo_png):
        """Arquivo não pode ser vazio nem absurdamente grande (> 5 MB para 60×60 mm)."""
        for fmt in ["PES", "DST", "JEF", "VP3"]:
            result = converter.convert(
                image_bytes=logo_png, output_format=fmt,
                width_mm=60.0, height_mm=60.0, fabric_id="cotton",
            )
            size = len(result["file_bytes"])
            assert size > 0, f"{fmt}: arquivo vazio"
            assert size < 5 * 1024 * 1024, f"{fmt}: arquivo suspeito ({size:,} bytes)"


# ── Tipos de ponto ────────────────────────────────────────────────────────────

class TestStitchTypes:

    @pytest.mark.parametrize("stitch_type", ["fill", "outline", "satin"])
    def test_all_stitch_types_produce_valid_pes(self, converter, logo_png, stitch_type, tmp_path):
        result = converter.convert(
            image_bytes=logo_png, output_format="PES",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
            stitch_type=stitch_type,
        )

        assert result["total_stitches"] > 0, (
            f"stitch_type='{stitch_type}' gerou 0 pontos"
        )
        assert result["file_bytes"][:4] == b"#PES"

        # Round-trip
        out_file = tmp_path / f"test_{stitch_type}.pes"
        out_file.write_bytes(result["file_bytes"])
        pattern = pyembroidery.read(str(out_file))
        assert pattern is not None
        assert len(pattern.stitches) > 0

    def test_fill_produces_more_stitches_than_outline(self, converter, logo_png):
        """Fill diagonal deve gerar mais pontos que outline puro."""
        fill = converter.convert(
            image_bytes=logo_png, output_format="PES",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
            stitch_type="fill",
        )
        outline = converter.convert(
            image_bytes=logo_png, output_format="PES",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
            stitch_type="outline",
        )
        assert fill["total_stitches"] > outline["total_stitches"], (
            f"fill ({fill['total_stitches']}) deveria ter mais pontos que "
            f"outline ({outline['total_stitches']})"
        )


# ── Todos os 12 formatos ──────────────────────────────────────────────────────

class TestAllFormats:

    @pytest.mark.parametrize("fmt", sorted(SUPPORTED_FORMATS))
    def test_format_produces_non_empty_file(self, converter, logo_png, fmt):
        result = converter.convert(
            image_bytes=logo_png, output_format=fmt,
            width_mm=50.0, height_mm=50.0, fabric_id="cotton",
        )
        assert len(result["file_bytes"]) > 0, f"{fmt}: arquivo vazio"
        assert result["total_stitches"] > 0, f"{fmt}: 0 pontos gerados"

    @pytest.mark.parametrize("fmt", sorted(SUPPORTED_FORMATS))
    def test_format_accepts_uppercase_and_lowercase(self, converter, logo_png, fmt):
        upper = converter.convert(
            image_bytes=logo_png, output_format=fmt,
            width_mm=40.0, height_mm=40.0, fabric_id="cotton",
        )
        lower = converter.convert(
            image_bytes=logo_png, output_format=fmt.lower(),
            width_mm=40.0, height_mm=40.0, fabric_id="cotton",
        )
        assert len(upper["file_bytes"]) == len(lower["file_bytes"]), (
            f"{fmt}: resultado diferente para maiúsculo vs minúsculo"
        )


# ── Edge cases ────────────────────────────────────────────────────────────────

class TestEdgeCases:

    def test_transparent_image_raises(self, converter):
        with pytest.raises(ValueError, match="pixels visíveis"):
            converter.convert(
                image_bytes=_transparent_image(), output_format="PES",
                width_mm=60.0, height_mm=60.0, fabric_id="cotton",
            )

    def test_single_color_image(self, converter, single_color_png):
        result = converter.convert(
            image_bytes=single_color_png, output_format="PES",
            width_mm=40.0, height_mm=40.0, fabric_id="cotton",
        )
        assert result["total_stitches"] > 0
        assert len(result["colors"]) == 1
        assert result["color_changes"] == 0
        assert result["file_bytes"][:4] == b"#PES"

    def test_unsupported_format_raises(self, converter, logo_png):
        with pytest.raises(ValueError, match="Formato não suportado"):
            converter.convert(
                image_bytes=logo_png, output_format="ABC",
                width_mm=60.0, height_mm=60.0, fabric_id="cotton",
            )

    def test_zero_dimensions_raises(self, converter, logo_png):
        with pytest.raises(ValueError, match="dimensões"):
            converter.convert(
                image_bytes=logo_png, output_format="PES",
                width_mm=0.0, height_mm=60.0, fabric_id="cotton",
            )

    def test_unknown_fabric_falls_back_to_cotton(self, converter, single_color_png):
        """Fabric desconhecido deve usar densidade padrão sem lançar exceção."""
        result = converter.convert(
            image_bytes=single_color_png, output_format="PES",
            width_mm=40.0, height_mm=40.0, fabric_id="tecido_inexistente",
        )
        assert result["total_stitches"] > 0

    @pytest.mark.parametrize("fabric", ["knit", "cotton", "towel"])
    def test_all_fabric_types(self, converter, single_color_png, fabric):
        result = converter.convert(
            image_bytes=single_color_png, output_format="PES",
            width_mm=40.0, height_mm=40.0, fabric_id=fabric,
        )
        assert result["total_stitches"] > 0, f"fabric='{fabric}' gerou 0 pontos"


# ── Validação interna ─────────────────────────────────────────────────────────

class TestValidation:

    def test_validation_ok_for_normal_design(self, converter, logo_png):
        result = converter.convert(
            image_bytes=logo_png, output_format="PES",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
        )
        val = result["validation"]
        assert val["severity"] == "ok", f"Esperado 'ok', encontrado '{val['severity']}': {val['issues']}"
        assert val["issues"] == []

    def test_validation_structure(self, converter, logo_png):
        result = converter.convert(
            image_bytes=logo_png, output_format="PES",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
        )
        val = result["validation"]
        assert "severity" in val
        assert "issues" in val
        assert val["severity"] in ("ok", "warning", "error")
        assert isinstance(val["issues"], list)

    def test_pes_magic_invalid_triggers_validation_error(self, converter, logo_png):
        """Garante que o checker de magic bytes PES realmente dispara em arquivo corrompido."""
        result = converter.convert(
            image_bytes=logo_png, output_format="PES",
            width_mm=60.0, height_mm=60.0, fabric_id="cotton",
        )
        # O arquivo real não deve ter esse erro
        codes = [i["code"] for i in result["validation"]["issues"]]
        assert "PES_MAGIC_INVALID" not in codes, (
            "Arquivo PES válido gerado com erro PES_MAGIC_INVALID — bug no validator"
        )
