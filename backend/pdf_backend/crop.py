"""Text-region bounding-box detection: pure functions, independent of
deskew and OCR, so they're unit-testable against synthetic images alone.

Two entry points share the same underlying block detection:
- detect_text_region: single unioned box (the original, simple behavior —
  what a plain scanned page needs).
- detect_regions: classifies the same blocks into named regions
  (main_text / apparatus / margin_left / margin_right / other), for critical
  editions where the critical apparatus and marginal line numbers should be
  excluded from OCR rather than merged into one crop box. See
  docs/ARCHITECTURE.md "Multi-region detection (critical editions)".
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .deskew import to_gray
from .geometry import BoundingBox

_MIN_CONTOUR_AREA_FRACTION = 0.0003  # drop dust/speckle contours below this fraction of image area

# Margin line numbers are individually tiny (a lone one- or two-digit
# numeral, often widely spaced — every 5th or 10th line, not every line —
# so they rarely merge into anything bigger via closing) and would be
# filtered out entirely as "dust" by _MIN_CONTOUR_AREA_FRACTION. Candidate
# detection for margin columns specifically therefore uses this much lower
# area floor, paired with a minimum pixel dimension to still reject actual
# single-pixel anti-aliasing artifacts.
_MARGIN_MIN_CONTOUR_AREA_FRACTION = 0.00002
_MARGIN_MIN_DIMENSION_PX = 4

# Classification thresholds for detect_regions, relative to the main_text
# block's own dimensions — see detect_regions' docstring for the reasoning.
_APPARATUS_MIN_WIDTH_FRACTION = 0.3
_MARGIN_MAX_WIDTH_FRACTION = 0.25
_VERTICAL_GAP_TOLERANCE_FRACTION = 0.02  # of image height; allows apparatus to start slightly above main_text's measured bottom (e.g. a shared rule line both blocks nearly touch)


@dataclass(frozen=True)
class Region:
    region_type: str  # "main_text" | "apparatus" | "margin_left" | "margin_right" | "other"
    bbox: BoundingBox

    def to_dict(self) -> dict:
        return {"region_type": self.region_type, "bbox": self.bbox.to_dict()}


def _find_top_level_contours(image: np.ndarray):
    """Binarize + close (merge glyphs into blobs) and return the resulting
    top-level (non-hole) contours with the image dimensions. See
    detect_text_region's original docstring for the RETR_CCOMP rationale
    (border/shadow frames create hole topology that RETR_EXTERNAL would
    wrongly drop real content from).

    No morphological opening/erosion step: a fixed small kernel aggressive
    enough to denoise real scanner dust also erases thin strokes of
    small-point-size text outright (critical-apparatus and margin-line-number
    text is set smaller than the main text, and was being erased before it
    ever reached this closing/merge step). Noise robustness instead comes
    from the area filters callers apply to the returned contours.
    """
    h, w = image.shape[:2]
    gray = to_gray(image)
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    close_kernel_w = max(15, w // 40)
    close_kernel_h = max(15, h // 60)
    close_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (close_kernel_w, close_kernel_h))
    closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, close_kernel)

    contours, hierarchy = cv2.findContours(closed, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    hierarchy = hierarchy[0] if hierarchy is not None else []
    top_level = [c for c, node in zip(contours, hierarchy) if node[3] == -1]
    return top_level, w, h


def _detect_blocks(
    image: np.ndarray,
    border_margin: int,
    min_area_fraction: float = _MIN_CONTOUR_AREA_FRACTION,
    min_dimension_px: int = 0,
) -> tuple[list[BoundingBox], int, int]:
    """Text/ink blocks after denoising + merging, filtered by a minimum area
    (as a fraction of the image) and, optionally, a minimum pixel width/height
    (an absolute floor that a fraction-of-image-area threshold can't express
    well for small marks like margin numerals — see _MARGIN_MIN_*).
    """
    contours, w, h = _find_top_level_contours(image)
    min_area = h * w * min_area_fraction

    boxes: list[BoundingBox] = []
    for contour in contours:
        if cv2.contourArea(contour) < min_area:
            continue
        x, y, cw, ch = cv2.boundingRect(contour)
        if min_dimension_px and (cw < min_dimension_px or ch < min_dimension_px):
            continue
        box = BoundingBox(x=x, y=y, width=cw, height=ch)
        if box.touches_border(w, h, margin=border_margin):
            continue
        boxes.append(box)

    return boxes, w, h


def detect_text_region(
    image: np.ndarray,
    padding: int = 0,
    border_margin: int = 2,
) -> BoundingBox:
    """Detect the bounding box of the "ink mass" on a page image: the union
    of all detected blocks. Falls back to the full image bounds if nothing
    survives filtering (e.g. a blank page), so callers always get a usable box.
    """
    boxes, w, h = _detect_blocks(image, border_margin)
    if not boxes:
        return BoundingBox(x=0, y=0, width=w, height=h)
    union = BoundingBox.union(boxes)
    if padding:
        union = union.pad(padding, w, h)
    return union


def detect_regions(
    image: np.ndarray,
    padding: int = 0,
    border_margin: int = 2,
) -> list[Region]:
    """Classify detected blocks into named regions for critical editions:

    - main_text: the single largest block (by area) on the page.
    - apparatus: block(s) positioned below main_text, roughly as wide as it
      — the critical apparatus sits under the main text column, typically
      set in smaller type but classified here by *position*, not font size,
      which is far more robust to estimate from a block's own bounding box
      alone.
    - margin_left / margin_right: block(s) narrower than main_text,
      vertically overlapping it, positioned entirely to its left/right —
      line numbers running down the margin.
    - other: anything left over (a running header, a footer/page number) —
      kept and labeled rather than silently dropped, so the UI can still
      show it, even though only main_text feeds OCR by default.

    A plain page with no apparatus/margin numbers — the common case outside
    critical editions — naturally yields a single `main_text` region
    covering the same area detect_text_region would have returned, so this
    is a strict superset of that simpler function's behavior.
    """
    boxes, w, h = _detect_blocks(image, border_margin)
    if not boxes:
        return [Region("main_text", BoundingBox(x=0, y=0, width=w, height=h))]

    def maybe_pad(box: BoundingBox) -> BoundingBox:
        return box.pad(padding, w, h) if padding else box

    if len(boxes) == 1:
        return [Region("main_text", maybe_pad(boxes[0]))]

    main_text = max(boxes, key=lambda b: b.width * b.height)
    vertical_tolerance = int(h * _VERTICAL_GAP_TOLERANCE_FRACTION)

    apparatus_candidates: list[BoundingBox] = []
    other_candidates: list[BoundingBox] = []

    for box in boxes:
        if box is main_text:
            continue
        is_below_main = box.y >= main_text.y2 - vertical_tolerance
        is_apparatus_width = box.width >= main_text.width * _APPARATUS_MIN_WIDTH_FRACTION
        if is_below_main and is_apparatus_width:
            apparatus_candidates.append(box)
        else:
            other_candidates.append(box)

    # Margin numerals get their own, more sensitive detection pass: a lone
    # numeral is individually far smaller than _MIN_CONTOUR_AREA_FRACTION
    # would allow through, since (unlike apparatus/main text) they don't
    # reliably merge into one bigger blob — they're often spaced every 5th
    # or 10th line, not every line.
    margin_boxes, _, _ = _detect_blocks(
        image,
        border_margin,
        min_area_fraction=_MARGIN_MIN_CONTOUR_AREA_FRACTION,
        min_dimension_px=_MARGIN_MIN_DIMENSION_PX,
    )
    margin_left_candidates: list[BoundingBox] = []
    margin_right_candidates: list[BoundingBox] = []
    for box in margin_boxes:
        vertical_overlap = min(box.y2, main_text.y2) - max(box.y, main_text.y)
        runs_alongside_main = vertical_overlap > 0
        is_margin_width = box.width <= main_text.width * _MARGIN_MAX_WIDTH_FRACTION
        if not (runs_alongside_main and is_margin_width):
            continue
        if box.x2 <= main_text.x:
            margin_left_candidates.append(box)
        elif box.x >= main_text.x2:
            margin_right_candidates.append(box)

    regions = [Region("main_text", maybe_pad(main_text))]
    if apparatus_candidates:
        regions.append(Region("apparatus", maybe_pad(BoundingBox.union(apparatus_candidates))))
    if margin_left_candidates:
        regions.append(Region("margin_left", maybe_pad(BoundingBox.union(margin_left_candidates))))
    if margin_right_candidates:
        regions.append(Region("margin_right", maybe_pad(BoundingBox.union(margin_right_candidates))))
    if other_candidates:
        regions.append(Region("other", maybe_pad(BoundingBox.union(other_candidates))))

    return regions
