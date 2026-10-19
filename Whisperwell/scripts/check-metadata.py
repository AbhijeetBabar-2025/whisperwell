#!/usr/bin/env python3
"""Checks AppStore/metadata.md fields against App Store Connect character limits."""
import re
import sys
from pathlib import Path

text = (Path(__file__).resolve().parent.parent / "AppStore" / "metadata.md").read_text()


def table_value(label):
    m = re.search(r"^\| " + re.escape(label) + r" \| (.+?) \|$", text, re.M)
    return m.group(1).strip() if m else None


def section(title):
    m = re.search(r"^## " + re.escape(title) + r"[^\n]*\n\n(.*?)(?=\n## |\Z)", text, re.M | re.S)
    return m.group(1).strip() if m else None


checks = [
    ("Name", table_value("Name (≤30)"), 30),
    ("Subtitle", table_value("Subtitle (≤30)"), 30),
    ("Promotional text", section("Promotional text"), 170),
    ("Keywords", section("Keywords"), 100),
    ("Description", section("Description"), 4000),
]
failed = False
for name, value, limit in checks:
    if value is None:
        print(f"MISSING  {name}")
        failed = True
        continue
    ok = len(value) <= limit
    failed |= not ok
    print(f"{'ok     ' if ok else 'TOO LONG'} {name}: {len(value)}/{limit}")

keywords = section("Keywords") or ""
if ", " in keywords:
    print("WARNING  Keywords: remove spaces after commas; they count against the limit")
sys.exit(1 if failed else 0)
