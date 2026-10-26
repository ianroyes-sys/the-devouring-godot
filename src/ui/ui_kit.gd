class_name UiKit
extends RefCounted
## Shared styling so every piece of UI agrees on colour, weight, and spacing.
##
## The UI is deliberately palette-reactive: chrome borders and accents pull from whatever palette
## the current scene declared, so the interface belongs to the scene instead of floating above it.
## Art direction §7 forbids UI covering more than the bottom 40% of the screen — the constants
## here enforce that.

## Drop a licensed pixel font at this path and every text element picks it up. Free options that
## match the reference board's density: Departure Mono (OFL), m6x11 (free), Pixel Operator (CC0).
## Until one is present the engine default is used, which is legible but not on-style.
const FONT_PATH := "res://assets/fonts/pixel.ttf"

const INK := Color(0.902, 0.878, 0.831)          ## body text — warm off-white, never pure white
const INK_DIM := Color(0.588, 0.573, 0.545)      ## secondary / narrator
const INK_LOCKED := Color(0.353, 0.345, 0.333)   ## unavailable choices
const PANEL_BG := Color(0.024, 0.031, 0.047, 0.90)
const PANEL_BG_SOLID := Color(0.024, 0.031, 0.047, 1.0)

const SIZE_BODY := 17
const SIZE_SPEAKER := 13
const SIZE_CHOICE := 16
const SIZE_SMALL := 12
const SIZE_TITLE := 34

const MAX_UI_HEIGHT_FRACTION := 0.40

## Tone tints for choice options. These colour a 3px left edge only — never the text, and never
## with an icon. The player should feel a register, not read a morality label.
const TONE_COLORS := {
	"warm": Color(0.85, 0.55, 0.28),
	"cold": Color(0.42, 0.62, 0.82),
	"neutral": Color(0.55, 0.53, 0.50),
	"curious": Color(0.62, 0.52, 0.78),
	"violent": Color(0.75, 0.24, 0.22),
	"faith": Color(0.78, 0.72, 0.45),
}


static func font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		return load(FONT_PATH)
	return null


static func apply_font(node: Control, size: int) -> void:
	var f := font()
	if f:
		node.add_theme_font_override("font", f)
		node.add_theme_font_override("normal_font", f)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_font_size_override("normal_font_size", size)


static func panel_style(palette_id: String, top_border: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(0)
	if top_border:
		sb.border_width_top = 1
		var b := ArtRegistry.accent(palette_id)
		b.a = 0.28
		sb.border_color = b
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 18
	return sb


static func choice_style(palette_id: String, tone: String, pressed: bool = false, locked: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.067, 0.094, 0.94 if not pressed else 1.0)
	if locked:
		sb.bg_color = Color(0.039, 0.043, 0.055, 0.72)
	sb.set_border_width_all(0)
	sb.border_width_left = 3
	var edge: Color = TONE_COLORS.get(tone, TONE_COLORS["neutral"])
	if locked:
		edge = INK_LOCKED
	elif pressed:
		edge = ArtRegistry.accent(palette_id)
	sb.border_color = edge
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", col)
	apply_font(l, size)
	return l


## Small caps-ish treatment for speaker plates and captions without needing a second font.
static func spaced_caps(s: String) -> String:
	return " ".join(s.to_upper().split(""))


static func rich(text: String, size: int, col: Color) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_color_override("default_color", col)
	apply_font(r, size)
	return r
