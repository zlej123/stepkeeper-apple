#!/usr/bin/env python3
"""무료 Apple ID(Personal Team)로 실기기에 설치하기 위한 프로젝트 스펙 생성.

무료 계정은 App Group을 쓸 수 없다 — 그래서 공유 확장(YouTube 앱 → stepkipper)을
빼고, 앱 본체만 자동 서명으로 빌드한다. ShareInbox는 그룹이 없으면 전부 nil로
안전하게 동작하므로(공유 수신만 비활성) 앱 기능은 그대로다.

사용: DEVELOPMENT_TEAM=XXXXXXXXXX python3 scripts/make-device-spec.py
      xcodegen generate --spec project-device.yml
"""
import os
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
team = os.environ.get("DEVELOPMENT_TEAM", "").strip()
if not team:
    sys.exit("DEVELOPMENT_TEAM 환경변수가 필요합니다 (Xcode > Settings > Accounts에서 "
             "Apple ID를 추가한 뒤, 팀 ID를 확인해 넣으세요).\n"
             "  scripts/find-team-id.sh 로 조회할 수 있습니다.")

spec = yaml.safe_load((ROOT / "project.yml").read_text(encoding="utf-8"))
spec["name"] = "stepkipper-device"

app = spec["targets"]["Stepkipper"]
# 공유 확장 제거 — 무료 계정에서 App Group 자격이 나오지 않는다
app["dependencies"] = [d for d in app.get("dependencies", [])
                       if d.get("target") != "StepkipperShare"]
spec["targets"].pop("StepkipperShare", None)
# 테스트 타겟도 뺀다 (기기 설치에 불필요하고 서명 대상만 늘린다)
spec["targets"].pop("StepkipperTests", None)
for scheme in list(spec.get("schemes", {})):
    spec["schemes"].pop(scheme, None)

base = app["settings"]["base"]
base.pop("CODE_SIGN_ENTITLEMENTS[sdk=iphone*]", None)   # App Group 자격 제거
base.update({
    # 번들 ID를 분리해 스토어용/시뮬레이터용과 충돌하지 않게 한다
    "PRODUCT_BUNDLE_IDENTIFIER": "com.stepkipper.app.personal",
    "CODE_SIGN_STYLE": "Automatic",
    "CODE_SIGN_IDENTITY": "Apple Development",
    "CODE_SIGNING_REQUIRED": "YES",
    "CODE_SIGNING_ALLOWED": "YES",
    "DEVELOPMENT_TEAM": team,
    "TARGETED_DEVICE_FAMILY": "1",     # 아이폰 전용
})
base.pop("CODE_SIGN_ENTITLEMENTS[sdk=macosx*]", None)
app["supportedDestinations"] = ["iOS"]

out = ROOT / "project-device.yml"
out.write_text(yaml.safe_dump(spec, allow_unicode=True, sort_keys=False), encoding="utf-8")
print(f"{out.name} 생성 (팀 {team}, 공유 확장 제외, 번들 ID com.stepkipper.app.personal)")
print("다음: xcodegen generate --spec project-device.yml && open stepkipper-device.xcodeproj")
