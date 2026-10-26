# \[WORKING TITLE\] — Dark Fantasy Telltale-Style iOS Narrative Game

### Game Design & Technical Brief for Claude Code (Godot Engine)

---

## 1\. Concept Pitch

A Telltale-style narrative adventure set in the exact moment magic is discovered in the world — igniting a brutal war between two empires, unleashing monstrous creatures never seen before, and throwing every rumor, superstition, and folk tale into question because *no one actually knows what's true yet*. Grimdark tone, Game of Thrones-level political depth and betrayal, told through a displaced soldier's eyes as he tries to survive, find his brother, and figure out who's really pulling the strings behind the collapse of his world.

**Genre:** Narrative choice-driven adventure (Telltale/Until Dawn style) **Platform:** iOS **Engine:** Godot (chosen for text-based scene/script files that are easy for an AI coding agent to read/write directly — no heavy GUI-only workflow like Unity) **Development approach:** Fully coded via Claude Code (Opus) **Art style:** Pixel art, dark fantasy (reference: [https://www.pinterest.com/RoyzFilmz/pixel-fantasy/](https://www.pinterest.com/RoyzFilmz/pixel-fantasy/)) **Audio:** Text-only dialogue, no voice acting — ambient sound design and score carry the atmosphere **Structure:** Episodic (Episode 1, 2, 3... like Telltale seasons) **Episode length target:** Short, 20–30 minutes per episode **Monetization:** Episode 1 free (acts as the hook/demo — critical for an unknown indie title with no marketing budget). Episodes 2+ sold individually (\~$3.99–4.99 each), with a discounted season-pass bundle option once 3+ episodes exist.

---

## 2\. World & Premise

**The setting:** This is the era magic was *discovered*, not an established magical world. It's raw, new, and destabilizing.

**The Rupture.** For a generation, two powers had been grinding against each other over a contested mountain fortress called **Kharwyn Hold** — the last chokepoint between their territories. **Aldreth**, the older of the two realms, holds the Hold by ancestral right and treats magic (on the rare occasion anyone spoke of it at all) as heresy — the Old Faith calls it "the Devouring." **The Vaeth Dominion**, younger, industrial, expansionist, has spent a generation annexing border territory and finally moved to take the Hold by siege.

To break Aldreth's walls, Vaethari combat engineers tunneled *under* the fortress — and broke into something that had been sealed beneath it since before either kingdom existed. Whatever it was tore open in an instant, killing thousands on both sides in the same breath, and the war both sides had been fighting stopped mattering. This event is now called **the Rupture**, and it is **not over**. Aftershocks — called **Tremors** — continue to ripple outward unpredictably, months later, still spawning monsters and occasionally leaving a handful of survivors changed, or "**Marked**": sudden, uncontrolled magical ability with no instruction manual and no guarantee it won't kill them. Nobody — not scholars, not priests, not the two crowns — knows what caused it, whether it's finished, or whether it's going to happen again somewhere else entirely.

- Because of the Rupture, **Aldreth and the Vaeth Dominion are still at war** — old grievances haven't gone anywhere, and now both sides are also scrambling to figure out whether magic is a weapon to seize or a plague to contain, before the other side decides for them.  
- **Monsters are emerging for the first time** as a side effect of the Tremors — nobody has faced these creatures before, so there's no established lore, bestiary, or strategy for dealing with them.  
- **Nobody understands magic yet.** People are trying to learn how to harness it in real time. This creates a world thick with **whispers, rumors, and folk tales** — some true, some completely fabricated — and critically, *no one in-world can reliably tell which is which*. The player included. Things must be discovered firsthand rather than taken from established lore.  
- Tone target: **Game of Thrones-level writing** — political depth, morally gray factions, betrayal, plot twists that recontextualize earlier events. Grimdark, not high fantasy.

**Design implication:** This "nobody knows what's real yet" premise is a strong mechanical hook — it justifies unreliable narrators, conflicting NPC accounts of the same event, and rumors that the player can choose to believe/act on that turn out true or false. Lean into this hard in dialogue writing.

---

## 3\. Protagonist

- **21-year-old male soldier**, fighting for **Aldreth** at Kharwyn Hold when the Rupture hit and **displaced him** — separated from his unit, his command structure, and cut off from any clear way back to Aldrethi lines. Having grown up under the Old Faith's teaching that magic is "the Devouring," his own instincts about what just happened to the world are going to be in direct conflict with what he's about to see — and with what's about to happen to his brother.  
- **Blank-slate avatar** — his personality, values, and moral alignment are shaped entirely by player choices going forward. No pre-defined personality traits should be hard-coded into his dialogue delivery; his characterization emerges from what the player picks.  
- Starting state for Episode 1: disoriented, cut off from his unit, in hostile/unfamiliar territory in the immediate aftermath of the cataclysm.

---

## 4\. Companions (Episode 1\)

### Core companion — required

**The Brother** — 19 years old, **Marked** by the Rupture: he manifested magic abilities in the same Tremor that displaced the protagonist. This is the central relationship of the game and the primary emotional anchor. His new abilities should be a source of both hope (a way to survive/fight back) and fear/tension (nobody trusts magic yet, least of all Aldrethi soldiers raised on the Old Faith). His arc likely has major long-term consequences based on how the player treats him — including whether the protagonist himself comes to see his own brother as something to protect or something to fear.

### Additional Episode 1 companions

- **The Medic** — a battle-hardened Aldrethi field medic traveling with the group who **distrusts magic on principle**, having only seen the Rupture cause mass death firsthand. Good source of friction with the Brother and the loudest voice for "magic is a plague, not a gift."  
- **The Enemy Soldier** — a **Vaethari** soldier, stranded on the wrong side of the lines by the same Tremor, thrown into an uneasy forced alliance with the protagonist's group. Vaethari doctrine treats magic as an opportunity to seize rather than a heresy to fear — a direct ideological foil to the Medic, and a live wire given the two kingdoms are still, technically, at war.  
- **The Prophet** — a wandering Old Faith preacher who calls the Rupture "the Awakening," not a catastrophe. She speaks in scripture and omens, seems to know more about what happened at Kharwyn Hold than a random traveler should, and may be far more deliberately positioned in these events than she first appears. Slow-burn mystery/manipulation angle — seed her lightly in Episode 1, pay it off later.  
- **The Scavenger** — a border-region local who was quietly trading in Kharwyn relics and Rupture rumors even before the world found out what happened. Self-interested, morally gray, knows the terrain and the folk tales better than anyone — a natural vehicle for the dialogue-deduction mechanic, since half of what she says is probably true and she isn't telling you which half.

*(Not all five need equal screen time in Episode 1 — the Brother, Medic, and Enemy Soldier can anchor the episode, with the Prophet and Scavenger introduced more lightly as hooks for Episode 2+.)*

All companions should have **trackable relationship stats** (trust/loyalty, and romance where applicable) that influence dialogue options, scene availability, and branching outcomes later in the story.

---

## 5\. Core Gameplay Loop

Full Telltale-style package:

1. **Scene exploration** — limited-movement environments, examine objects/points of interest, walk-and-talk segments.  
2. **Dialogue trees** — branching conversations with timed or untimed choices depending on scene tension.  
3. **Dialogue-based deduction puzzles** — the primary puzzle type. Player must piece together truth from conflicting NPC statements, rumors, and folk tales (ties directly into the "nobody knows what's real yet" world premise). No inventory/item-combination puzzles — keep puzzle-solving conversational and inference-based.  
4. **Quick-time events (QTEs)** — for action/combat/danger beats (escapes, monster encounters, physical confrontations).  
5. **Choice & consequence checkpoints** — decisions that visibly matter, both immediate and long-term.

### "X will remember that" system

Player-facing prompts confirming when a choice has been flagged as consequential (Telltale's signature UX). Needs a clear, lightweight on-screen notification system.

---

## 6\. Choice & Consequence Depth

- **Deep branching** — meaningfully different scenes and story paths, not just cosmetic dialogue swaps. Choices should be able to lock/unlock entire scenes, alter which companions are present, and change how later episodes open.  
- **Multiple distinct endings** for the season, driven by accumulated choices (not a single late-game "pick an ending" screen — should emerge from the whole playthrough).  
- Relationship stats (trust/loyalty/romance) with companions should feed into which branches are available and how the ending(s) resolve.

**Technical implication:** Needs a robust state-tracking system from day one — a central "world state" object tracking flags (booleans/enums for major decisions), companion relationship values (numeric), and discovered-truths/rumors (to support the deduction mechanic). This should be architected before writing Episode 1 content so it scales across future episodes.

---

## 7\. Structure & Scope

- **Episodic**, Telltale-season format: Episode 1, 2, 3, etc.  
- Episode 1 target playtime: **20–30 minutes**.  
- Episode 1 should function as a complete narrative unit (clear opening, rising tension, a major choice or twist, a cliffhanger/hook into Episode 2\) while establishing the state-tracking systems that later episodes will build on.

---

## 8\. Visual Art Direction

- **Pixel art**, dark fantasy aesthetic.  
- Reference board: [https://www.pinterest.com/RoyzFilmz/pixel-fantasy/](https://www.pinterest.com/RoyzFilmz/pixel-fantasy/) (could not be auto-analyzed — pull specific reference images manually if particular pieces should inform character/environment design).  
- Should support Telltale-style "camera framing" even in 2D pixel form — close-ups on faces during key dialogue beats, wider shots for environment/establishing scenes.

---

## 9\. Audio Direction

- **No voice acting.** Text-only dialogue.  
- Ambient sound design and a moody score should carry atmosphere and tension — invest weight here since voice acting is off the table.

---

## 10\. Technical Notes for Claude Code

- **Engine:** Godot (GDScript), targeting iOS export.  
- **Dev environment:** Entire codebase to be written via Claude Code (Opus). Favor Godot's text-based `.tscn`/`.gd` file structure and avoid workflows that depend on manual GUI-only editor steps where possible.  
- **iOS export:** Will require a Mac \+ Xcode for final build/signing regardless of engine — flag this as a downstream step, not a blocker for early development.  
- **Core systems to architect early:**  
  - Dialogue tree data format (recommend a structured format like JSON or a custom Godot resource — something Claude Code can generate/edit programmatically at scale as the season grows)  
  - World state / flag tracking system (choices, discovered truths, unlocked branches)  
  - Companion relationship stat system (trust/loyalty/romance per character)  
  - "X will remember that" notification UI  
  - QTE input system (touch-based prompts suited for iOS)  
  - Save/load system (critical for episodic structure — must persist state between episode installs/updates)  
- **Save architecture should anticipate multi-episode continuity** from the start, since choices in Episode 1 need to be readable by Episode 2+.

---

## 11\. Established Lore Reference (Quick Sheet)

For consistency across dialogue writing and future episodes:

| Term | Meaning |
| :---- | :---- |
| **The Rupture** | The cataclysmic event at Kharwyn Hold that unleashed magic into the world. Ongoing, not a one-time event. |
| **Kharwyn Hold** | The contested mountain fortress under which the Rupture occurred. |
| **Tremors** | Ongoing aftershocks of the Rupture — the source of new monsters and newly Marked individuals. |
| **The Marked** | People who gain sudden, uncontrolled magical ability from a Tremor (includes the Brother). |
| **Aldreth** | The protagonist's home kingdom — older, ancestral claim to Kharwyn Hold, Old Faith doctrine treats magic as heresy ("the Devouring"). |
| **The Vaeth Dominion (Vaethari)** | The rival kingdom — younger, industrial, expansionist, treats magic as an opportunity to seize rather than a heresy. |
| **The Old Faith** | Aldreth's dominant religion; source of "the Devouring" doctrine and the Prophet's "Awakening" counter-narrative. |

## 13\. Build Process & Environment (For Claude Code)

- **Dev environment:** Godot already installed, Mac \+ Xcode ready for iOS export/signing. No environment setup blockers.  
- **Build order:** Go straight for the **full Episode 1 in one pass** rather than a separate vertical-slice/prototype phase. *Recommendation: playtest scenes as they're completed rather than waiting until the whole episode is done — this catches core-system bugs (dialogue engine, state tracking, save system) before they're baked into every scene built on top of them.*  
- **Art pipeline:** Hybrid approach —  
  1. Start with a free/open-source dark fantasy pixel art pack (browse itch.io) to get the game feeling real in Godot immediately.  
  2. **Confirm commercial-use licensing** on any pack used, since episodes will eventually be sold.  
  3. Architect the art pipeline so sprites/tilesets are swappable references, not hardcoded — real commissioned art (matching the Pinterest reference board) can slot in later without reworking scene/game logic.

## 14\. Remaining Open Items

- Specific pixel art reference pieces from the Pinterest board, if particular images should directly inform character/environment design  
- Exact visual/behavioral design of the first monster(s) the player encounters  
- Whether the true cause of the Rupture (what was actually sealed under Kharwyn Hold) gets revealed within Season 1 or held further out

