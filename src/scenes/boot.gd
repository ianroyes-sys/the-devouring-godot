extends Control
## Cold-start scene. Applies saved settings, shows a brief studio/warning card, then hands off.
##
## The content warning card is here rather than buried in a menu because the episode opens on a
## mass-casualty aftermath in the first thirty seconds.

const HOLD := 2.2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.024, 0.031, 0.047)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var warn := UiKit.label(
		"This story contains depictions of war,\nmass death, and religious violence.",
		UiKit.SIZE_SMALL, UiKit.INK_DIM)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(warn)

	# Restore volume before any audio plays, so the first ambient bed doesn't blast someone who
	# turned it down last session.
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(SaveManager.setting("master_volume", 0.9)))))

	col.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(col, "modulate:a", 1.0, 0.8)
	tw.tween_interval(HOLD)
	tw.tween_property(col, "modulate:a", 0.0, 0.6)
	await tw.finished

	get_tree().change_scene_to_file(SceneDirector.MENU_SCENE)
