# Dialogue Graph Format

One JSON file per scene at `data/episode<N>/<scene_id>.json`. **Story is data, not code** — adding
an episode is writing JSON, never touching GDScript. Run the validator after every edit:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script src/tools/validate_data.gd
```

## Top level

```json
{
  "id": "s01_the_tremor",
  "title": "The Tremor",
  "entry": "wake_01",
  "stage": { "bg": "kharwyn_field", "palette": "ASHFALL", "bed": "battlefield" },
  "on_enter": [ { "flag": "ep1_started" } ],
  "on_exit":  [ { "flag": "s01_done" } ],
  "nodes": { "wake_01": { ... } }
}
```

`stage` / `on_enter` fire before the first node; `on_exit` fires when the graph ends.

## Fields available on every node

| Field | Purpose |
| :---- | :------ |
| `type` | `line` (default), `choice`, `qte`, `deduction`, `branch`, `jump`, `end` |
| `effects` | Effect list applied **on entering** the node |
| `stage` | Stage directive (backdrop / palette / who's on screen / camera shake) |
| `shot` | Camera framing for this beat |
| `next` | Where to go — node id string, or inline branch array |

### `next` — inline branching

```json
"next": [
  { "if": "trust('brother') >= 3", "to": "he_opens_up" },
  { "if": "has_flag('drew_sword')", "to": "he_flinches" },
  { "to": "default_beat" }
]
```
Evaluated top to bottom, first match wins. Last entry should be unconditional. `"next": "id"` is
the shorthand for the single-target case. Omitting `next` (or `"END"`) ends the scene.

## Node types

### `line`
```json
{ "type": "line", "speaker": "medic", "text": "Don't touch him.",
  "shot": { "framing": "close", "focus": "medic" }, "next": "reply_01" }
```
`speaker` is a companion key, `"protagonist"`, or `"narrator"` (renders italic, no name plate).
Optional `"tone": "whisper" | "shout" | "strained"` adjusts typewriter speed and shake.

### `choice`
```json
{ "type": "choice", "prompt": "He's waiting for you to say something.",
  "timer": 7.0, "default": "say_nothing",
  "options": [
    { "id": "reassure", "text": "\"You're still my brother.\"", "tone": "warm",
      "effects": [ { "adjust": "brother", "stat": "trust", "by": 2 } ],
      "remember": "brother", "next": "he_breathes" },
    { "id": "recoil", "text": "\"Stay back.\"", "tone": "cold",
      "effects": [ { "adjust": "brother", "stat": "trust", "by": -3 },
                   { "flag": "feared_the_brother" } ],
      "remember": "brother", "next": "he_steps_away" },
    { "id": "ask_medic", "text": "[Look at Harrow]", "if": "has_met('medic')",
      "locked_text": "[Look at Harrow]", "next": "harrow_shakes_head" },
    { "id": "say_nothing", "text": "Say nothing.", "next": "silence_hangs" }
  ]
}
```
- `timer` — seconds. Omit for untimed. Overridden off by the `timed_choices` accessibility setting.
- `default` — option id auto-picked on timeout. Without it, timeout uses `on_timeout` /
  `timeout_effects` and logs `[said nothing]`. **Always author one or the other** — silence must be
  a position, not a bug.
- `if` — gate. If it fails and `locked_text` is present the option shows greyed out, so the player
  can see the door they didn't have the key for.
- `remember` — fires the "X will remember that" toast.
- `tone` — `warm` / `cold` / `neutral` / `curious` / `violent`. Tints the option's left edge only;
  it does **not** label the choice morally.

### `qte`
```json
{ "type": "qte", "kind": "rapid_tap", "duration": 3.2, "target": 14,
  "caption": "GET UP", "shot": { "framing": "close", "focus": "protagonist" },
  "success": "you_stand", "fail": "it_reaches_you",
  "success_effects": [], "fail_effects": [ { "flag": "wounded_leg" } ] }
```
`kind`: `tap` (single, `target` ignored) · `rapid_tap` (`target` taps before `duration`) ·
`hold` (hold for `duration`) · `swipe` (with `"direction": "left"|"right"|"up"|"down"`).

**Failing a QTE never kills the player in Episode 1** — it costs state (a wound flag, a
relationship hit, a worse branch). Death-on-fail belongs to a later episode where the player
understands the verbs.

### `deduction` — the game's only puzzle type
```json
{ "type": "deduction",
  "question": "Who was in the tunnel when it opened?",
  "statements": [
    { "who": "medic", "text": "Vaethari sappers. I pulled two of them out myself." },
    { "who": "enemy_soldier", "text": "Our sappers never reached the undercroft." },
    { "who": "scavenger", "text": "Somebody was down there a week before the siege." }
  ],
  "options": [
    { "id": "d_vaethari", "text": "Vaethari sappers broke the seal.",
      "effects": [ { "resolve": "vaethari_broke_seal", "verdict": "verified" } ], "next": "..." },
    { "id": "d_earlier", "text": "Someone was down there before the siege began.",
      "effects": [ { "learn": "someone_was_there_first" },
                   { "remember_text": "You have started keeping your own counsel." } ],
      "next": "..." }
  ]
}
```
The board shows the conflicting statements the player has actually heard, then asks them to
commit. **No option is marked correct in the data.** Whether a conclusion was right is revealed
later in story, which is the entire point of the "nobody knows what's true" premise. Record the
player's belief with `resolve` / `learn` and pay it off in a later scene.

### `branch` / `jump`
Silent routing nodes with no presentation. `branch` is conventionally used with an inline `next`
array, `jump` with a single target.

### `end`
Ends the scene; `SceneDirector` advances to the next scene in the episode manifest.

## Stage directives

```json
"stage": {
  "bg": "kharwyn_field",
  "palette": "ASHFALL",
  "cast": ["protagonist", "brother"],
  "enter": [ { "who": "medic", "at": "right" } ],
  "exit": ["scavenger"],
  "bed": "battlefield",
  "pulse": "dread", "intensity": 0.4,
  "shake": 0.5,
  "glow": "brother"
}
```
`bg` and `palette` resolve through `src/stage/art_registry.gd` — never a raw path. `glow` applies
the magic-override colour from art direction §2 to a character.

## Shots

`{"framing": "wide"|"mid"|"close"|"insert", "focus": "<cast key>", "hold": 0.4}` — see art
direction §4 for what each register is *for*.

## Effects reference

| Effect | Meaning |
| :----- | :------ |
| `{"flag": "k"}` / `{"flag": "k", "value": "north"}` | Set a story flag |
| `{"unflag": "k"}` | Set false |
| `{"bump": "k", "by": 1}` | Increment a counter flag |
| `{"adjust": "brother", "stat": "trust", "by": -2}` | Relationship delta (clamped ±10) |
| `{"learn": "id"}` | Player now knows something is true |
| `{"rumor": "id", "source": "scavenger"}` | Player heard a claim (verdict `unknown`) |
| `{"resolve": "id", "verdict": "verified"}` | Player commits to believing / disbelieving it |
| `{"meet": "medic"}` | Marks a companion introduced |
| `{"remember": "brother"}` | "Cael will remember that." |
| `{"remember_text": "..."}` | Custom consequence toast |
| `{"sting": "magic"}` / `{"bed": "cave"}` / `{"pulse": "dread", "intensity": 0.6}` | Audio |

Any effect may carry `"if"` to fire conditionally.

## Conditions

GDScript expressions with `WorldState` as base instance. Anything public on it is callable:

```
has_flag('drew_sword')          flag('route') == 'north'
trust('brother') >= 3           loyalty('medic') < 0        romance('scavenger') > 4
knows('someone_was_there_first')  heard('the_hold_still_burns')
believes('vaethari_broke_seal')   rumor_verdict('x') == 'refuted'
deductions_made() >= 2            has_met('prophet')        chose('recoil')
completed('s01_the_tremor')
```
Combine with `and` / `or` / `not` / parentheses.
