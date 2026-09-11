"""Heuristic bibliographic-metadata extraction from OCR'd title-page words,
for the auto-rename feature. Always returns ranked *candidate* lists, never
a single forced answer — the Swift RenameSuggestionSheet pre-fills these but
the user edits before the filename is applied.
"""

from __future__ import annotations

import re

from .schemas import MetadataCandidates, Word

_AUTHOR_PATTERN = re.compile(
    r"\b(?:by|tr(?:ans)?\.?(?:\s*by)?|translated\s+by|übersetzt\s+von|ed(?:ited)?\.?\s*by)\s+(.+)",
    re.IGNORECASE,
)
_YEAR_PATTERN = re.compile(r"\b(1[4-9]\d{2}|20\d{2})\b")

_LINE_Y_OVERLAP_FRACTION = 0.5  # two words share a line if their bboxes overlap vertically by at least this much


def cluster_lines(words: list[Word]) -> list[list[Word]]:
    """Group words into reading-order lines by vertical bbox overlap, then
    sort each line left-to-right. Independent of font size within a line.
    """
    remaining = sorted(words, key=lambda w: w.bbox.y)
    lines: list[list[Word]] = []

    for word in remaining:
        placed = False
        for line in lines:
            anchor = line[0]
            overlap = min(word.bbox.y2, anchor.bbox.y2) - max(word.bbox.y, anchor.bbox.y)
            min_height = min(word.bbox.height, anchor.bbox.height)
            if min_height > 0 and overlap / min_height >= _LINE_Y_OVERLAP_FRACTION:
                line.append(word)
                placed = True
                break
        if not placed:
            lines.append([word])

    for line in lines:
        line.sort(key=lambda w: w.bbox.x)
    lines.sort(key=lambda line: min(w.bbox.y for w in line))
    return lines


def line_text(line: list[Word]) -> str:
    return " ".join(w.text for w in line).strip()


def line_median_height(line: list[Word]) -> float:
    heights = sorted(w.bbox.height for w in line)
    n = len(heights)
    if n == 0:
        return 0.0
    mid = n // 2
    return heights[mid] if n % 2 else (heights[mid - 1] + heights[mid]) / 2.0


def extract_candidates(pages: list[list[Word]], max_candidates: int = 3) -> MetadataCandidates:
    """`pages` is one word list per page (typically page 1, optionally page 2),
    already in the order they should be considered.
    """
    all_lines: list[list[Word]] = []
    for page_words in pages:
        all_lines.extend(cluster_lines(page_words))

    texts = [line_text(line) for line in all_lines]

    years: list[str] = []
    for text in texts:
        for match in _YEAR_PATTERN.finditer(text):
            year = match.group(1)
            if year not in years:
                years.append(year)
    years = years[:max_candidates]

    authors: list[str] = []
    for text in texts:
        match = _AUTHOR_PATTERN.search(text)
        if match:
            candidate = match.group(1).strip().strip(".,;:")
            if candidate and candidate not in authors:
                authors.append(candidate)

    author_line_indices = {i for i, text in enumerate(texts) if _AUTHOR_PATTERN.search(text)}
    year_only_indices = {
        i for i, text in enumerate(texts) if _YEAR_PATTERN.fullmatch(text.strip())
    }
    excluded = author_line_indices | year_only_indices

    ranked = sorted(
        (i for i in range(len(all_lines)) if i not in excluded and texts[i]),
        key=lambda i: line_median_height(all_lines[i]),
        reverse=True,
    )

    titles: list[str] = []
    for i in ranked:
        text = texts[i]
        if text not in titles:
            titles.append(text)
        if len(titles) >= max_candidates:
            break

    if not authors and len(ranked) >= 2:
        # No explicit "by"/"tr." line found — on a typical title page the
        # second-largest text block (after the title itself) is the author
        # byline, so use it as a fallback guess even if it also made the
        # title-candidates list above.
        fallback = texts[ranked[1]]
        if fallback:
            authors.append(fallback)

    return MetadataCandidates(title=titles, author=authors[:max_candidates], year=years)


_ILLEGAL_FILENAME_CHARS = re.compile(r'[\/:\\\?\*"<>\|\x00-\x1f]')


def sanitize_filename(name: str) -> str:
    cleaned = _ILLEGAL_FILENAME_CHARS.sub("", name)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned or "untitled"


def render_filename(author: str | None, title: str | None, year: str | None) -> str:
    """`{author} - {title} ({year})`, gracefully degrading when a field is
    missing (batch mode / no candidates found), never producing an empty name.
    """
    parts = []
    if author:
        parts.append(sanitize_filename(author))
    if title:
        parts.append(sanitize_filename(title))
    name = " - ".join(parts) if parts else "Untitled"
    if year:
        name = f"{name} ({sanitize_filename(year)})"
    return name
