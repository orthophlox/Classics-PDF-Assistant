#!/usr/bin/env bash
# Generates/updates appcast.xml for Sparkle auto-updates from a folder of
# released .dmg builds. See README.md "자동 업데이트 설정하기" for the
# full one-time setup (signing keypair, hosting, Info.plist) this fits into.
#
# Prerequisites:
#   - Sparkle's command-line tools (generate_appcast, sign_update,
#     generate_keys). These ship in the "Sparkle-x.y.z.tar.xz" (or .zip)
#     release asset at https://github.com/sparkle-project/Sparkle/releases
#     — NOT the same thing as the SPM package Xcode resolves for the app
#     itself, which doesn't reliably expose these binaries at a fixed path.
#     Download that asset once and note its bin/ directory.
#   - A signing keypair already created once via that distribution's
#     bin/generate_keys (stores the private key in your Keychain — never
#     commit it anywhere, including here).
#
# Usage:
#   ./scripts/generate_appcast.sh /path/to/releases-folder [--tools-dir DIR]
#
# releases-folder should contain every .dmg you've shipped. generate_appcast
# scans it, signs each archive with the Keychain-stored private key, and
# writes/updates appcast.xml in that same folder.

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "generate_appcast.sh must run on macOS (Sparkle's tools are macOS-only)." >&2
  exit 1
fi

RELEASES_DIR="${1:-}"
if [[ -z "$RELEASES_DIR" ]]; then
  echo "Usage: $0 /path/to/releases-folder [--tools-dir DIR]" >&2
  exit 1
fi
shift || true

TOOLS_DIR=""
if [[ "${1:-}" == "--tools-dir" && -n "${2:-}" ]]; then
  TOOLS_DIR="$2"
fi

find_tool() {
  local name="$1"
  if [[ -n "$TOOLS_DIR" && -x "$TOOLS_DIR/$name" ]]; then
    echo "$TOOLS_DIR/$name"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  # Sometimes reachable here when Xcode has already resolved Sparkle as an
  # SPM package dependency for the app target — not guaranteed, hence the
  # --tools-dir escape hatch above.
  local spm_hit
  spm_hit="$(find ~/Library/Developer/Xcode/DerivedData -path "*artifacts/sparkle/Sparkle/bin/$name" -print -quit 2>/dev/null || true)"
  if [[ -n "$spm_hit" ]]; then
    echo "$spm_hit"
    return 0
  fi
  return 1
}

GENERATE_APPCAST="$(find_tool generate_appcast || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "Couldn't find generate_appcast." >&2
  echo "Download the Sparkle release archive (.tar.xz/.zip, not the source" >&2
  echo "checkout) from https://github.com/sparkle-project/Sparkle/releases" >&2
  echo "and pass its bin/ directory: $0 $RELEASES_DIR --tools-dir /path/to/bin" >&2
  exit 1
fi

echo "Using generate_appcast: $GENERATE_APPCAST"
"$GENERATE_APPCAST" "$RELEASES_DIR"

echo
echo "appcast.xml written to $RELEASES_DIR — host this folder (or at least"
echo "appcast.xml plus the .dmg files) somewhere reachable, and point"
echo "Info.plist's SUFeedURL at the appcast.xml URL."
