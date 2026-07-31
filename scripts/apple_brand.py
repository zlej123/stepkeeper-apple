#!/usr/bin/env python3
"""Apple 클라이언트가 외부 stepkeeper 코어 자산을 stepkipper 브랜드로 표시하게 한다."""

from pathlib import Path
import sys


REPLACEMENTS = (
    ("kept with stepkeeper", "kept with stepkipper"),
    ("stepkeeper로 생성", "stepkipper로 생성"),
    ("stepkeeper で作成", "stepkipper で作成"),
    ("stepkeeper generic analysis result", "stepkipper generic analysis result"),
    ("stepkeeper recipe analysis result", "stepkipper recipe analysis result"),
)


def apply_brand(text: str) -> str:
    for source, replacement in REPLACEMENTS:
        text = text.replace(source, replacement)
    return text


def rewrite(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    branded = apply_brand(text)
    if branded != text:
        path.write_text(branded, encoding="utf-8")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        rewrite(Path(argument))
