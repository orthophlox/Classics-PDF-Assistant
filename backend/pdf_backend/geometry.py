"""Bounding-box and angle math shared by deskew, crop, and OCR."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BoundingBox:
    x: int
    y: int
    width: int
    height: int

    @property
    def x2(self) -> int:
        return self.x + self.width

    @property
    def y2(self) -> int:
        return self.y + self.height

    def to_dict(self) -> dict:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}

    @classmethod
    def from_dict(cls, data: dict) -> "BoundingBox":
        return cls(x=int(data["x"]), y=int(data["y"]), width=int(data["width"]), height=int(data["height"]))

    @classmethod
    def union(cls, boxes: list["BoundingBox"]) -> "BoundingBox":
        if not boxes:
            raise ValueError("cannot union an empty list of boxes")
        x1 = min(b.x for b in boxes)
        y1 = min(b.y for b in boxes)
        x2 = max(b.x2 for b in boxes)
        y2 = max(b.y2 for b in boxes)
        return cls(x=x1, y=y1, width=x2 - x1, height=y2 - y1)

    def pad(self, amount: int, bounds_width: int, bounds_height: int) -> "BoundingBox":
        """Grow the box by `amount` on every side, clamped to [0, bounds]."""
        x1 = max(0, self.x - amount)
        y1 = max(0, self.y - amount)
        x2 = min(bounds_width, self.x2 + amount)
        y2 = min(bounds_height, self.y2 + amount)
        return BoundingBox(x=x1, y=y1, width=x2 - x1, height=y2 - y1)

    def touches_border(self, bounds_width: int, bounds_height: int, margin: int = 2) -> bool:
        return (
            self.x <= margin
            or self.y <= margin
            or self.x2 >= bounds_width - margin
            or self.y2 >= bounds_height - margin
        )


def normalize_min_area_rect_angle(angle: float, width: float, height: float) -> float:
    """Normalize cv2.minAreaRect's angle (range depends on OpenCV version) into a
    signed small rotation in degrees, where positive means counter-clockwise tilt
    that should be corrected by rotating the image clockwise by that amount.
    """
    # OpenCV 4.5+ minAreaRect returns angle in [0, 90). A "landscape" rect (width
    # >= height) close to 0 means near-horizontal already; a "portrait" rect means
    # the detected angle is relative to the long side and needs a -90 correction.
    if width < height:
        angle = angle - 90
    if angle < -45:
        angle += 90
    elif angle > 45:
        angle -= 90
    return angle


def points_to_dpi_scale(dpi: int) -> float:
    """PDF points are 1/72 inch; pixels at `dpi` are dpi/72 per point."""
    return dpi / 72.0
