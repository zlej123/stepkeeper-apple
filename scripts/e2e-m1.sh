#!/bin/bash
# M1 E2E: 스텁 서버 + 시뮬레이터 + 실제 유튜브 플레이어(메타데이터) → 링크 모드 문서 생성 검증
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
SIM="iPhone 17 Pro"
BUNDLE=com.stepkipper.app
URL="https://www.youtube.com/watch?v=4ioPBiTWm3M"

# 적응(Task 1 스파이크에서 배운 것, 컨텍스트 사전승인): 이전 실행이 남긴 좀비 스텁 서버 정리.
pkill -f stub-server.py 2>/dev/null || true

python3 scripts/stub-server.py 8787 &
STUB=$!
trap 'kill $STUB 2>/dev/null || true' EXIT
sleep 1

xcodebuild -project stepkipper-apple.xcodeproj -scheme Stepkipper \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build | tail -2
# 적응: `simctl boot || true`(부팅 시작만 하고 완료를 기다리지 않음) 대신 bootstatus -b로 교체 —
# 이미 부팅돼 있으면 즉시 반환하고, 아니면 부팅 완료까지 블로킹 대기한다.
xcrun simctl bootstatus "$SIM" -b
# 적응(Task 1 스파이크에서 배운 것, 컨텍스트 사전승인): uninstall 없이 재설치하면 이전 실행의
# Documents/stepkipper 잔여물이 새 실행 판정을 가짜로 통과시킬 수 있다 — install 전에 제거한다.
xcrun simctl uninstall "$SIM" $BUNDLE 2>/dev/null || true
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/stepkipper.app
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null || true
CONTAINER=$(xcrun simctl get_app_container "$SIM" $BUNDLE data)
rm -rf "$CONTAINER/Documents/stepkipper"

SIMCTL_CHILD_STEPKIPPER_E2E_URL="$URL" SIMCTL_CHILD_STEPKIPPER_LINK_MODE=1 \
  SIMCTL_CHILD_STEPKIPPER_SERVER_URL="http://127.0.0.1:8787" \
  xcrun simctl launch "$SIM" $BUNDLE

DOC=""
for i in $(seq 1 60); do
  DOC=$(ls "$CONTAINER"/Documents/stepkipper/*/document.md 2>/dev/null | head -1) && [ -n "$DOC" ] && break
  sleep 2
done
[ -n "$DOC" ] || { echo "M1 E2E FAIL: document.md not produced"; exit 1; }
echo "--- document.md ---"
cat "$DOC"
grep -q "▶ \[영상" "$DOC" || { echo "M1 E2E FAIL: no link fallback"; exit 1; }
grep -q "stepkipper로 생성" "$DOC" || { echo "M1 E2E FAIL: no footer"; exit 1; }
ls "$(dirname "$DOC")" | grep -q "analysis.json" || { echo "M1 E2E FAIL: no analysis.json"; exit 1; }
xcrun simctl io "$SIM" screenshot build/m1-screenshot.png >/dev/null 2>&1 || true
echo "M1 E2E PASS"
