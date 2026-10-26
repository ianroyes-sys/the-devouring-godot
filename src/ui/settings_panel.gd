extends Control
## Settings overlay.
##
## `timed_choices` and `reduce_shake` are accessibility settings, not difficulty settings, and are
## deliberately not hidden behind a warning — a player who can't beat a 6-second timer should still
## get the whole story. Content authors never check these; the UI layer honours them.

var _palette := "ASHFALL"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.016, 0.020, 0.031, 0.94)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var margin := MarginContainer.new()
	SafeArea.apply(margin)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	col.add_child(UiKit.label("SETTINGS", UiKit.SIZE_SMALL, ArtRegistry.accent(_palette)))

	col.add_child(_slider("Text speed", "text_speed", 0.4, 2.0, 0.1))
	col.add_child(_toggle("Timed choices", "timed_choices",
		"Off gives you unlimited time on every choice."))
	col.add_child(_toggle("Instant text", "skip_seen_text",
		"Skips the typewriter reveal entirely."))
	col.add_child(_toggle("Reduce screen shake", "reduce_shake", ""))
	col.add_child(_slider("Volume", "master_volume", 0.0, 1.0, 0.05))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 50)
	UiKit.apply_font(back, UiKit.SIZE_CHOICE)
	back.add_theme_stylebox_override("normal", UiKit.choice_style(_palette, "neutral"))
	back.add_theme_stylebox_override("hover", UiKit.choice_style(_palette, "warm"))
	back.add_theme_stylebox_override("pressed", UiKit.choice_style(_palette, "warm", true))
	back.add_theme_color_override("font_color", UiKit.INK)
	back.pressed.connect(queue_free)
	col.add_child(back)


func _toggle(label_text: String, key: String, help: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var cb := CheckButton.new()
	cb.text = label_text
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = bool(SaveManager.setting(key, true))
	UiKit.apply_font(cb, UiKit.SIZE_CHOICE)
	cb.add_theme_color_override("font_color", UiKit.INK)
	cb.add_theme_color_override("font_pressed_color", UiKit.INK)
	cb.add_theme_color_override("font_hover_color", UiKit.INK)
	cb.toggled.connect(func(on: bool): SaveManager.set_setting(key, on))
	row.add_child(cb)

	if help != "":
		row.add_child(UiKit.label(help, 11, UiKit.INK_LOCKED))
	return row


func _slider(label_text: String, key: String, lo: float, hi: float, step: float) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var value_label := UiKit.label("%s  —  %.2f" % [label_text, float(SaveManager.setting(key, 1.0))], UiKit.SIZE_CHOICE, UiKit.INK)
	row.add_child(value_label)

	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(SaveManager.setting(key, 1.0))
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 28)
	s.value_changed.connect(func(v: float):
		SaveManager.set_setting(key, v)
		value_label.text = "%s  —  %.2f" % [label_text, v]
		if key == "master_volume":
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, v)))
	)
	row.add_child(s)
	return row
