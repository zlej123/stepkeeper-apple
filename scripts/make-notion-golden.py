#!/usr/bin/env python3
"""Notion 블록 골든 생성 — 코어 build_notion_blocks로 기대 JSON을 만든다.
사용: python3 scripts/make-notion-golden.py  (코어: STEPKIPPER_PATH, 기본 ../stepkeeper)
이미지 업로드 id는 case.json의 image_refs 키에 fake-<guide_id>를 주입한다."""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = Path(os.environ.get("STEPKIPPER_PATH", ROOT.parent / "stepkeeper")).resolve()
sys.path.insert(0, str(CORE / "src"))
from stepkeeper import export as core_export  # noqa: E402

golden_root = ROOT / "Tests" / "Fixtures" / "golden"
for case_dir in sorted(p for p in golden_root.iterdir() if p.is_dir()):
    analysis = json.loads((case_dir / "analysis.json").read_text(encoding="utf-8"))
    case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
    image_ids = {gid: f"fake-{gid}" for gid in case.get("image_refs", {})}
    blocks = core_export.build_notion_blocks(analysis, case["video_id"], image_ids)
    out = case_dir / "expected-notion.json"
    out.write_text(json.dumps(blocks, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {case_dir.name}/expected-notion.json ({len(blocks)} blocks)")
