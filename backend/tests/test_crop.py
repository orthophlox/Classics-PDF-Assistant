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


def test_detect_regions_plain_page_yields_single_main_text_region():
    # No apparatus/margin numbers — the common case outside critical
    # editions — should behave like detect_text_region: one region.
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)

    regions = crop.detect_regions(arr)

    assert len(regions) == 1
    assert regions[0].region_type == "main_text"
    assert regions[0].bbox == crop.detect_text_region(arr)


def _region_types(regions):
    return {r.region_type for r in regions}


def test_detect_regions_classifies_critical_edition_layout():
    page = synthetic.make_critical_edition_page()
    arr = synthetic.to_rgb_ndarray(page)

    regions = crop.detect_regions(arr)
    by_type = {r.region_type: r.bbox for r in regions}

    assert "main_text" in by_type
    assert "apparatus" in by_type
    assert "margin_left" in by_type
    assert "margin_right" in by_type

    main_text = by_type["main_text"]
    apparatus = by_type["apparatus"]
    margin_left = by_type["margin_left"]
    margin_right = by_type["margin_right"]

    # Apparatus sits below the main text, not overlapping it.
    assert apparatus.y >= main_text.y2 - 5

    # Margins are narrow and sit outside the main text column on either side.
    assert margin_left.x2 <= main_text.x
    assert margin_right.x >= main_text.x2
    assert margin_left.width < main_text.width * 0.3
    assert margin_right.width < main_text.width * 0.3

    # Main text remains the largest region by area.
    main_area = main_text.width * main_text.height
    for region_type, bbox in by_type.items():
        if region_type == "main_text":
            continue
        assert bbox.width * bbox.height < main_area


def test_detect_regions_padding_expands_each_region_within_bounds():
    page = synthetic.make_critical_edition_page()
    arr = synthetic.to_rgb_ndarray(page)

    tight = {r.region_type: r.bbox for r in crop.detect_regions(arr, padding=0)}
    padded = {r.region_type: r.bbox for r in crop.detect_regions(arr, padding=15)}

    assert tight.keys() == padded.keys()
    for region_type in tight:
        assert padded[region_type].width >= tight[region_type].width
        assert padded[region_type].height >= tight[region_type].height


def test_detect_regions_falls_back_to_full_image_for_blank_page():
    from PIL import Image

    blank = Image.new("L", (500, 700), color=255)
    arr = synthetic.to_rgb_ndarray(blank)

    regions = crop.detect_regions(arr)

    assert len(regions) == 1
    assert regions[0].region_type == "main_text"
    assert regions[0].bbox.width == 500 and regions[0].bbox.height == 700
