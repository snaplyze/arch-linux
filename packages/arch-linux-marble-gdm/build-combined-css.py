#!/usr/bin/env python3

"""Build the reviewed Marble GDM stylesheet without modifying the vendor resource."""

from __future__ import annotations

import sys
from pathlib import Path


REMOVED_PROPERTIES = (
    "background-color",
    "color",
    "box-shadow",
    "border-radius",
)


def upstream_stock_transform(content: str) -> str:
    """Reproduce Marble 50.0.0's stock-CSS preparation byte for byte."""

    content = content.replace("!important", "")
    transformed = ""
    for line in content.splitlines():
        if not any(prop in line for prop in REMOVED_PROPERTIES):
            transformed += line + "\n"
        elif "}" in line and "{" not in line:
            transformed += "}\n"
    return transformed


def combine(stock_css: str, marble_css: str) -> str:
    """Match the upstream prepend/marker sequence, then append reviewed Marble CSS."""

    stock_css = upstream_stock_transform(stock_css)
    return stock_css + "\n\n/* Marble theme */\n\n\n" + marble_css


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(
            f"Usage: {argv[0]} STOCK_CSS MARBLE_CSS OUTPUT_CSS",
            file=sys.stderr,
        )
        return 2

    stock_path, marble_path, output_path = map(Path, argv[1:])
    stock_css = stock_path.read_bytes().decode("utf-8")
    marble_css = marble_path.read_bytes().decode("utf-8")
    combined = combine(stock_css, marble_css)
    with output_path.open("w", encoding="utf-8", newline="\n") as output:
        output.write(combined)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
