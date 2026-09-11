"""Text-region bounding-box detection: a pure function, independent of
deskew and OCR, so it's unit-testable against synthetic images alone.
"""

from __future__ import annotations

import cv2
import numpy as np

from .deskew import to_gray
from .geometry import BoundingBox

_OPEN_KERNEL_SIZE = 3
_MIN_CONTOUR_AREA_FRACTION = 0.0003  # drop dust/speckle contours below this fraction of image area


def detect_text_region(
    image: np.ndarray,
    padding: int = 0,
    border_margin: int = 2,
) -> BoundingBox:
    """Detect the bounding box of the "ink mass" on a page image: the union
    of contours after denoising and merging text into blobs, excluding
    contours that touch the image border (scanner-bed shadow strips).

    Falls back to the full image bounds if nothing survives filtering (e.g.
    a blank page), so callers always get a usable box.
    """
    h, w = image.shape[:2]
    gray = to_gray(image)
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    open_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (_OPEN_KERNEL_SIZE, _OPEN_KERNEL_SIZE))
    opened = cv2.morphologyEx(binary, cv2.MORPH_OPEN, open_kernel)

    close_kernel_w = max(15, w // 40)
    close_kernel_h = max(15, h // 60)
    close_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (close_kernel_w, close_kernel_h))
    closed = cv2.morphologyEx(opened, cv2.MORPH_CLOSE, close_kernel)

    # RETR_CCOMP, not RETR_EXTERNAL: a border/shadow strip that forms a closed
    # frame around the page creates a "hole" in the topology, and
    # RETR_EXTERNAL would treat genuinely separate text-blob contours nested
    # inside that hole as non-external and silently drop them. RETR_CCOMP
    # promotes any component inside a hole back to the top hierarchy level
    # (parent == -1) alongside the frame's own outer boundary, while the
    # hole's own thin ring boundary is demoted to a child (parent != -1) —
    # so filtering on parent == -1 keeps real ink blobs and drops both the
    # frame's outer edge (via the border-touch check below) and the hole
    # ring artifact (which would otherwise look like one giant text region).
    contours, hierarchy = cv2.findContours(closed, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    hierarchy = hierarchy[0] if hierarchy is not None else []

    min_area = h * w * _MIN_CONTOUR_AREA_FRACTION
    boxes: list[BoundingBox] = []
    for contour, node in zip(contours, hierarchy):
        parent = node[3]
        if parent != -1:
            continue
        if cv2.contourArea(contour) < min_area:
            continue
        x, y, cw, ch = cv2.boundingRect(contour)
        box = BoundingBox(x=x, y=y, width=cw, height=ch)
        if box.touches_border(w, h, margin=border_margin):
            continue
        boxes.append(box)

    if not boxes:
        return BoundingBox(x=0, y=0, width=w, height=h)

    union = BoundingBox.union(boxes)
    if padding:
        union = union.pad(padding, w, h)
    return union
