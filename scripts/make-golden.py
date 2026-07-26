#!/usr/bin/env python3
"""골든 기대 출력 생성 — 코어 render.py로 Tests/Fixtures/golden/<case>/expected.md 를 만든다.
사용: python3 scripts/make-golden.py   (코어 위치는 STEPKEEPER_PATH, 기본 ../stepkeeper)
서버 /v1/documents 와 동일 파이프라인: template 프론트매터 분리 → build_context(picks={}, image_refs) → render → strip + \n
"""
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = Path(os.environ.get("STEPKEEPER_PATH", ROOT.parent / "stepkeeper")).resolve()
sys.path.insert(0, str(CORE / "src"))
from stepkeeper import render as core_render  # noqa: E402

golden_root = ROOT / "Tests" / "Fixtures" / "golden"
for case_dir in sorted(p for p in golden_root.iterdir() if p.is_dir()):
    analysis = json.loads((case_dir / "analysis.json").read_text(encoding="utf-8"))
    case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
    template = core_render.load_template(analysis["_profile"])
    body = template.split("\n---\n", 1)[1] if "\n---\n" in template else template
    with tempfile.TemporaryDirectory() as tmp:
        context = core_render.build_context(
            case["video_id"], analysis, picks={},
            source_frames=Path(tmp) / "no-frames", images_dir=Path(tmp),
            image_refs=case.get("image_refs", {}))
    markdown = core_render.render(body, context).strip() + "\n"
    (case_dir / "expected.md").write_text(markdown, encoding="utf-8")
    print(f"wrote {case_dir.name}/expected.md ({len(markdown)} chars)")
