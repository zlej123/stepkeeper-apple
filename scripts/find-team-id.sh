#!/bin/bash
# 무료 Apple ID의 Personal Team ID 조회.
# Xcode > Settings > Accounts 에서 Apple ID를 먼저 추가해야 나온다.
set -u
echo "== 코드 서명 인증서"
security find-identity -v -p codesigning | sed 's/^/  /'
echo
echo "== Xcode가 내려받은 프로비저닝 프로파일의 팀"
dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [ -d "$dir" ] && ls "$dir"/*.mobileprovision >/dev/null 2>&1; then
  for p in "$dir"/*.mobileprovision; do
    security cms -D -i "$p" 2>/dev/null \
      | plutil -extract TeamIdentifier.0 raw - 2>/dev/null \
      | sed 's/^/  /'
  done | sort -u
else
  echo "  (없음 — Xcode에서 Apple ID 추가 후 기기 연결 상태로 한 번 빌드하면 생성됩니다)"
fi
echo
echo "인증서 줄의 괄호 안 10자리가 팀 ID입니다. 예: Apple Development: me@x.com (A1B2C3D4E5)"
