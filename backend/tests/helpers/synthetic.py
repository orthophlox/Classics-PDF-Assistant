"""Synthetic "scanned page" generators for testing deskew/crop/OCR without any
real book scans. Pure PIL, no external assets beyond system fonts.
"""

from __future__ import annotations

import io

import numpy as np
import pymupdf
from PIL import Image, ImageDraw, ImageFont

_FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(_FONT_PATH, size)


def make_text_page(
    width: int = 1000,
    height: int = 1400,
    margin: int = 150,
    lines: list[str] | None = None,
    font_size: int = 28,
) -> Image.Image:
    """A clean, unrotated "page" with a block of text inset from a white margin."""
    if lines is None:
        lines = [f"Line {i} of synthetic text for OCR/deskew/crop testing." for i in range(20)]
    img = Image.new("L", (width, height), color=255)
    draw = ImageDraw.Draw(img)
    font = _font(font_size)
    y = margin
    for line in lines:
        draw.text((margin, y), line, fill=0, font=font)
        y += int(font_size * 1.6)
    return img


def make_critical_edition_page(
    width: int = 1200,
    height: int = 1600,
    main_text_x: int = 300,
    main_text_width: int = 650,
    main_text_top: int = 150,
    main_text_bottom: int = 1100,
    apparatus_top: int = 1200,
    apparatus_bottom: int = 1500,
    margin_gap: int = 60,
    margin_number_width: int = 40,
) -> Image.Image:
    """A synthetic critical-edition page: a main text column, a smaller-font
    critical apparatus block below it, and narrow line-number columns in the
    left and right margins — well-separated so detect_regions has a clean
    case to classify, for testing multi-region detection independent of any
    real edition's actual layout.
    """
    img = Image.new("L", (width, height), color=255)
    draw = ImageDraw.Draw(img)

    body_font = _font(28)
    y = main_text_top
    line_index = 0
    while y < main_text_bottom - 30:
        draw.text((main_text_x, y), f"Textus principalis linea {line_index}", fill=0, font=body_font)
        line_index += 1
        y += 45

    # Margin line numbers: small numerals every few lines, well clear of
    # the main text column on both sides.
    margin_font = _font(16)
    margin_left_x = main_text_x - margin_gap - margin_number_width
    margin_right_x = main_text_x + main_text_width + margin_gap
    for n, ly in enumerate(range(main_text_top, main_text_bottom - 30, 45 * 5), start=1):
        draw.text((margin_left_x, ly), str(n * 5), fill=0, font=margin_font)
        draw.text((margin_right_x, ly), str(n * 5), fill=0, font=margin_font)

    # Critical apparatus: smaller font, spans roughly the same width as the
    # main text column, positioned below it with a clear gap.
    apparatus_font = _font(14)
    ay = apparatus_top
    apparatus_index = 0
    while ay < apparatus_bottom - 16:
        draw.text(
            (main_text_x - 20, ay),
            f"{apparatus_index + 1} lemma] varia lectio codicis testis {apparatus_index}",
            fill=0,
            font=apparatus_font,
        )
        apparatus_index += 1
        ay += 22

    return img


def rotate_page(img: Image.Image, angle_deg: float) -> Image.Image:
    """Rotate with white fill and an expanded canvas, mimicking a skewed scan."""
    return img.rotate(-angle_deg, expand=True, fillcolor=255, resample=Image.BICUBIC)


def add_border_noise(img: Image.Image, thickness: int = 12) -> Image.Image:
    """Simulate a scanner-bed black border/shadow strip around the page edges."""
    arr = np.array(img.convert("L"))
    arr[:thickness, :] = 0
    arr[-thickness:, :] = 0
    arr[:, :thickness] = 0
    arr[:, -thickness:] = 0
    return Image.fromarray(arr)


def to_rgb_ndarray(img: Image.Image) -> np.ndarray:
    """Convert a PIL (grayscale or RGB) image to a 3-channel RGB ndarray, matching
    pdf_io.rasterize_page's output (PyMuPDF renders to RGB, not BGR).
    """
    return np.array(img.convert("RGB"))


def images_to_pdf(images: list[Image.Image], dpi: int, output_path: str) -> str:
    """Build a multi-page PDF whose pages, when rasterized by pdf_io at the
    same `dpi`, reproduce these images pixel-for-pixel-ish — for building a
    synthetic "scanned book" input.pdf for pipeline integration tests.
    """
    doc = pymupdf.open()
    for img in images:
        w_px, h_px = img.size
        page_width_pt = w_px / (dpi / 72.0)
        page_height_pt = h_px / (dpi / 72.0)
        page = doc.new_page(width=page_width_pt, height=page_height_pt)
        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="PNG")
        page.insert_image(pymupdf.Rect(0, 0, page_width_pt, page_height_pt), stream=buf.getvalue())
    doc.save(output_path)
    doc.close()
    return output_path
