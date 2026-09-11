#!/usr/bin/env bash
# Builds Classics PDF Assistant end-to-end and packages it as a
# double-click-installable .dmg. macOS only — see README.md "Distributing
# a .dmg" for what this does and why each step exists.
#
# Usage: ./scripts/build_dmg.sh
#
# Prerequisites (all checked below, with an actionable error if missing):
#   - Xcode (for xcodebuild) and its command-line tools
#   - XcodeGen: brew install xcodegen
#   - Homebrew Tesseract: brew install tesseract tesseract-lang
#   - Python 3.10+
#
# Output: dist/ClassicsPDFAssistant.dmg

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "build_dmg.sh must run on macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClassicsPDFAssistant"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/ClassicsPDFAssistant/build"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1 — $2" >&2
    exit 1
  fi
}

require xcodebuild "install Xcode from the App Store, then run: xcode-select --install"
require xcodegen "brew install xcodegen"
require python3 "install Python 3.10+ (e.g. brew install python@3.12)"

echo "== 1/5: Python backend dependencies =="
if [[ ! -d "$ROOT_DIR/.venv" ]]; then
  python3 -m venv "$ROOT_DIR/.venv"
fi
source "$ROOT_DIR/.venv/bin/activate"
pip install --upgrade pip -q
pip install -r "$ROOT_DIR/backend/requirements.txt" -q
deactivate

echo "== 2/5: Freeze the backend (PyInstaller + vendored Tesseract) =="
"$ROOT_DIR/backend/packaging/build_backend.sh"

echo "== 3/5: Generate the Xcode project =="
(cd "$ROOT_DIR/ClassicsPDFAssistant" && xcodegen generate)

echo "== 4/5: Build the app (Release, ad-hoc signed) =="
# CODE_SIGN_IDENTITY="-" (ad-hoc) needs no Apple Developer account — anyone
# building this locally can produce a runnable .app. This is NOT the same
# as a Developer ID signature: Gatekeeper will still warn on first launch
# on another Mac (or the same Mac, once quarantined by the .dmg download/
# mount). See README.md for how to open it anyway, and what real
# distribution (Developer ID + notarization) would additionally require.
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$ROOT_DIR/ClassicsPDFAssistant/ClassicsPDFAssistant.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build did not produce $APP_PATH — check the xcodebuild output above." >&2
  exit 1
fi

echo "== 5/5: Package as a .dmg =="
mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Classics PDF Assistant" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo
echo "Done: $DMG_PATH"
echo "This build is ad-hoc signed, not notarized — on first open, Gatekeeper"
echo "will show an 'unidentified developer' warning. Right-click the app in"
echo "Finder and choose Open (or System Settings > Privacy & Security >"
echo "Open Anyway) once; subsequent launches are normal. See README.md."
