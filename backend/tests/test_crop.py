from pdf_backend import crop
from tests.helpers import synthetic


def test_detect_text_region_excludes_wide_white_margin():
    width, height, margin = 1000, 1400, 150
    page = synthetic.make_text_page(width=width, height=height, margin=margin)
    arr = synthetic.to_rgb_ndarray(page)

    box = crop.detect_text_region(arr)

    # The detected box should be well inside the full page and roughly
    # aligned with the margin the text was drawn at (some slack for font
    # ascenders/descenders and morphological padding).
    assert box.x > margin * 0.5
    assert box.y > margin * 0.5
    assert box.x2 < width - margin * 0.5
    assert box.width < width * 0.8
    assert box.height < height * 0.8


def test_detect_text_region_ignores_border_noise():
    width, height, margin = 1000, 1400, 150
    page = synthetic.make_text_page(width=width, height=height, margin=margin)
    page_with_noise = synthetic.add_border_noise(page, thickness=12)
    arr = synthetic.to_rgb_ndarray(page_with_noise)

    box = crop.detect_text_region(arr)

    # Detected region must not extend all the way to the noisy border.
    assert box.x > 12
    assert box.y > 12
    assert box.x2 < width - 12
    assert box.y2 < height - 12


def test_detect_text_region_padding_expands_box_within_bounds():
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)

    tight = crop.detect_text_region(arr, padding=0)
    padded = crop.detect_text_region(arr, padding=30)

    assert padded.width >= tight.width
    assert padded.height >= tight.height
    assert padded.x <= tight.x
    assert padded.y <= tight.y


def test_detect_text_region_falls_back_to_full_image_for_blank_page():
    from PIL import Image

    blank = Image.new("L", (500, 700), color=255)
    arr = synthetic.to_rgb_ndarray(blank)

    box = crop.detect_text_region(arr)

    assert box.x == 0 and box.y == 0
    assert box.width == 500 and box.height == 700
