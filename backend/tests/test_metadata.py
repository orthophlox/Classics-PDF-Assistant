from pdf_backend import metadata
from pdf_backend.geometry import BoundingBox
from pdf_backend.schemas import Word


def _w(text, x, y, width, height):
    return Word(text=text, bbox=BoundingBox(x=x, y=y, width=width, height=height), confidence=90.0)


def _title_page_words() -> list[Word]:
    # Line 1: big title (two words, same line)
    line1 = [_w("ILIAS", 100, 100, 220, 60)]
    # Line 2: author byline
    line2 = [_w("Homer", 150, 220, 120, 30)]
    # Line 3: translator credit (author-pattern line)
    line3 = [
        _w("translated", 100, 320, 130, 20),
        _w("by", 240, 320, 30, 20),
        _w("Richard", 280, 320, 90, 20),
        _w("Lattimore", 380, 320, 110, 20),
    ]
    # Line 4: place + year
    line4 = [_w("Chicago", 150, 400, 100, 18), _w("1951", 260, 400, 60, 18)]
    return line1 + line2 + line3 + line4


def test_cluster_lines_groups_by_vertical_overlap_and_sorts_left_to_right():
    words = [
        _w("World", 200, 100, 100, 40),
        _w("Hello", 50, 102, 100, 40),
        _w("Second", 50, 300, 100, 30),
        _w("Line", 200, 305, 100, 30),
    ]
    lines = metadata.cluster_lines(words)

    assert len(lines) == 2
    assert [w.text for w in lines[0]] == ["Hello", "World"]
    assert [w.text for w in lines[1]] == ["Second", "Line"]


def test_line_median_height():
    line = [_w("a", 0, 0, 10, 20), _w("b", 20, 0, 10, 30), _w("c", 40, 0, 10, 40)]
    assert metadata.line_median_height(line) == 30


def test_extract_candidates_finds_title_author_year():
    candidates = metadata.extract_candidates([_title_page_words()])

    assert "ILIAS" in candidates.title
    assert any("Lattimore" in a for a in candidates.author)
    assert "1951" in candidates.year


def test_extract_candidates_handles_empty_page():
    candidates = metadata.extract_candidates([[]])
    assert candidates.title == []
    assert candidates.author == []
    assert candidates.year == []


def test_extract_candidates_falls_back_to_second_line_when_no_author_pattern():
    words = [_w("BIG TITLE", 100, 100, 300, 60), _w("Some Author Name", 100, 200, 200, 28)]
    candidates = metadata.extract_candidates([words])

    assert "BIG TITLE" in candidates.title
    assert candidates.author and candidates.author[0] == "Some Author Name"


def test_sanitize_filename_strips_illegal_characters():
    assert metadata.sanitize_filename("Homer: Ilias / A Translation?") == "Homer Ilias A Translation"
    assert metadata.sanitize_filename('Weird\\/:*?"<>|Name') == "WeirdName"
    assert metadata.sanitize_filename("   ") == "untitled"


def test_render_filename_applies_template():
    assert metadata.render_filename("Homer", "Ilias", "1920") == "Homer - Ilias (1920)"


def test_render_filename_degrades_gracefully_when_fields_missing():
    assert metadata.render_filename(None, "Ilias", None) == "Ilias"
    assert metadata.render_filename(None, None, "1920") == "Untitled (1920)"
    assert metadata.render_filename(None, None, None) == "Untitled"
