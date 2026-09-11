"""Two-pass deskew: coarse OSD orientation, then fine sub-degree tilt correction.

A Hough/minAreaRect-style detector alone only reasons about small tilts around
the page's own axes; a page scanned fully sideways or upside down looks, to
such a detector, like a page with a large but plausible "skew" in the wrong
direction. Tesseract's own orientation-and-script-detection (OSD) is run
first to catch and correct 90/180/270-degree rotations before the fine pass
runs at all.
"""

from __future__ import annotations

import cv2
import numpy as np
import pytesseract

from .geometry import normalize_min_area_rect_angle

_MIN_CONTOUR_AREA_FRACTION = 0.0005  # drop specks smaller than this fraction of the image area


def to_gray(image: np.ndarray) -> np.ndarray:
    if image.ndim == 2:
        return image
    return cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)


def rotate_image(image: np.ndarray, angle_deg: float, fill: int | tuple = 255) -> np.ndarray:
    """Rotate by angle_deg (cv2.getRotationMatrix2D sign convention) around the
    image center, expanding the canvas so no content is clipped, filling new
    area white. detect_fine_skew_angle's output is designed to be passed
    straight back into this function to correct the skew it measured.
    """
    if abs(angle_deg) < 1e-6:
        return image
    h, w = image.shape[:2]
    center = (w / 2.0, h / 2.0)
    matrix = cv2.getRotationMatrix2D(center, angle_deg, 1.0)

    cos = abs(matrix[0, 0])
    sin = abs(matrix[0, 1])
    new_w = int(h * sin + w * cos)
    new_h = int(h * cos + w * sin)
    matrix[0, 2] += (new_w / 2.0) - center[0]
    matrix[1, 2] += (new_h / 2.0) - center[1]

    border_value = fill if image.ndim == 2 else (fill, fill, fill)
    return cv2.warpAffine(
        image,
        matrix,
        (new_w, new_h),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=border_value,
    )


def detect_osd_rotation(image: np.ndarray) -> int:
    """Coarse pass. Returns one of 0/90/180/270 (degrees the page must be
    rotated counter-clockwise to become upright), or 0 if OSD can't decide
    (e.g. too little text — common on a synthetic test image with a single
    short line, or a blank/near-blank page).
    """
    try:
        osd = pytesseract.image_to_osd(image, output_type=pytesseract.Output.DICT)
        rotate = int(osd.get("rotate", 0)) % 360
        return rotate if rotate in (0, 90, 180, 270) else 0
    except pytesseract.TesseractError:
        return 0


def detect_fine_skew_angle(image: np.ndarray) -> float:
    """Fine pass. Returns a small signed angle in degrees (cv2.getRotationMatrix2D
    convention) that, passed directly to rotate_image(), corrects the
    measured tilt — see rotate_image for the exact convention.
    """
    gray = to_gray(image)
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (25, 5))
    dilated = cv2.dilate(binary, kernel, iterations=1)

    contours, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return 0.0

    image_area = gray.shape[0] * gray.shape[1]
    min_area = image_area * _MIN_CONTOUR_AREA_FRACTION
    significant = [c for c in contours if cv2.contourArea(c) >= min_area]
    if not significant:
        return 0.0

    all_points = np.vstack(significant)
    rect = cv2.minAreaRect(all_points)
    (_, _), (w, h), angle = rect
    if w == 0 or h == 0:
        return 0.0
    return normalize_min_area_rect_angle(angle, w, h)


def deskew(image: np.ndarray, correct_orientation: bool = True) -> tuple[np.ndarray, float]:
    """Full two-pass deskew. Returns (corrected_image, fine_skew_angle_deg) —
    the fine angle is the adjustable value surfaced in the JSON protocol;
    any 90/180/270 orientation correction is applied unconditionally and not
    separately reported, since it isn't something a user fine-tunes.
    """
    working = image
    if correct_orientation:
        coarse = detect_osd_rotation(image)
        if coarse:
            working = rotate_image(image, -coarse)

    fine_angle = detect_fine_skew_angle(working)
    corrected = rotate_image(working, fine_angle)
    return corrected, fine_angle


def apply_known_skew(image: np.ndarray, skew_angle_deg: float) -> np.ndarray:
    """Apply a previously-computed (or user-overridden) skew angle without
    re-running detection — used when `ocr`/`finalize` are given an explicit
    deskew_angle_deg from a prior `analyze` call or user adjustment.
    """
    return rotate_image(image, skew_angle_deg)
