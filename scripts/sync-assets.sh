#!/bin/bash
# skill-core 자산(템플릿·프롬프트·스키마·규칙)을 앱 리소스로 복사 (원본: ../stepkeeper).
# 코어 갱신 시 재실행 후 make-golden.py / make-notion-golden.py 재생성.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${STEPKIPPER_PATH:-../stepkeeper}/src/stepkeeper/skill-core"
for p in generic recipe; do
  mkdir -p "Resources/skill-core/$p"
  cp "$SRC/profiles/$p/template.md" "Resources/skill-core/$p/template.md"
  for lang in ko ja; do
    cp "$SRC/profiles/$p/template.$lang.md" "Resources/skill-core/$p/template.$lang.md"
  done
  cp "$SRC/profiles/$p/prompt.md"   "Resources/skill-core/$p/prompt.md"
  cp "$SRC/profiles/$p/schema.json" "Resources/skill-core/$p/schema.json"
done
mkdir -p "Resources/skill-core/engine"
cp "$SRC/engine/rules.md" "Resources/skill-core/engine/rules.md"
cp "$SRC/engine/highrisk.json" "Resources/skill-core/engine/highrisk.json"
python3 scripts/apple_brand.py \
  Resources/skill-core/generic/template*.md Resources/skill-core/generic/schema.json \
  Resources/skill-core/recipe/template*.md Resources/skill-core/recipe/schema.json
echo "synced skill-core assets from $SRC"
