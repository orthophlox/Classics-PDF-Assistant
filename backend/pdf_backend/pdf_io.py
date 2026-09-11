"""PDF <-> image I/O via PyMuPDF (no external poppler/ghostscript dependency)."""

from __future__ import annotations

import numpy as np
import pymupdf
from PIL import Image

from .geometry import points_to_dpi_scale


def open_pdf(path: str) -> pymupdf.Document:
    return pymupdf.open(path)


def page_count(doc: pymupdf.Document) -> int:
    return doc.page_count


def rasterize_page(doc: pymupdf.Document, page_index: int, dpi: int) -> np.ndarray:
    """Render a page to an RGB uint8 numpy array at the given DPI."""
    page = doc[page_index]
    zoom = points_to_dpi_scale(dpi)
    matrix = pymupdf.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=matrix, colorspace=pymupdf.csRGB, alpha=False)
    image = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, pix.n)
    return image


def np_to_pil(image: np.ndarray) -> Image.Image:
    return Image.fromarray(image)


def save_png(image: np.ndarray, path: str) -> None:
    np_to_pil(image).save(path, format="PNG")


def crop_np(image: np.ndarray, x: int, y: int, width: int, height: int) -> np.ndarray:
    h, w = image.shape[:2]
    x2 = min(w, x + width)
    y2 = min(h, y + height)
    x = max(0, x)
    y = max(0, y)
    return image[y:y2, x:x2]
