# The Devouring — Project Rules

Dark fantasy, Telltale-style narrative adventure. Godot 4.7 → iOS. Portrait.
Episodic: Ep1 free, Ep2+ paid (~$3.99–4.99), season bundle at 3+ episodes.

**Read `docs/ART_DIRECTION.md` before touching any visual.** It is locked and derived from
Ian's actual reference board. Read `docs/GAME_BRIEF.md` for the original design brief and
`docs/ARCHITECTURE.md` for how the systems fit together.

## Hard constraints

- **Portrait only.** 480×960 base viewport, `canvas_items` stretch, `expand` aspect.
- **Pixel art discipline:** nearest filtering, Bayer dithering, no blur/bloom/gradients.
- **One light source per shot.** Cold ambient + one hot accent. See art direction §3.
- **No voice acting.** Text only. Ambient beds and stings carry all atmosphere.
- **No inventory puzzles.** Puzzles are conversational deduction only (brief §5.3).
- **Art is never hardcoded.** All asset paths go through `src/stage/art_registry.gd`.
- **Never break save compatibility.** `SaveManager.SAVE_VERSION` exists so Ep1 choices stay
  readable by Ep2+. If you change the save shape, write a migration in `_migrate()`. Do not
  silently drop fields.

## Writing register

Game of Thrones-adjacent: political, morally grey, no winking. Specifically:

- **Nobody in-world knows what magic is.** No character may explain magic correctly. Every
  explanation offered is a guess, a doctrine, or a lie. The player cannot look up the truth.
- Conflicting accounts of the same event are a feature. Track them as `rumors`, not facts.
- The protagonist is a **blank slate** — never write him a personality. He asks, reacts, and
  chooses. His characterisation is whatever the player picked. No jokes, no swagger, no
  hard-coded moral stance in his lines.
- Lore terms are fixed: the Rupture, Tremors, the Marked, Kharwyn Hold, Aldreth, the Vaeth
  Dominion (Vaethari), the Old Faith, the Devouring, the Awakening.

## Content authoring

Episode content is **data, not code**. Scenes live in `data/episode1/*.json` as node graphs.
Adding story = writing JSON. See `docs/DIALOGUE_FORMAT.md` for the schema. Conditions are
GDScript expressions evaluated against `WorldState` (e.g. `trust("brother") >= 3 and not has_flag("told_medic")`).

## Validation

```bash
GODOT=~/Downloads/Godot.app/Contents/MacOS/Godot   # move to /Applications when convenient

# 1. Static graph check — missing `next` targets, unreachable nodes, unparseable conditions,
#    unknown effect verbs, timed choices with no authored silence. Exits non-zero on failure.
"$GODOT" --headless --path . res://src/tools/Validator.tscn

# 2. 400 randomised playthroughs. Reports node/option coverage and fails on any runtime error.
"$GODOT" --headless --path . res://src/tools/Autoplay.tscn

# 3. Screenshot named story beats (needs a display) -> user://captures
"$GODOT" --path . res://src/tools/Capture.tscn

# Play it:
"$GODOT" --path .
```

Run the validator **and** autoplay after every content edit. A typo'd `next` target is otherwise a
dead-end the player discovers instead of you.

Note: the harnesses must run as **scenes**, not `--script`. `--script` starts a bare SceneTree with
no autoloads, so every script that references `WorldState` fails to compile.

## iOS

```bash
tools/build_ios.sh archive    # Xcode project + unsigned arm64 archive (works today)
tools/build_ios.sh ipa        # signed .ipa — needs an Apple ID in Xcode → Settings → Accounts
```

**Read `docs/IOS_BUILD.md` before changing `export_presets.cfg` or any iOS setting.** Non-negotiables
that are easy to break by accident:

- `rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot` — without it iOS
  export fails with a **blank** error message. Never remove it.
- `custom_template/debug=""` / `custom_template/release=""` must stay present-and-empty. Deleting
  the keys makes Godot read nil as "a custom template was specified".
- Never set the export path inside the project directory.
- The iOS Simulator cannot run this on Apple Silicon — upstream Godot's simulator library is
  x86_64-only. Test on a device.

## Regenerating placeholder art

```bash
python3 tools/gen_art.py                        # assets/bg, assets/char, assets/audio
"$GODOT" --headless --path . --import           # REQUIRED — otherwise Godot serves the stale
                                                # import cache and you review the old sprites
```

## GDScript gotchas already paid for once

- **`set_anchors_preset()` keeps existing offsets.** On a fresh Control those are all zero, so the
  node stays 0×0 and only its content minimum renders. Use
  `set_anchors_and_offsets_preset()`.
- **`PRESET_BOTTOM_WIDE` grows *downward* off-screen.** A bottom-anchored panel that hugs its content
  also needs `grow_vertical = Control.GROW_DIRECTION_BEGIN`.
- **A shrink-to-fit Label must have `autowrap_mode = AUTOWRAP_OFF`.** A wrapping label reports a
  one-character minimum width, which renders a speaker name as a vertical column of letters.
- **Don't mix anchor presets with manually-set `size`.** The preset recomputes offsets on the next
  layout pass and discards the size. Use explicit positions against the fixed 480×960 base instead.
- **`var x := (a and b) or c` fails to infer a type** when the operands are Variant comparisons.
  Annotate: `var x: bool = ...`.

## Session hygiene

Work on this game from `~/Developer/TheDevouring` so this file loads. Never from `~/`.
