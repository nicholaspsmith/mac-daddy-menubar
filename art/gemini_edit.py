#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

"""Edit an image with Gemini (gemini-2.5-flash-image): image + instruction in, image out.

Usage: python3 gemini_edit.py <in.png> <out.png> "<instruction>"
The key comes from GOOGLE_GENERATIVE_AI_API_KEY or the site repo's untracked .env
(../../widgets.nicksmith.software/.env), same as art/gen_icons.py there.
"""
import base64, json, os, sys, urllib.request
from pathlib import Path

MODEL = "gemini-2.5-flash-image"
API = "https://generativelanguage.googleapis.com/v1beta"

def key() -> str:
    k = os.environ.get("GOOGLE_GENERATIVE_AI_API_KEY")
    env = Path(__file__).resolve().parents[2] / "widgets.nicksmith.software" / ".env"
    if not k and env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("GOOGLE_GENERATIVE_AI_API_KEY="):
                k = line.split("=", 1)[1].strip().strip("'\"")
    if not k:
        sys.exit("GOOGLE_GENERATIVE_AI_API_KEY is not set")
    return k

def main(src: str, dst: str, prompt: str) -> None:
    body = {"contents": [{"parts": [
                {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(Path(src).read_bytes()).decode()}},
                {"text": prompt}]}],
            "generationConfig": {"responseModalities": ["IMAGE"]}}
    req = urllib.request.Request(f"{API}/models/{MODEL}:generateContent?key={key()}",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=240) as r:
        resp = json.load(r)
    for cand in resp.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            data = part.get("inlineData", {}).get("data")
            if data:
                Path(dst).write_bytes(base64.b64decode(data))
                print("wrote", dst)
                return
    sys.exit("no image in response: " + json.dumps(resp)[:400])

if __name__ == "__main__":
    main(*sys.argv[1:4])
