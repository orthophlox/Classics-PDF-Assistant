# Bundled asset licenses

## DejaVuSans.ttf

DejaVu fonts, derived from Bitstream Vera. Public-domain-like, freely
redistributable; see the Bitstream Vera license terms:
<https://dejavu-fonts.github.io/License.html>. Used by `textlayer.py` as the
OCR text-layer font (covers Latin + polytonic Greek, unlike the PDF base-14
fonts) and, as a fallback, wherever the packaged app doesn't ship its own
copy.

## sRGB.icc

sRGB IEC61966-2.1 ICC profile (from Debian's `icc-profiles-free` package,
zlib/libpng license — see
<https://salsa.debian.org/debian/icc-profiles-free>). Used by `export.py`
for the lightweight PDF/A output intent.
