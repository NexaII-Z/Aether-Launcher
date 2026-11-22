#!/usr/bin/env python3
"""Cheap sanity checks that run anywhere (no Xcode needed)."""
import json
import re
import struct
import sys
from pathlib import Path

import yaml

root = Path(__file__).resolve().parent.parent
errors = []

spec = yaml.safe_load((root / "project.yml").read_text())
if spec.get("targets", {}).get("AETHERLauncher", {}).get("type") != "application":
    errors.append("project.yml: AETHERLauncher application target missing")

for path in (root / "Resources").rglob("Contents.json"):
    try:
        json.loads(path.read_text())
    except ValueError as exc:
        errors.append(f"{path.relative_to(root)}: invalid JSON ({exc})")

icon = root / "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
if not icon.exists():
    errors.append("App icon missing")
else:
    header = icon.read_bytes()[:24]
    width, height = struct.unpack(">II", header[16:24])
    if (width, height) != (1024, 1024):
        errors.append(f"App icon is {width}x{height}, expected 1024x1024")

sources = list((root / "Sources").rglob("*.swift"))
if not sources:
    errors.append("No Swift sources found")
for path in sources:
    text = re.sub(r'"(\\.|[^"\\])*"', '""', path.read_text())
    if text.count("{") != text.count("}") or text.count("(") != text.count(")"):
        errors.append(f"{path.relative_to(root)}: unbalanced braces or parentheses")

if errors:
    print("Preflight failed:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)
print(f"Preflight OK ({len(sources)} Swift files)")
