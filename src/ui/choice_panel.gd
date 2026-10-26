class_name ChoicePanel
extends Control
## Timed / untimed choice list, bottom-anchored and thumb-reachable.
##
## Two decisions worth defending:
##
## 1. The timer is a thin draining bar at the top edge of the panel, not a countdown number. A
##    number makes players optimise; a bar makes them feel hurried. Telltale's tension comes from
##    the second thing.
## 2. Gated options can render greyed out via `locked_text` instead of vanishing. Seeing the door
##    you lack the key for is what makes the relationship stats feel real — an invisible branch
##    teaches the player nothing.
##
## The `timed_choices` accessibility setting disables timers globally without touching content.

signal chosen(index: int)
signal timed_out()

const MAX_OPTIONS := 5

var palette_id := "CRYPT"

var _panel: PanelContainer
var _timer_bar: ProgressBar
var _prompt: Label
var _list: VBoxContainer
var _buttons: Array[Button] = []

var _time_left := 0.0
var _time_total := 0.0
var _timing := false
var _resolved := false


func _ready() -> void:
	# The last option in the list is the one a thumb rests on, so it must clear the home indicator.
	SafeArea.apply(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# Grow upward from the bottom edge — see the same note in dialogue_box.gd.
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 3)
	_timer_bar.max_value = 1.0
	_timer_bar.value = 1.0
	_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_timer_bar)

	_prompt = UiKit.label("", UiKit.SIZE_SMALL, UiKit.INK_DIM)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_prompt)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 7)
	vbox.add_child(_list)

	set_palette(palette_id)
	hide()


func set_palette(id: String) -> void:
	palette_id = id
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(id))

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.07)
	_timer_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ArtRegistry.accent(id)
	_timer_bar.add_theme_stylebox_override("fill", fill)


func present(node: Dictionary, options: Array) -> void:
	_resolved = false
	_clear()

	_prompt.text = String(node.get("prompt", ""))
	_prompt.visible = _prompt.text != ""

	var count: int = mini(options.size(), MAX_OPTIONS)
	if options.size() > MAX_OPTIONS:
		push_warning("ChoicePanel: %d options offered, showing %d. Portrait can't hold more." % [options.size(), MAX_OPTIONS])

	for i in count:
		var opt: Dictionary = options[i]
		var locked: bool = opt.get("_locked", false)
		var b := Button.new()
		b.text = String(opt.get("text", ""))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = locked
		UiKit.apply_font(b, UiKit.SIZE_CHOICE)

		var tone := String(opt.get("tone", "neutral"))
		b.add_theme_stylebox_override("normal", UiKit.choice_style(palette_id, tone, false, locked))
		b.add_theme_stylebox_override("hover", UiKit.choice_style(palette_id, tone, false, locked))
		b.add_theme_stylebox_override("pressed", UiKit.choice_style(palette_id, tone, true, locked))
		b.add_theme_stylebox_override("disabled", UiKit.choice_style(palette_id, tone, false, true))
		b.add_theme_color_override("font_color", UiKit.INK_LOCKED if locked else UiKit.INK)
		b.add_theme_color_override("font_disabled_color", UiKit.INK_LOCKED)
		b.add_theme_color_override("font_hover_color", UiKit.INK)
		b.add_theme_color_override("font_pressed_color", ArtRegistry.accent_hi(palette_id))

		if not locked:
			var idx := i
			b.pressed.connect(func(): _pick(idx))

		_list.add_child(b)
		_buttons.append(b)

		# Stagger the entrance so the list reads top-to-bottom instead of appearing as a wall.
		b.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.18)

	var t := float(node.get("timer", 0.0))
	if t > 0.0 and bool(SaveManager.setting("timed_choices", true)):
		_time_total = t
		_time_left = t
		_timing = true
		_timer_bar.visible = true
		_timer_bar.value = 1.0
	else:
		_timing = false
		_timer_bar.visible = false

	show()


func _process(delta: float) -> void:
	if not _timing or _resolved:
		return
	_time_left -= delta
	var frac := clampf(_time_left / _time_total, 0.0, 1.0)
	_timer_bar.value = frac

	# Bar turns hostile in the last third — the only colour change in the whole UI, so it reads.
	var fill := StyleBoxFlat.new()
	fill.bg_color = ArtRegistry.accent(palette_id) if frac > 0.33 else Color(0.75, 0.24, 0.22)
	_timer_bar.add_theme_stylebox_override("fill", fill)

	if _time_left <= 0.0:
		_timing = false
		_resolved = true
		AudioDirector.sting("tick")
		dismiss()
		timed_out.emit()


func _pick(index: int) -> void:
	if _resolved:
		return
	_resolved = true
	_timing = false
	AudioDirector.sting("select")

	# Brief confirmation flash on the picked option so the player sees what they committed to
	# before the panel leaves.
	if index < _buttons.size():
		var b := _buttons[index]
		b.add_theme_color_override("font_color", ArtRegistry.accent_hi(palette_id))
	for i in _buttons.size():
		if i != index:
			var other := _buttons[i]
			var tw := create_tween()
			tw.tween_property(other, "modulate:a", 0.15, 0.15)

	await get_tree().create_timer(0.18).timeout
	dismiss()
	chosen.emit(index)


func _clear() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()


func dismiss() -> void:
	hide()
	_timing = false
	_clear()
