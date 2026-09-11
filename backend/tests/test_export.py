import pikepdf

from pdf_backend import export, textlayer
from pdf_backend.geometry import BoundingBox
from pdf_backend.schemas import Word
from tests.helpers import synthetic


def _w(text, x, y, width, height):
    return Word(text=text, bbox=BoundingBox(x=x, y=y, width=width, height=height), confidence=90.0)


def _sample_page_words():
    return [
        _w("Hello", 50, 100, 100, 30),
        _w("world", 160, 102, 100, 30),
        _w("Second", 50, 200, 100, 30),
        _w("line", 160, 202, 60, 30),
    ]


def test_words_to_text_orders_lines_and_words():
    text = export.words_to_text([_sample_page_words()])
    assert text == "Hello world\nSecond line"


def test_words_to_text_separates_pages_with_form_feed():
    text = export.words_to_text([_sample_page_words(), _sample_page_words()])
    assert text.count("\f") == 1
    pages = text.split("\f")
    assert len(pages) == 2
    assert pages[0] == pages[1] == "Hello world\nSecond line"


def test_write_plain_text_creates_file(tmp_path):
    out = tmp_path / "out.txt"
    export.write_plain_text([_sample_page_words()], str(out))
    assert out.read_text(encoding="utf-8") == "Hello world\nSecond line"


def test_make_pdf_a_leaning_adds_xmp_and_output_intent(tmp_path):
    page = synthetic.make_text_page(width=900, height=1200)
    arr = synthetic.to_rgb_ndarray(page)
    words = [_w("Test", 100, 100, 100, 30)]
    pdf_bytes = textlayer.build_page_pdf(arr, words=words, dpi=300)

    src = tmp_path / "in.pdf"
    src.write_bytes(pdf_bytes)
    dst = tmp_path / "out_pdfa.pdf"

    export.make_pdf_a_leaning(str(src), str(dst), title="Test Document")

    assert dst.exists()
    with pikepdf.open(str(dst)) as pdf:
        with pdf.open_metadata() as meta:
            assert meta.get("pdfaid:part") == "2"
            assert meta.get("pdfaid:conformance") == "B"
            assert meta.get("dc:title") == "Test Document"
        assert "/OutputIntents" in pdf.Root
        assert len(pdf.Root.OutputIntents) == 1
