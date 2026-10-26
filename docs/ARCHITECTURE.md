# Architecture

Godot 4.7 · GDScript · portrait 480×960 base · iOS target.

The organising principle: **story is data, engine is code, and the two only meet in one place.**
Adding an episode should never require touching GDScript. That constraint is what makes a season's
worth of branching content tractable, and it's why the layers below are separated the way they are.

```
                     data/episode1/*.json          ← writers live here
                              │
                       DialogueRuntime             ← walks the graph, knows no UI
                     ┌────────┴────────┐
              Condition          Effects           ← read/write WorldState only
                     └────────┬────────┘
                         WorldState                ← the single source of branching truth
                              │
                        SaveManager                ← versioned, migration-aware
                              │
        ┌─────────────────────┴──────────────────────┐
     PlayScene  ← the ONLY place runtime and UI meet │
        ├── Stage ──── ArtRegistry ──── assets/      │
        └── DialogueBox / ChoicePanel / QteWidget / DeductionBoard
```

## Autoloads

| Autoload | Responsibility |
| :------- | :------------- |
| `WorldState` | Flags, companion trust/loyalty/romance, known truths, heard rumours + verdicts, choice log. Every branch in the game reads from here and nowhere else. |
| `SaveManager` | Versioned save/load with `_migrate()`, frozen per-episode records, global settings. |
| `Notifier` | "X will remember that." Queues rather than stacks; dedupes per scene. |
| `AudioDirector` | Ambient bed (crossfaded), independent tension pulse, one-shot sting pool. |
| `SceneDirector` | Episode manifest, scene transitions, fades, autosave ordering. |

## The three seams that matter

**1. Runtime ↔ presentation.** `DialogueRuntime` emits `line_shown`, `choices_offered`,
`qte_requested`, `deduction_requested`, `stage_directive`, `shot_requested` — and then waits. It has
no reference to any UI class. `PlayScene` is the only script that knows both sides exist. This is
what lets the same content run in the editor, in a headless coverage harness, and on device.

**2. Content ↔ state.** Content never names a GDScript symbol. Conditions are expressions evaluated
by Godot's own `Expression` class against `WorldState` as base instance, so `trust('brother') >= 3`
in a JSON file is real, checkable code with real operator precedence — and a typo is a parse error
the validator catches offline instead of a branch that's silently always false.

**3. Content ↔ art.** Content says `"bg": "kharwyn_field"`, never a path. `ArtRegistry` is the only
file that knows about `res://assets/`. Swapping today's procedural placeholders for commissioned
art is an edit to two tables in one file.

## Save compatibility

`SAVE_VERSION` + `_migrate()` exist from day one because Episode 1 saves written today must be
readable by an Episode 3 binary shipped much later, across App Store updates. Three specific
protections:

- Unknown top-level keys in a save file are **preserved**, not dropped, so a downgrade doesn't
  destroy data written by a newer build.
- `WorldState.from_dict()` **merges** relationships rather than replacing them, so a save written
  before a companion existed loads with that companion present at defaults.
- `record_episode_complete()` freezes a snapshot per episode, so Ep2 can read Ep1's outcome even if
  the player later restarts Ep1.

## Two visual registers

Per `ART_DIRECTION.md` §4, the reference board is environment-forward with tiny silhouetted figures
and no rendered faces — which is at odds with Telltale's face-driven UX. The resolution is two
registers, both implemented in `Stage`:

- `wide` / `mid` → camera zoom on 48×96 tableau silhouettes. The board's look.
- `close` / `insert` → a **bust plate**: a purpose-drawn 220×280 chest-up portrait on its own
  CanvasLayer (so the stage camera can't drag it around), positioned by the *head* so the face lands
  on the same eyeline at any scale, with the shoulders dissolving via dithered alpha into the scene.

Zooming a 48px sprite to 2.2× would just yield eight enormous pixels, so close-ups need their own
artwork rather than a camera trick.

## Tooling

| Tool | Purpose |
| :--- | :------ |
| `src/tools/Validator.tscn` | Static check of every graph: missing `next` targets, unreachable nodes, unparseable conditions, unknown effect verbs, timed choices with no authored silence, unresolvable art/audio ids. Non-zero exit, so it works as a CI gate. |
| `src/tools/Autoplay.tscn` | 400 randomised playthroughs driving the runtime headlessly. Reports node and option coverage, exercises timeout and QTE-fail branches, and fails on any runtime error. |
| `src/tools/Capture.tscn` | Runs the real scene with a renderer and screenshots named story beats, so visuals can be reviewed without playing through. |
| `tools/gen_art.py` | Procedural placeholder art + audio in the locked palettes. Deterministic seed. |

Both harnesses drive `DialogueRuntime` directly, bypassing the UI. That's deliberate — it's a real
test of the content graph — but it means `PlayScene` defensively dismisses every UI surface when a
new line arrives, so a board resolved from outside the UI can't be left covering the screen.

## Known gaps

- **No pixel font yet.** `UiKit.FONT_PATH` is the single hook; drop a licensed TTF at
  `assets/fonts/pixel.ttf` and every text element picks it up. Until then the engine default is used
  — legible, but not on-style. Free candidates: Departure Mono (OFL), Pixel Operator (CC0).
- **Audio is synthesised, not designed.** Real sound design matters more here than usual because
  there's no voice acting.
- **Episode 1 is one scene.** The manifest in `SceneDirector.EPISODES` is where the rest go.
- **iOS export preset not created.** Needs a Mac + Xcode pass; no code blocker.
- Regenerating art requires `Godot --headless --path . --import` before the next run, or Godot
  serves the previous import cache and you review stale sprites.
