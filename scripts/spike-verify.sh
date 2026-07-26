#!/bin/bash
# M0 스파이크: 시뮬레이터에서 앱을 실행해 캡처를 수행하고 result.json을 판정한다.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
SIM="iPhone 17 Pro"
BUNDLE=com.stepkeeper.app

xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build | tail -2
xcrun simctl boot "$SIM" 2>/dev/null || true
# 이전 실행의 잔여 result.json이 새 실행 판정을 가짜로 통과시키지 않도록 데이터 초기화.
xcrun simctl uninstall "$SIM" $BUNDLE 2>/dev/null || true
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/stepkeeper.app
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null || true
SIMCTL_CHILD_STEPKEEPER_SPIKE=1 xcrun simctl launch "$SIM" $BUNDLE

# 스파이크 하네스는 홈 화면에서 진입해야 하므로 UI 없이는 자동 진입이 안 된다 →
# 앱 시작 시 STEPKEEPER_SPIKE=1이면 스파이크 뷰를 루트로 띄우는 분기가 StepkeeperApp에 필요(Step 8).
CONTAINER=$(xcrun simctl get_app_container "$SIM" $BUNDLE data)
RESULT="$CONTAINER/Documents/spike/result.json"
echo "waiting for $RESULT"
# 워치독 예산(PlayerBridge): waitForMetadata 90s + primePlayer 10s + capture 30s*3 = 193s 최악치.
# 여유를 두고 90회 * 4s = 360s까지 대기.
for i in $(seq 1 90); do
  [ -f "$RESULT" ] && break
  sleep 4
done
[ -f "$RESULT" ] || { echo "SPIKE FAIL: result.json not produced"; exit 1; }
cat "$RESULT"
python3 - "$RESULT" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
assert r.get("ok"), f"spike not ok: {r}"
print("SPIKE PASS (iOS simulator)")
EOF
