import os
import sys

import pytesseract

from pdf_backend.bundle import configure_bundled_tesseract


def test_configure_bundled_tesseract_is_noop_when_not_frozen():
    original_cmd = pytesseract.pytesseract.tesseract_cmd
    original_tessdata_prefix = os.environ.get("TESSDATA_PREFIX")

    assert not getattr(sys, "frozen", False)
    configure_bundled_tesseract()

    assert pytesseract.pytesseract.tesseract_cmd == original_cmd
    assert os.environ.get("TESSDATA_PREFIX") == original_tessdata_prefix


def test_configure_bundled_tesseract_points_at_vendored_binary_when_frozen(tmp_path, monkeypatch):
    bundle_dir = tmp_path / "bundle"
    bundle_dir.mkdir()
    fake_tesseract = bundle_dir / "tesseract"
    fake_tesseract.write_text("#!/bin/sh\n")
    fake_tesseract.chmod(0o755)
    (bundle_dir / "tessdata").mkdir()

    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "_MEIPASS", str(bundle_dir), raising=False)
    monkeypatch.delenv("TESSDATA_PREFIX", raising=False)

    original_cmd = pytesseract.pytesseract.tesseract_cmd
    try:
        configure_bundled_tesseract()
        assert pytesseract.pytesseract.tesseract_cmd == str(fake_tesseract)
        assert os.environ.get("TESSDATA_PREFIX") == str(bundle_dir / "tessdata")
    finally:
        pytesseract.pytesseract.tesseract_cmd = original_cmd
        # configure_bundled_tesseract() sets TESSDATA_PREFIX via plain
        # os.environ.setdefault(), not through monkeypatch — monkeypatch's
        # delenv above only reverts what *it* changed, so a value the
        # function under test writes afterward needs explicit cleanup here
        # or it leaks into every later test in the session (as it did: real
        # OCR tests started failing, looking for tessdata at this fake path).
        os.environ.pop("TESSDATA_PREFIX", None)


def test_configure_bundled_tesseract_leaves_tessdata_prefix_alone_if_already_set(tmp_path, monkeypatch):
    bundle_dir = tmp_path / "bundle"
    bundle_dir.mkdir()
    (bundle_dir / "tesseract").write_text("#!/bin/sh\n")
    (bundle_dir / "tessdata").mkdir()

    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "_MEIPASS", str(bundle_dir), raising=False)
    monkeypatch.setenv("TESSDATA_PREFIX", "/some/explicit/path")

    original_cmd = pytesseract.pytesseract.tesseract_cmd
    try:
        configure_bundled_tesseract()
        assert os.environ["TESSDATA_PREFIX"] == "/some/explicit/path"
    finally:
        pytesseract.pytesseract.tesseract_cmd = original_cmd
