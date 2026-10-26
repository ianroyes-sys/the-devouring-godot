class_name DialogueBox
extends Control
## Bottom-anchored dialogue panel with typewriter reveal and a speaker plate.
##
## Behaviour that matters for feel:
##   - Tapping while text is still revealing completes it instantly; tapping again advances. Two
##     distinct taps, because a single "tap does both" makes players skip lines by accident.
##   - The narrator gets no name plate and renders italic + dimmed, so world-voice and
##     character-voice are never confusable.
##   - `tone` changes reveal speed: a whisper crawls, a shout lands almost instantly. Since there's
##     no voice acting, pacing is the only performance channel available.

signal advance_requested()

const BASE_CPS := 46.0          ## characters per second at text_speed 1.0
const TONE_SPEED := {
	"whisper": 0.55,
	"strained": 0.75,
	"neutral": 1.0,
	"shout": 2.4,
}

var palette_id := "CRYPT"

var _panel: PanelContainer
var _speaker_plate: PanelContainer
var _speaker_label: Label
var _body: RichTextLabel
var _chevron: Label
var _tap_catcher: Control

var _revealing := false
var _reveal_tween: Tween
var _chevron_tween: Tween
var _full_text := ""


func _ready() -> void:
	# Inset for the notch and the home indicator: a bottom-anchored panel would otherwise sit in
	# the swipe-up gesture zone, where tapping to advance can dismiss the app.
	SafeArea.apply(self)
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Catches taps across the whole screen, not just the panel, so advancing never requires
	# precision. Sits behind the panel so buttons still win.
	_tap_catcher = Control.new()
	_tap_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tap_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_tap_catcher.gui_input.connect(_on_tap)
	add_child(_tap_catcher)

	# BOTTOM_WIDE lets the panel hug its own content height at the bottom of the screen rather than
	# being a fixed slab. Short lines get a small box; the body's minimum height keeps it from
	# jittering between one- and two-line beats.
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# BOTTOM_WIDE pins the rect *at* the bottom edge with zero height, so a content-sized panel
	# grows downward off-screen. GROW_DIRECTION_BEGIN makes it grow upward from the bottom edge,
	# which is what "bottom-anchored panel that hugs its content" actually requires.
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_speaker_plate = PanelContainer.new()
	_speaker_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_speaker_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker_label = UiKit.label("", UiKit.SIZE_SPEAKER, UiKit.INK)
	# Must not wrap. The plate shrinks to its content, and a wrapping label reports a one-character
	# minimum width — which renders the speaker's name as a vertical column of letters.
	_speaker_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_speaker_label.add_theme_constant_override("line_spacing", 0)
	_speaker_plate.add_child(_speaker_label)
	vbox.add_child(_speaker_plate)

	_body = UiKit.rich("", UiKit.SIZE_BODY, UiKit.INK)
	_body.custom_minimum_size = Vector2(0, 96)
	vbox.add_child(_body)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron = UiKit.label("▾", UiKit.SIZE_SMALL, UiKit.INK_DIM)
	_chevron.modulate.a = 0.0
	footer.add_child(_chevron)
	vbox.add_child(footer)

	set_palette(palette_id)
	hide()


func set_palette(id: String) -> void:
	palette_id = id
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(id))

	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0)
	plate.set_border_width_all(0)
	plate.border_width_bottom = 1
	var b := ArtRegistry.accent(id)
	b.a = 0.45
	plate.border_color = b
	plate.content_margin_bottom = 3
	plate.content_margin_left = 0
	plate.content_margin_right = 6
	_speaker_plate.add_theme_stylebox_override("panel", plate)


func show_line(node: Dictionary) -> void:
	var speaker := String(node.get("speaker", "narrator"))
	var text := String(node.get("text", ""))
	var tone := String(node.get("tone", "neutral"))

	var is_narrator := speaker == "narrator" or speaker == ""
	_speaker_plate.visible = not is_narrator
	if not is_narrator:
		_speaker_label.text = WorldState.display_name(speaker)
		var col := UiKit.INK
		if speaker == "protagonist":
			col = ArtRegistry.accent_hi(palette_id)
		_speaker_label.add_theme_color_override("font_color", col)

	_full_text = text
	if is_narrator:
		_body.add_theme_color_override("default_color", UiKit.INK_DIM)
		_body.text = "[i]%s[/i]" % text
	else:
		_body.add_theme_color_override("default_color", UiKit.INK)
		_body.text = text

	show()
	_start_reveal(tone, text.length())


func _start_reveal(tone: String, char_count: int) -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_hide_chevron()

	var speed_mult: float = TONE_SPEED.get(tone, 1.0) * float(SaveManager.setting("text_speed", 1.0))
	var cps: float = maxf(8.0, BASE_CPS * speed_mult)
	var dur: float = float(char_count) / cps

	if SaveManager.setting("skip_seen_text", false):
		dur = 0.0

	_body.visible_ratio = 0.0
	_revealing = true
	if dur <= 0.01:
		_body.visible_ratio = 1.0
		_finish_reveal()
		return

	_reveal_tween = create_tween()
	_reveal_tween.tween_property(_body, "visible_ratio", 1.0, dur)
	_reveal_tween.tween_callback(_finish_reveal)


func _finish_reveal() -> void:
	_revealing = false
	_show_chevron()


func complete_reveal() -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_body.visible_ratio = 1.0
	_finish_reveal()


func _show_chevron() -> void:
	if _chevron_tween and _chevron_tween.is_valid():
		_chevron_tween.kill()
	_chevron.modulate.a = 1.0
	_chevron_tween = create_tween().set_loops()
	_chevron_tween.tween_property(_chevron, "modulate:a", 0.25, 0.8).set_trans(Tween.TRANS_SINE)
	_chevron_tween.tween_property(_chevron, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func _hide_chevron() -> void:
	if _chevron_tween and _chevron_tween.is_valid():
		_chevron_tween.kill()
	_chevron.modulate.a = 0.0


func _on_tap(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
	if not pressed:
		return

	if _revealing:
		complete_reveal()
	else:
		advance_requested.emit()


func set_input_enabled(on: bool) -> void:
	_tap_catcher.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func dismiss() -> void:
	_hide_chevron()
	hide()
