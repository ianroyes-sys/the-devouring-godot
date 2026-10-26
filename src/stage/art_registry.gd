class_name ArtRegistry
extends RefCounted
## The single indirection layer between content and image files.
##
## Content JSON says `"bg": "kharwyn_field"`, never a path. Swapping today's procedural
## placeholders for commissioned art (brief §13.3) is an edit to the tables in this file and
## nothing else — no scene, script, or content change. If you ever find `res://assets/` written
## in a .tscn or a content file, that's a bug.

const BG_DIR := "res://assets/bg"
const CHAR_DIR := "res://assets/char"

## Palettes transcribed from docs/ART_DIRECTION.md §2. Ordered dark -> light, accent last.
## Kept in code as well as in the doc because the stage tints UI chrome and fog to match the
## active scene palette, so these values have to be reachable at runtime.
const PALETTES := {
	"ASHFALL": {
		"ramp": ["#0d0810", "#1a1018", "#3a0d14", "#7a1520", "#b8322e", "#d9553a"],
		"accent": "#ff9a3c", "accent_hi": "#ffd98a",
	},
	"DROWNED": {
		"ramp": ["#070b1a", "#0e1730", "#1b2a52", "#2d4a86", "#4a7fc4", "#7fa9dd"],
		"accent": "#5fe0e8", "accent_hi": "#b6f5f2",
	},
	"VIOLET": {
		"ramp": ["#140a1f", "#26123a", "#3f1d5c", "#6b2f86", "#a34a9e", "#d97ab5"],
		"accent": "#f2d7ff", "accent_hi": "#ffffff",
	},
	"BOGSHADE": {
		"ramp": ["#101410", "#1b241c", "#2e3d2e", "#47593f", "#6b7d55", "#96a37c"],
		"accent": "#c6cfa8", "accent_hi": "#e4e8cd",
	},
	"CRYPT": {
		"ramp": ["#060608", "#121216", "#22222a", "#3a3a44", "#5c5c68", "#8a8a96"],
		"accent": "#ffb45c", "accent_hi": "#ffd9a8",
	},
	"SNOWLIGHT": {
		"ramp": ["#0b0f18", "#182231", "#2c3a4d", "#4d5f75", "#8397ab", "#cdd8e2"],
		"accent": "#e8f2ff", "accent_hi": "#ffffff",
	},
}

## The magic override from art direction §2 — Marked characters glow in a colour that does not
## belong to whatever palette the scene is using. The clash is the point.
const MAGIC_GLOW := "#5fe0e8"
const MAGIC_GLOW_HI := "#b6f5f2"

## bg id -> parallax planes, far to near. Missing planes are skipped silently.
const BACKDROPS := {
	"kharwyn_field": {"palette": "ASHFALL", "planes": ["far", "mid", "near"]},
	"kharwyn_undercroft": {"palette": "DROWNED", "planes": ["far", "mid", "near"]},
	"treeline_dusk": {"palette": "VIOLET", "planes": ["far", "mid", "near"]},
	"bog_road": {"palette": "BOGSHADE", "planes": ["far", "mid", "near"]},
	"tunnel_mouth": {"palette": "CRYPT", "planes": ["far", "mid", "near"]},
}

## Parallax strength per plane. Higher = moves more on camera push-in, so reads as nearer.
const PLANE_DEPTH := {"far": 0.12, "mid": 0.45, "near": 1.0}

## Character silhouette sets. `full` = tableau scale, `bust` = close-up plate (art direction §5).
const CHARACTERS := {
	"protagonist": {"full": "protagonist_full", "bust": "protagonist_bust"},
	"brother": {"full": "brother_full", "bust": "brother_bust"},
	"medic": {"full": "medic_full", "bust": "medic_bust"},
	"enemy_soldier": {"full": "enemy_soldier_full", "bust": "enemy_soldier_bust"},
	"prophet": {"full": "prophet_full", "bust": "prophet_bust"},
	"scavenger": {"full": "scavenger_full", "bust": "scavenger_bust"},
}

## Camera zoom per framing register, per art direction §4.
const FRAMING := {
	"wide": 1.0,
	"mid": 1.4,
	"close": 2.2,
	"insert": 3.0,
}


static func color(hex: String) -> Color:
	return Color(hex)


static func palette(id: String) -> Dictionary:
	if PALETTES.has(id):
		return PALETTES[id]
	push_warning("ArtRegistry: unknown palette '%s', falling back to CRYPT." % id)
	return PALETTES["CRYPT"]


static func ramp(palette_id: String) -> Array:
	return palette(palette_id)["ramp"]


static func ramp_color(palette_id: String, index: int) -> Color:
	var r: Array = ramp(palette_id)
	return Color(r[clampi(index, 0, r.size() - 1)])


static func accent(palette_id: String) -> Color:
	return Color(palette(palette_id)["accent"])


static func accent_hi(palette_id: String) -> Color:
	return Color(palette(palette_id)["accent_hi"])


static func backdrop_palette(bg_id: String) -> String:
	return BACKDROPS.get(bg_id, {}).get("palette", "CRYPT")


static func backdrop_planes(bg_id: String) -> Array:
	return BACKDROPS.get(bg_id, {}).get("planes", [])


static func backdrop_texture(bg_id: String, plane: String) -> Texture2D:
	return _load("%s/%s_%s.png" % [BG_DIR, bg_id, plane])


static func character_texture(who: String, kind: String = "full") -> Texture2D:
	var entry: Dictionary = CHARACTERS.get(who, {})
	var name: String = entry.get(kind, "")
	if name == "":
		return null
	return _load("%s/%s.png" % [CHAR_DIR, name])


static func framing_zoom(framing: String) -> float:
	return FRAMING.get(framing, 1.0)


static func _load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		# Deliberately a warning, not an error: an unfinished sprite should leave a hole in the
		# frame, not stop a playtest.
		push_warning("ArtRegistry: missing art '%s'" % path)
		return null
	return load(path) as Texture2D
