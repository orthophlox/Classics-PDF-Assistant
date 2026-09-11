#!/usr/bin/env bash
# Fully removes Classics PDF Assistant: quits it if running, deletes its
# saved settings and temporary working files, then deletes the app itself
# from /Applications. Never touches anything the app exported (PDFs, .txt
# files, etc.) — those live wherever the user chose to save them, entirely
# separate from what this script deletes.
#
# Double-click this file in Finder to run it (it opens in Terminal). It's
# copied alongside the .app in the .dmg by scripts/build_dmg.sh — see
# README.md "제거하기" for the in-app alternative (App menu > Uninstall…),
# which stops short of deleting the .app itself since a running app
# deleting its own bundle is fragile; this script has no such constraint
# because it isn't the app.

set -uo pipefail

BUNDLE_ID="com.classicspdfassistant.app"  # must match project.yml's PRODUCT_BUNDLE_IDENTIFIER
APP_NAME="ClassicsPDFAssistant"
APP_PATH="/Applications/$APP_NAME.app"

echo "이 스크립트는 Classics PDF Assistant를 완전히 제거합니다:"
echo "  - 앱 실행 중이면 종료"
echo "  - 저장된 설정 삭제"
echo "  - 임시 작업 파일 삭제"
echo "  - $APP_PATH 삭제"
echo
echo "내보낸 PDF 등 사용자 문서는 전혀 건드리지 않습니다."
echo
read -r -p "계속할까요? [y/N] " confirm
case "$confirm" in
  y|Y|yes|YES) ;;
  *) echo "취소했습니다."; read -r -p "Enter를 눌러 창을 닫으세요..." _; exit 0 ;;
esac

echo
echo "== 앱 종료 =="
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
sleep 1
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "== 설정 삭제 =="
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || echo "  (저장된 설정 없음)"

echo "== 임시 작업 파일 삭제 =="
TEMP_ROOT="${TMPDIR:-/tmp}/$APP_NAME"
if [ -d "$TEMP_ROOT" ]; then
  rm -rf "$TEMP_ROOT"
  echo "  삭제됨: $TEMP_ROOT"
else
  echo "  (임시 파일 없음)"
fi

echo "== 앱 삭제 =="
if [ -d "$APP_PATH" ]; then
  if rm -rf "$APP_PATH" 2>/dev/null; then
    echo "  삭제됨: $APP_PATH"
  else
    echo "  권한이 필요합니다 — 관리자 암호를 입력해 주세요."
    sudo rm -rf "$APP_PATH"
    echo "  삭제됨: $APP_PATH"
  fi
else
  echo "  (/Applications 에서 $APP_NAME.app을 찾지 못했습니다 — 다른 위치에 설치했다면 직접 휴지통으로 옮겨주세요)"
fi

echo
echo "제거를 완료했습니다."
read -r -p "Enter를 눌러 창을 닫으세요..." _
