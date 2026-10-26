# The Devouring — Art Direction (LOCKED)

Derived from Ian's `pinterest.com/RoyzFilmz/pixel-fantasy` board, read 2026-07-26.
This document is the authority. If a sprite disagrees with this file, the sprite is wrong.

---

## 1. What the board actually is

Reading ~60 pins, the board is not "generic dark fantasy pixel art." It is a very specific and
very consistent thing, and the consistency is the useful part:

| Trait | Observation | Rule it becomes |
| :---- | :---------- | :-------------- |
| **Aspect** | Essentially every pin is *vertical* (phone-wallpaper shaped) | **The game is portrait.** Not landscape Telltale. Locked. |
| **Figure scale** | The character is tiny — 5–15% of frame height — and almost always seen from behind or in pure silhouette | Environment is the protagonist. Figures are shadows in it. |
| **Light** | Exactly **one** dominant source per frame: torch, bonfire, moon, lava, god-ray, glowing rune | One light per shot. Never two co-equal sources. |
| **Colour logic** | Cold desaturated ambient + a single saturated accent (ember orange, cyan, blood red, violet) | Palette = cold field + one hot note. |
| **Depth** | 5–7 stacked silhouette planes, each lighter + more desaturated toward horizon, fog band between | Parallax stage with atmospheric perspective baked into the art. |
| **Texture** | Heavy visible **ordered dithering** in every sky and fog gradient | Bayer dither, never smooth gradients, never blur. |
| **Resolution** | Mid-to-high density pixel art (Octopath/Owlboy register), *not* chunky 8-bit | Base canvas 480×960. 1 art pixel = 1 game pixel. |
| **Architecture** | Pointed gothic arches, spires, colonnades, ruined stone, graveyard crosses | Gothic vocabulary only. No high-fantasy gold-and-banners. |
| **Recurring motifs** | Planted sword, bodies hanging from a bridge, field of grave-crosses, arched window onto a moon, lone bonfire, huge armoured thing looming over a small knight in rain | Reuse these as **staging language**, they're the board's grammar. |

**The single most important read:** on this board, people are never the subject and faces are
never rendered. That is a real tension with Telltale-style close-ups, and §4 resolves it
deliberately rather than by accident.

---

## 2. Palettes

Six mood families. **Each scene commits to exactly one** — the board never blends two.
Colours are ordered dark→light; the last entry of each is the accent/light source.

### ASHFALL — Kharwyn aftermath, burning, war
The crimson-sky / black-silhouette pins (graveyard field, lava river, red castle).
```
#0d0810  #1a1018  #3a0d14  #7a1520  #b8322e  #d9553a   accent: #ff9a3c  #ffd98a
```
Use for: the Rupture site, the field of dead, anything still burning.

### DROWNED — the Rupture scar, caves, underground water
The indigo cave-waterfall and blue-tower pins.
```
#070b1a  #0e1730  #1b2a52  #2d4a86  #4a7fc4  #7fa9dd   accent: #5fe0e8  #b6f5f2
```
Use for: below Kharwyn, flooded tunnels, anywhere magic is *cold*.

### VIOLET — dusk travel, the wrong kind of beautiful
The magenta-sky castle and purple mountain pins. The board's prettiest register — use it when
the world looks gorgeous and is about to hurt you.
```
#140a1f  #26123a  #3f1d5c  #6b2f86  #a34a9e  #d97ab5   accent: #f2d7ff
```
Use for: roads between locations, the Prophet's scenes, false calm.

### BOGSHADE — superstition, fog, the Old Faith
The olive/sage wraith-in-the-woods pins. Muted, sickly, low contrast.
```
#101410  #1b241c  #2e3d2e  #47593f  #6b7d55  #96a37c   accent: #c6cfa8
```
Use for: rumour and folk-tale scenes, the Prophet's sermons, anything where the player is
being lied to.

### CRYPT — monsters, terror, the unknown
The greyscale spider-dungeon and dragon-tower pins. **Near-zero saturation** except the torch.
```
#060608  #121216  #22222a  #3a3a44  #5c5c68  #8a8a96   accent: #ffb45c
```
Use for: first monster reveals. Draining the colour out is the tell that something is wrong.

### SNOWLIGHT — cold aftermath, the swords-in-snow pin
```
#0b0f18  #182231  #2c3a4d  #4d5f75  #8397ab  #cdd8e2   accent: #e8f2ff
```
Use for: later-episode winter, mass graves, exhaustion.

**Magic override.** Marked characters emit light that does **not** belong to the scene palette.
When the Brother uses his ability, his glow is `#5fe0e8 → #b6f5f2` (DROWNED accent) regardless
of the active palette. That clash is intentional and is the visual thesis of the game: magic
does not match the world it landed in.

---

## 3. Rendering rules

- **Dither, don't blend.** All sky/fog gradients use a 4×4 Bayer matrix between two adjacent
  palette entries. No alpha gradients, no blur, no soft shadows.
- **Nearest-neighbour filtering, integer scaling.** Already set in `project.godot`.
- **Max ~24 colours on screen** per scene (palette + accent + magic override).
- **Rim light, not fill light.** Figures get a 1–2px accent-coloured edge on the side facing
  the light source and are otherwise near-black. This is how every pin on the board handles
  characters and it is *much* cheaper to produce than fully-lit sprites.
- **Fog bands.** Between each parallax plane, a horizontal band of the next-lighter palette
  entry at ~35% dither density. This single trick is what makes the board's pieces read as deep.
- **No outlines.** The board has no black keylines around figures — separation comes from
  value contrast against the plane behind.
- **No pure black, no pure white.** Darkest is the palette's first entry; brightest is its accent.

---

## 4. The close-up problem, and the answer

Telltale's whole UX is faces. This board has no faces. Resolving this by just drawing
detailed portraits would throw away the reference. So: **two registers, used deliberately.**

### Register A — TABLEAU (the board's look; ~70% of shots)
Wide. Full environment. Figure at 8–15% of frame height, rim-lit, seen from behind or in
profile silhouette. Used for establishing shots, travel, dread, monster reveals, and any
line where the *world* is speaking louder than the character.

### Register B — PLATE (close dialogue; ~30% of shots)
Push in to a **bust silhouette**, chest-up, still rim-lit, still mostly black. The face is
rendered at only ~6–10 pixels of feature detail: eyes as 1–2px high-contrast marks, a jaw
edge, a mouth line. Environment palette washes across the background as flat dithered bands.

This keeps the board's "people are shadows" logic while giving the player something to read
emotionally. It also means **a character's whole expressive range is a handful of pixels** —
which is a production gift, not a limitation. Swapping 4 pixels changes a performance.

**Shot vocabulary** (these are the literal values the dialogue JSON accepts):

| `shot.framing` | Zoom | Use |
| :------------- | :--- | :-- |
| `wide` | 1.0 | Establishing, tableau, environment as subject |
| `mid` | 1.4 | Two-character staging, walk-and-talk |
| `close` | 2.2 | Register B plate — emotional beats, lies, revelations |
| `insert` | 3.0 | An object: a wound, a relic, a hand starting to glow |

---

## 5. Character presence spec

Sprite canvases, at 480×960 base resolution:

| Slot | Canvas | Notes |
| :--- | :----- | :---- |
| Full figure (tableau) | 48×96 | Rim-lit silhouette. Read at 8–15% frame height. |
| Bust plate (close) | 220×280 | Chest-up. Minimal facial pixels per §4. |
| Insert prop | 120×120 | Hands, relics, wounds. |

Per-character silhouette must be identifiable **as a shape alone**, since that's all the
player usually gets:

- **Protagonist** — Aldrethi infantry: rounded kettle helm, cloak torn at hem, sword low.
- **The Brother** — no helm, hunched, *the only silhouette that emits light*.
- **The Medic** — satchel bulk on one hip breaks his outline asymmetrically; no weapon.
- **The Enemy Soldier** — Vaethari: angular faceted helm, straight-shouldered, industrial.
- **The Prophet** — tallest, robed to the ground, hood, no visible arms. Reads as a column.
- **The Scavenger** — smallest, laden with hanging junk that jitters when she moves.

---

## 6. Pipeline (per brief §13)

1. All art is loaded through `res://assets/` by **path constants in `art_registry.gd`** — never
   hardcoded in scenes. Swapping in commissioned art is a registry edit, not a refactor.
2. Current placeholders are **procedurally generated** by `tools/gen_art.py` (PIL) directly in
   these palettes with real Bayer dithering. This means the game looks intentional today with
   **zero third-party licensing exposure** — relevant since episodes 2+ are sold.
3. If an itch.io pack is ever introduced, its licence must be recorded in `assets/LICENSES.md`
   before a single sprite ships. Not after.

---

## 7. Explicit do-not list

- ❌ Smooth gradients, glows, blur, bloom, alpha-faded shadows
- ❌ Fully-lit character sprites with rendered faces at tableau scale
- ❌ Two competing light sources in one frame
- ❌ Saturated greens or golds as ambient (reads high-fantasy, kills grimdark)
- ❌ Black keyline outlines around figures
- ❌ Landscape framing
- ❌ Chunky 8-bit / NES-scale pixels
- ❌ UI that covers more than the bottom 40% of the screen
