from pdf_backend import deskew
from tests.helpers import synthetic


def test_rotate_image_roundtrip_is_close_to_original_content_bbox():
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)

    rotated = deskew.rotate_image(arr, 5.0)
    restored = deskew.rotate_image(rotated, -5.0)

    # Rotation expands the canvas, so just check we didn't crash and the
    # restored image still contains dark (text) pixels roughly proportional
    # to the original — a coarse sanity check, not pixel-exact (interpolation).
    gray_before = deskew.to_gray(arr)
    gray_after = deskew.to_gray(restored)
    dark_before = (gray_before < 128).sum()
    dark_after = (gray_after < 128).sum()
    assert dark_after > dark_before * 0.5


def test_detect_fine_skew_angle_recovers_known_rotation():
    page = synthetic.make_text_page()

    for true_angle in (-6.0, -2.0, 3.0, 7.5):
        rotated_page = synthetic.rotate_page(page, true_angle)
        rotated_arr = synthetic.to_rgb_ndarray(rotated_page)

        detected = deskew.detect_fine_skew_angle(rotated_arr)

        # PIL's rotate() and cv2's warpAffine-based rotate_image() use opposite
        # sign conventions for "counter-clockwise"; what matters is that
        # detect_fine_skew_angle's output, fed straight back into
        # rotate_image (as deskew() does), cancels the rotation applied here
        # — verified separately in test_deskew_reduces_measured_skew_close_to_zero.
        # This test just checks the detector tracks the magnitude/sign of the
        # PIL-applied rotation consistently.
        assert abs(detected - true_angle) < 1.5, (
            f"true_angle={true_angle} detected={detected}"
        )


def test_deskew_reduces_measured_skew_close_to_zero():
    page = synthetic.make_text_page()

    for true_angle in (-5.0, 4.0, 8.0):
        rotated_page = synthetic.rotate_page(page, true_angle)
        rotated_arr = synthetic.to_rgb_ndarray(rotated_page)

        corrected, applied_angle = deskew.deskew(rotated_arr, correct_orientation=False)

        residual = deskew.detect_fine_skew_angle(corrected)
        assert abs(residual) < 1.5, f"true_angle={true_angle} residual={residual}"


def test_detect_fine_skew_angle_near_zero_for_unrotated_page():
    page = synthetic.make_text_page()
    arr = synthetic.to_rgb_ndarray(page)
    angle = deskew.detect_fine_skew_angle(arr)
    assert abs(angle) < 1.0


def test_detect_osd_rotation_handles_upright_page_gracefully():
    page = synthetic.make_text_page(lines=[f"Text line {i} for OSD detection testing purposes." for i in range(25)])
    arr = synthetic.to_rgb_ndarray(page)
    # Should not raise; upright text should report 0 (or occasionally be
    # uncertain on a synthetic page — both are acceptable, only crashing isn't).
    rotation = deskew.detect_osd_rotation(arr)
    assert rotation in (0, 90, 180, 270)
