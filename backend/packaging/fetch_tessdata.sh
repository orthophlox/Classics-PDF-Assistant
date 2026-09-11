#!/usr/bin/env bash
# Downloads grc/lat/eng tessdata_best language files for bundling into the
# macOS app. tessdata_best (not _fast) is used deliberately: classical-
# language OCR accuracy matters more than speed for this manual,
# per-document workflow. Run this before pyinstaller.spec's datas step
# picks up backend/packaging/tessdata/.
#
# Usage: ./fetch_tessdata.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$SCRIPT_DIR/tessdata"
BASE_URL="https://github.com/tesseract-ocr/tessdata_best/raw/main"
LANGS=(eng grc lat osd)

mkdir -p "$DEST"

for lang in "${LANGS[@]}"; do
  dest_file="$DEST/${lang}.traineddata"
  if [ -f "$dest_file" ]; then
    echo "already present: $dest_file"
    continue
  fi
  echo "downloading ${lang}.traineddata ..."
  curl -fL "$BASE_URL/${lang}.traineddata" -o "$dest_file"
done

echo "tessdata ready at $DEST"
