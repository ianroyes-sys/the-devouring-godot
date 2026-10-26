extends Control
## Title screen. Also the episode-select surface once Episode 2 exists.
##
## The tagline does real work: it states the game's central disagreement before the player has
## made a single choice, which primes them to distrust everything a character tells them later.

const TITLE := "THE DEVOURING"
const TAGLINE := "Aldreth calls it the Devouring.\nThe Prophet calls it the Awakening.\nNobody knows which is true."

var _palette := "ASHFALL"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_backdrop()

	# Backdrop stays full-bleed; only the text column is inset for the notch.
	var margin := MarginContainer.new()
	SafeArea.apply(margin)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 96)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := UiKit.label(TITLE, UiKit.SIZE_TITLE, ArtRegistry.accent_hi(_palette))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	var rc := ArtRegistry.accent(_palette)
	rc.a = 0.4
	rule.color = rc
	col.add_child(rule)

	var tag := UiKit.label(TAGLINE, UiKit.SIZE_SMALL, UiKit.INK_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)

	col.add_child(_spacer())

	var ep := UiKit.label("EPISODE ONE  ·  %s" % SceneDirector.episode_title(1).to_upper(), UiKit.SIZE_SMALL, ArtRegistry.accent(_palette))
	ep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ep)

	if SaveManager.has_save():
		var meta := SaveManager.peek()
		var sub := "%d choices made" % int(meta.get("choices", 0))
		col.add_child(_menu_button("Continue", sub, _on_continue))

	col.add_child(_menu_button("New Game", "", _on_new_game))
	col.add_child(_menu_button("Settings", "", _on_settings))

	col.add_child(_spacer())

	var footer := UiKit.label("v%s  ·  pre-alpha" % ProjectSettings.get_setting("application/config/version", "0.1.0"), 10, UiKit.INK_LOCKED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(footer)

	AudioDirector.play_bed("wind")

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.9)


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = ArtRegistry.ramp_color(_palette, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Reuse the scene backdrop art so the menu belongs to the same world as the game.
	for plane in ArtRegistry.backdrop_planes("kharwyn_field"):
		var tex := ArtRegistry.backdrop_texture("kharwyn_field", String(plane))
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = Color(0.55, 0.55, 0.6, 1.0)
		add_child(tr)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.024, 0.031, 0.047, 0.62)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _menu_button(text: String, subtitle: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text if subtitle == "" else "%s\n%s" % [text, subtitle]
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(0, 54)
	UiKit.apply_font(b, UiKit.SIZE_CHOICE)
	b.add_theme_stylebox_override("normal", UiKit.choice_style(_palette, "neutral"))
	b.add_theme_stylebox_override("hover", UiKit.choice_style(_palette, "warm"))
	b.add_theme_stylebox_override("pressed", UiKit.choice_style(_palette, "warm", true))
	b.add_theme_color_override("font_color", UiKit.INK)
	b.add_theme_color_override("font_pressed_color", ArtRegistry.accent_hi(_palette))
	b.pressed.connect(cb)
	return b


func _on_continue() -> void:
	await SceneDirector.continue_game()


func _on_new_game() -> void:
	if SaveManager.has_save():
		# Overwriting a run is destructive and the player can't undo it, so make them confirm.
		_confirm_overwrite()
		return
	await SceneDirector.start_new_game()


func _confirm_overwrite() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Starting over will overwrite your current run and every choice in it."
	dlg.ok_button_text = "Start over"
	dlg.cancel_button_text = "Keep my run"
	add_child(dlg)
	dlg.confirmed.connect(func():
		SaveManager.delete_save()
		SceneDirector.start_new_game()
	)
	dlg.popup_centered()


func _on_settings() -> void:
	var script: GDScript = load("res://src/ui/settings_panel.gd")
	var panel: Control = script.new()
	add_child(panel)
