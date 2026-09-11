import numpy as np

from pdf_backend import pdf_io
from tests.helpers import synthetic


def test_to_bw_produces_only_two_intensity_levels():
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)

    bw = pdf_io.to_bw(arr)

    assert bw.ndim == 2
    assert set(np.unique(bw).tolist()) <= {0, 255}


def test_to_bw_keeps_ink_black_on_white_background():
    # A page that's mostly white background with a modest amount of black
    # text should stay mostly white (255) after conversion — this is the
    # opposite polarity from crop.py/deskew.py's internal ink-mass analysis,
    # which inverts (ink=foreground=255) for contour detection.
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)

    bw = pdf_io.to_bw(arr)

    white_fraction = (bw == 255).mean()
    assert white_fraction > 0.5


def test_to_bw_on_blank_page_is_entirely_white():
    from PIL import Image

    blank = Image.new("L", (200, 300), color=255)
    arr = synthetic.to_rgb_ndarray(blank)

    bw = pdf_io.to_bw(arr)

    assert (bw == 255).all()
