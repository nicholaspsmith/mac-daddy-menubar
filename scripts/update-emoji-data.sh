#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nicholas Smith
# Regenerate Resources/bundle/emoji.json from Unicode's emoji-test.txt and CLDR's
# English annotations. Re-run (bumping the pins) when Unicode ships a new version.
set -euo pipefail
cd "$(dirname "$0")/.."
EMOJI_VERSION="${EMOJI_VERSION:-16.0}"
CLDR_TAG="${CLDR_TAG:-release-46}"
python3 - "$EMOJI_VERSION" "$CLDR_TAG" <<'PY'
import json, re, sys, urllib.request, xml.etree.ElementTree as ET
emoji_version, cldr = sys.argv[1], sys.argv[2]
TEST = f"https://unicode.org/Public/emoji/{emoji_version}/emoji-test.txt"
CLDR = f"https://raw.githubusercontent.com/unicode-org/cldr/{cldr}/common"
TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]

def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()

names, keywords = {}, {}
for path in ("annotations/en.xml", "annotationsDerived/en.xml"):
    for a in ET.fromstring(fetch(f"{CLDR}/{path}")).iter("annotation"):
        cp = a.get("cp").replace("️", "")
        text = (a.text or "").strip()
        if a.get("type") == "tts":
            names[cp] = text
        else:
            keywords[cp] = [k.strip() for k in text.split("|") if k.strip()]

line_re = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E[\d.]+\s+(.+)$")
emoji, index, group = [], {}, None
for line in fetch(TEST).decode("utf-8").splitlines():
    if line.startswith("# group:"):
        group = line.split(":", 1)[1].strip()
        continue
    m = line_re.match(line)
    if not m or group == "Component":
        continue
    cps = [int(x, 16) for x in m.group(1).split()]
    char = "".join(map(chr, cps))
    tones = [c for c in cps if c in TONES]
    if tones:
        base = "".join(chr(c) for c in cps if c not in TONES)
        i = index.get(base, index.get(base.replace("️", "")))
        if i is not None and len(set(tones)) == 1:
            emoji[i].setdefault("t", [None] * 5)[TONES.index(tones[0])] = char
        continue
    key = char.replace("️", "")
    index[char] = index[key] = len(emoji)
    emoji.append({"c": char, "n": names.get(key, m.group(2)), "k": keywords.get(key, []), "g": group})

for e in emoji:
    if "t" in e and None in e["t"]:
        del e["t"]

with open("Resources/bundle/emoji.json", "w", encoding="utf-8") as f:
    json.dump(emoji, f, ensure_ascii=False, separators=(",", ":"))
print(f"wrote {len(emoji)} emoji ({sum('t' in e for e in emoji)} with skin tones)")
PY
