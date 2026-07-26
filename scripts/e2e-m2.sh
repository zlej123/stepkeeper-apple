#!/bin/bash
# M2 E2E: 스텁 분석 + 실제 유튜브 캡처 → 이미지 포함 문서 생성 검증
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
SIM="iPhone 17 Pro"
BUNDLE=com.stepkeeper.app
URL="https://www.youtube.com/watch?v=4ioPBiTWm3M"

# 적응(Task 1 스파이크에서 배운 것, 컨텍스트 사전승인): 이전 실행이 남긴 좀비 스텁 서버 정리.
pkill -f stub-server.py 2>/dev/null || true

# 적응(Task 10 학습 사항, 컨텍스트 사전승인): -u로 stdout 버퍼링을 꺼서 로그 파일 리다이렉트 시에도
# [stub] 요청 로그가 유실 없이 즉시 flush되게 한다.
python3 -u scripts/stub-server.py 8787 &
STUB=$!
trap 'kill $STUB 2>/dev/null || true' EXIT
sleep 1

xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build | tail -2
# 적응(Task 10 학습 사항, 컨텍스트 사전승인): `simctl boot || true`(부팅 시작만 하고 완료를 기다리지
# 않음) 대신 bootstatus -b로 교체 — 이미 부팅돼 있으면 즉시 반환하고, 아니면 부팅 완료까지 블로킹 대기.
xcrun simctl bootstatus "$SIM" -b
# 적응(Task 10 학습 사항, 컨텍스트 사전승인): uninstall 없이 재설치하면 이전 실행(M1)의 앱 데이터
# 컨테이너(Documents/stepkeeper 잔여물 + M1이 저장한 linkMode=true UserDefaults)가 그대로 남아
# 이번 실행이 링크 모드로 새는 등 판정을 오염시킬 수 있다 — install 전에 제거한다.
xcrun simctl uninstall "$SIM" $BUNDLE 2>/dev/null || true
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/stepkeeper.app
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null || true
CONTAINER=$(xcrun simctl get_app_container "$SIM" $BUNDLE data)
rm -rf "$CONTAINER/Documents/stepkeeper"

SIMCTL_CHILD_STEPKEEPER_E2E_URL="$URL" \
  SIMCTL_CHILD_STEPKEEPER_SERVER_URL="http://127.0.0.1:8787" \
  xcrun simctl launch "$SIM" $BUNDLE

DOC=""
for i in $(seq 1 90); do
  DOC=$(ls "$CONTAINER"/Documents/stepkeeper/*/document.md 2>/dev/null | head -1) && [ -n "$DOC" ] && break
  sleep 2
done
[ -n "$DOC" ] || { echo "M2 E2E FAIL: document.md not produced"; exit 1; }
DIR=$(dirname "$DOC")
echo "--- document.md ---"
cat "$DOC"
grep -q '!\[요만큼\](vg-1.jpg)' "$DOC" || { echo "M2 E2E FAIL: no embedded image line"; exit 1; }
[ -f "$DIR/vg-1.jpg" ] || { echo "M2 E2E FAIL: vg-1.jpg missing"; exit 1; }
SIZE=$(stat -f%z "$DIR/vg-1.jpg")
[ "$SIZE" -gt 5000 ] || { echo "M2 E2E FAIL: vg-1.jpg too small ($SIZE bytes)"; exit 1; }
xcrun simctl io "$SIM" screenshot build/m2-screenshot.png >/dev/null 2>&1 || true
echo "M2 E2E PASS (image $SIZE bytes)"
