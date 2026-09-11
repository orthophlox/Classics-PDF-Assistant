"""Dataclasses mirroring docs/JSON_PROTOCOL.md.

Plain dataclasses (not pydantic) are sufficient here: each subprocess
invocation handles exactly one JSON payload, so schema validation overhead
and the extra PyInstaller bundle weight aren't worth it. `to_dict`/`from_dict`
are written by hand to keep the wire format exactly as documented.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .crop import Region
from .geometry import BoundingBox


@dataclass(frozen=True)
class Word:
    text: str
    bbox: BoundingBox
    confidence: float = -1.0

    def to_dict(self) -> dict:
        return {"text": self.text, "bbox": self.bbox.to_dict(), "confidence": self.confidence}

    @classmethod
    def from_dict(cls, data: dict) -> "Word":
        return cls(
            text=data["text"],
            bbox=BoundingBox.from_dict(data["bbox"]),
            confidence=float(data.get("confidence", -1.0)),
        )


@dataclass
class PageOptions:
    """Per-page input for `ocr`/`finalize`: overrides layered on the analyze defaults."""

    page_index: int
    crop_box: BoundingBox | None = None
    deskew_angle_deg: float | None = None
    words: list[Word] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "page_index": self.page_index,
            "crop_box": self.crop_box.to_dict() if self.crop_box else None,
            "deskew_angle_deg": self.deskew_angle_deg,
            "words": [w.to_dict() for w in self.words],
        }

    @classmethod
    def from_dict(cls, data: dict) -> "PageOptions":
        crop = data.get("crop_box")
        return cls(
            page_index=int(data["page_index"]),
            crop_box=BoundingBox.from_dict(crop) if crop else None,
            deskew_angle_deg=data.get("deskew_angle_deg"),
            words=[Word.from_dict(w) for w in data.get("words", [])],
        )


@dataclass
class AnalyzeOptions:
    dpi: int = 300
    deskew: bool = True
    auto_crop: bool = True
    crop_padding_pt: float = 12.0

    @classmethod
    def from_dict(cls, data: dict) -> "AnalyzeOptions":
        d = data or {}
        return cls(
            dpi=int(d.get("dpi", 300)),
            deskew=bool(d.get("deskew", True)),
            auto_crop=bool(d.get("auto_crop", True)),
            crop_padding_pt=float(d.get("crop_padding_pt", 12.0)),
        )


@dataclass
class PageAnalysis:
    page_index: int
    preview_image: str
    skew_angle_deg: float
    detected_crop_box: BoundingBox
    image_width: int
    image_height: int
    detected_regions: list[Region] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "page_index": self.page_index,
            "preview_image": self.preview_image,
            "skew_angle_deg": self.skew_angle_deg,
            "detected_crop_box": self.detected_crop_box.to_dict(),
            "detected_regions": [r.to_dict() for r in self.detected_regions],
            "image_width": self.image_width,
            "image_height": self.image_height,
        }


@dataclass
class PageOCRResult:
    page_index: int
    words: list[Word]
    mean_confidence: float

    def to_dict(self) -> dict:
        return {
            "page_index": self.page_index,
            "words": [w.to_dict() for w in self.words],
            "mean_confidence": self.mean_confidence,
        }


@dataclass
class MetadataCandidates:
    title: list[str] = field(default_factory=list)
    author: list[str] = field(default_factory=list)
    year: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {"title": self.title, "author": self.author, "year": self.year}


@dataclass
class FinalizeOptions:
    dpi: int = 300
    searchable_pdf: bool = True
    plain_text: bool = False
    pdf_a: bool = False

    @classmethod
    def from_dict(cls, data: dict) -> "FinalizeOptions":
        d = data or {}
        return cls(
            dpi=int(d.get("dpi", 300)),
            searchable_pdf=bool(d.get("searchable_pdf", True)),
            plain_text=bool(d.get("plain_text", False)),
            pdf_a=bool(d.get("pdf_a", False)),
        )


def ok_response(**fields) -> dict:
    return {"status": "ok", "error": None, **fields}


def error_response(message: str, **fields) -> dict:
    return {"status": "error", "error": message, **fields}
