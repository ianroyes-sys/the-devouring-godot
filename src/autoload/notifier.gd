extends Node
## The "X will remember that" system.
##
## Telltale's signature. Two rules make it work and both are easy to get wrong:
##   1. It must never overlap the dialogue box or a choice — it sits top-right, above everything.
##   2. It must be *rare*. If every line fires a toast the player stops reading them. So this
##      dedupes per scene and rate-limits: a companion can only be flagged once per beat.
##
## Toasts queue rather than stack, so two companions reacting to the same choice read as a
## sequence, which is more legible than two boxes fighting for the same corner.

signal toast_shown(who: String)

const HOLD_TIME := 2.4
const GAP := 0.35

var _layer: CanvasLayer
var _root: VBoxContainer
var _queue: Array[Dictionary] = []
var _busy := false
## who -> true, cleared on scene change so the same companion can react again next scene
var _flagged_this_scene: Dictionary = {}

var _font: FontFile


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "NotifierLayer"
	add_child(_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_left", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(margin)

	_root = VBoxContainer.new()
	_root.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_theme_constant_override("separation", 6)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_root)


func clear_scene_dedupe() -> void:
	_flagged_this_scene.clear()


## `who` is a companion key ("brother"), or "world" for faction/global consequences.
func remember(who: String, once_per_scene: bool = true) -> void:
	if once_per_scene and _flagged_this_scene.has(who):
		return
	_flagged_this_scene[who] = true

	var label := ""
	if who == "world":
		label = "This will have consequences."
	else:
		label = "%s will remember that." % WorldState.display_name(who)
	_queue.append({"who": who, "text": label})
	if not _busy:
		_drain()


## For non-relationship consequences: "The Old Faith will remember that."
func remember_custom(text: String) -> void:
	_queue.append({"who": "custom", "text": text})
	if not _busy:
		_drain()


func _drain() -> void:
	_busy = true
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		await _show(item["text"])
		toast_shown.emit(item["who"])
		await get_tree().create_timer(GAP).timeout
	_busy = false


func _show(text: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.024, 0.031, 0.047, 0.86)
	sb.border_color = Color(1.0, 0.604, 0.235, 0.55)  # ASHFALL accent, low alpha
	sb.set_border_width_all(0)
	sb.border_width_left = 2
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.902, 0.851, 0.788))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	_root.add_child(panel)

	panel.modulate.a = 0.0
	panel.position.x += 14
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.22)
	tw.tween_property(panel, "position:x", panel.position.x - 14, 0.28) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw.finished

	await get_tree().create_timer(HOLD_TIME).timeout

	var out := create_tween()
	out.tween_property(panel, "modulate:a", 0.0, 0.35)
	await out.finished
	panel.queue_free()
