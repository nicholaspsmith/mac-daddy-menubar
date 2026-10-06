# Menu-bar art

The menu-bar icon is Menu Pimp's illustration (`source.png`) shrunk to 24x22pt (1x + @2x PNGs in
`../Resources/bundle/`), recoloured and decorated live by StatusItemKit's
`CharacterIcon.macDaddy(art:level:asleep:flourish:)`.

| File | What it is |
|---|---|
| `source.png` | The original illustration (Gemini, `gemini-2.5-flash-image`). |
| `asleep-raw.png` | Gemini edit of `source.png`: "eyes peacefully closed, change only the eyes". The model also closed the mouth, so `make_art.py` takes only the eye band from it and blends it into the original. |
| `hattip-raw3.png` | Gemini edit of `source.png`: hat lifted off his head and tipped, grey hair showing. Aligned to the base art (by the irises and medallion) so the face does not move. |
| `make_art.py` | Builds everything in `Resources/bundle/`: background cut out, one crop for all states, 1x/@2x art, and the purple-hat masks (colour segmentation, gold band and feather excluded). Prints the feature positions the code overlays use. |
| `gemini_edit.py` | The image-edit call (`gemini-2.5-flash-image`; key from the site repo's untracked `.env`). |
| `debug/` | Hat masks drawn in red over the art, for checking by eye. |

Rebuild: `python3 art/make_art.py` (needs Pillow + numpy), then `scripts/make-icon.sh` (the app
icon and `docs/mascot.png` are this same art, redrawn at icon size by the Menumon site's
`art/glyphs/hires-art.py`, which runs `make_art.py`'s steps), then `scripts/build-app.sh`.
Edits were made with:

```
python3 art/gemini_edit.py art/source.png art/asleep-raw.png "Edit this image: make the character's eyes peacefully closed (gently curved closed eyelids, like sleeping). Keep everything else exactly the same: same pose, same hat, same colours, same framing, same white background. Change only the eyes."
python3 art/gemini_edit.py art/source.png art/hattip-raw3.png "Make a new version of this image where the man lifts his hat off his head to say hello: the hat floats noticeably higher (lifted up off his head) and is tipped at an angle. No hands. Show the top of his head (short grey hair) under the raised hat. Nothing else changes: same face, same expression, same beard, same fur collar and medallion, same style, white background, and the hat and feather stay completely inside the frame."
```
