class_name DeductionBoard
extends Control
## The game's only puzzle type: reconcile conflicting testimony and commit to a conclusion.
##
## The world premise is that nobody can verify anything, so this is deliberately *not* a quiz with
## a right answer. Two things make it a real mechanic instead of a multiple-choice box:
##
##   1. **Each statement is tappable** and toggles between taken-as-true and doubted. Doubting is
##      the actual verb of the game — the player is choosing who to believe, which is the whole
##      theme, and it's recorded in WorldState so later scenes can vindicate or humiliate them.
##   2. **No option is marked correct in the data.** The payoff arrives episodes later. The board
##      records the belief; the story decides whether it was earned.
##
## A statement may declare a `rumor` id; doubting it resolves that rumor as refuted, trusting it as
## verified. That means a deduction here can gate dialogue in Episode 3.

signal committed(index: int)

var palette_id := "CRYPT"

var _scrim: ColorRect
var _scroll: ScrollContainer
var _column: VBoxContainer
var _question: Label
var _statements: Array = []
## statement index -> true when the player has marked it doubted
var _doubted: Dictionary = {}
var _cards: Array[Button] = []
var _resolved := false


func _ready() -> void:
	# The scrim stays full-bleed (it's meant to cover the screen edge to edge); only the scrolling
	# content is inset, which is handled below.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(0.016, 0.020, 0.031, 0.0)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_inset_scroll()
	SafeArea.changed.connect(_inset_scroll)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 12)
	_scroll.add_child(_column)

	hide()


## The scrim is intentionally full-bleed — it should cover the screen edge to edge, including under
## the notch. Only the readable content is pulled inside the safe area.
func _inset_scroll() -> void:
	if _scroll == null:
		return
	var pad: Vector4 = SafeArea.insets()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 16 + pad.x
	_scroll.offset_top = 44 + pad.y
	_scroll.offset_right = -(16 + pad.z)
	_scroll.offset_bottom = -(24 + pad.w)


func set_palette(id: String) -> void:
	palette_id = id


func present(node: Dictionary) -> void:
	_resolved = false
	_doubted.clear()
	_cards.clear()
	for c in _column.get_children():
		c.queue_free()

	_statements = node.get("statements", [])

	var header := UiKit.label(String(node.get("header", "WHAT DO YOU ACTUALLY BELIEVE?")), UiKit.SIZE_SMALL, ArtRegistry.accent(palette_id))
	_column.add_child(header)

	_question = UiKit.label(String(node.get("question", "")), 21, UiKit.INK)
	_column.add_child(_question)

	var instruction := UiKit.label("Tap any account to doubt it.", UiKit.SIZE_SMALL, UiKit.INK_DIM)
	_column.add_child(instruction)

	_column.add_child(_rule())

	for i in _statements.size():
		var st: Dictionary = _statements[i]
		var card := _make_card(i, st)
		_column.add_child(card)
		_cards.append(card)

	_column.add_child(_rule())

	var commit_label := UiKit.label(String(node.get("commit_prompt", "Your conclusion:")), UiKit.SIZE_SMALL, UiKit.INK_DIM)
	_column.add_child(commit_label)

	var options: Array = node.get("options", [])
	for i in options.size():
		var opt: Dictionary = options[i]
		if not Condition.check(opt.get("if", null)):
			continue
		var b := Button.new()
		b.text = String(opt.get("text", ""))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		UiKit.apply_font(b, UiKit.SIZE_CHOICE)
		var tone := String(opt.get("tone", "curious"))
		b.add_theme_stylebox_override("normal", UiKit.choice_style(palette_id, tone))
		b.add_theme_stylebox_override("hover", UiKit.choice_style(palette_id, tone))
		b.add_theme_stylebox_override("pressed", UiKit.choice_style(palette_id, tone, true))
		b.add_theme_color_override("font_color", UiKit.INK)
		b.add_theme_color_override("font_pressed_color", ArtRegistry.accent_hi(palette_id))
		var idx := i
		b.pressed.connect(func(): _commit(idx))
		_column.add_child(b)

	show()
	var tw := create_tween()
	tw.tween_property(_scrim, "color:a", 0.93, 0.4)
	_scroll.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.tween_interval(0.15)
	tw2.tween_property(_scroll, "modulate:a", 1.0, 0.35)


func _rule() -> Control:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	var c := ArtRegistry.accent(palette_id)
	c.a = 0.22
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _make_card(index: int, st: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 56)
	UiKit.apply_font(b, 15)

	# `attrib` lets a statement come from someone who isn't a tracked companion — a dying stranger,
	# a scrap of overheard rumour. The deduction mechanic needs sources the player can't build a
	# relationship with, or every puzzle collapses into "who do I like most".
	var who := String(st.get("who", ""))
	var speaker := String(st.get("attrib", ""))
	if speaker == "":
		speaker = WorldState.display_name(who) if who != "" else "Unattributed"
	b.text = "%s\n\"%s\"" % [speaker.to_upper(), String(st.get("text", ""))]

	_style_card(b, false)
	var idx := index
	b.pressed.connect(func(): _toggle_doubt(idx))
	return b


func _style_card(b: Button, doubted: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.067, 0.094, 0.95)
	sb.set_border_width_all(0)
	sb.border_width_left = 3
	if doubted:
		sb.bg_color = Color(0.086, 0.031, 0.031, 0.85)
		sb.border_color = Color(0.75, 0.24, 0.22)
	else:
		sb.border_color = ArtRegistry.accent(palette_id)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", UiKit.INK_DIM if doubted else UiKit.INK)
	b.add_theme_color_override("font_hover_color", UiKit.INK_DIM if doubted else UiKit.INK)
	b.add_theme_color_override("font_pressed_color", UiKit.INK)


func _toggle_doubt(index: int) -> void:
	if _resolved or index >= _cards.size():
		return
	var now: bool = not _doubted.get(index, false)
	_doubted[index] = now
	_style_card(_cards[index], now)
	AudioDirector.sting("select")


func _commit(index: int) -> void:
	if _resolved:
		return
	_resolved = true

	# Record who the player chose to disbelieve before the conclusion's own effects run, so a
	# conclusion can react to the doubts in the same beat.
	for i in _statements.size():
		var st: Dictionary = _statements[i]
		var rumor_id := String(st.get("rumor", ""))
		if rumor_id == "":
			continue
		var doubted: bool = _doubted.get(i, false)
		WorldState.hear_rumor(rumor_id, String(st.get("who", "")))
		WorldState.resolve_rumor(rumor_id, "refuted" if doubted else "verified")
	WorldState.set_flag("last_deduction_doubts", _doubted.size())

	AudioDirector.sting("reveal")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_scroll, "modulate:a", 0.0, 0.3)
	tw.tween_property(_scrim, "color:a", 0.0, 0.45)
	await tw.finished
	hide()
	committed.emit(index)
