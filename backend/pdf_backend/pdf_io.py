"""PDF <-> image I/O via PyMuPDF (no external poppler/ghostscript dependency)."""

from __future__ import annotations

import cv2
import numpy as np
import pymupdf
from PIL import Image

from .deskew import to_gray
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


def to_bw(image: np.ndarray) -> np.ndarray:
    """Bi-level (pure black/white) conversion via Otsu threshold, for the
    "Black & white" export toggle — black ink on a white background, the
    same sense a "B&W scan" mode means, as opposed to grayscale (which keeps
    intermediate shades). Deliberately not the inverted binarization
    crop.py/deskew.py use internally for ink-mass analysis: this is for
    direct visual embedding in the output PDF, so ink must stay black (0),
    background white (255). Only applied to the final output image, never
    to what OCR runs against — Tesseract's own adaptive binarization does
    better than a single global threshold, so OCR always sees the original
    grayscale/color rasterization.
    """
    gray = to_gray(image)
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    return binary


def crop_np(image: np.ndarray, x: int, y: int, width: int, height: int) -> np.ndarray:
    h, w = image.shape[:2]
    x2 = min(w, x + width)
    y2 = min(h, y + height)
    x = max(0, x)
    y = max(0, y)
    return image[y:y2, x:x2]
