extends Node
## Screenshot harness. Runs the real PlayScene, drives it forward, and captures the frame at named
## story beats so visuals can be reviewed without a human sitting through the scene.
##
##   Godot --path . res://src/tools/Capture.tscn
##
## Not headless: headless has no renderer, so viewport capture would come back blank.

const OUT_DIR := "user://captures"

## node id -> output filename. Chosen to cover every UI surface and every palette.
const SHOTS := {
	"wake_05": "01_wake_wide",
	"first_choice": "02_choice_untimed",
	"find_cael_05": "03_close_plate_brother",
	"reveal_02": "04_the_light",
	"react_choice": "05_choice_timed",
	"harrow_03": "06_close_plate_medic",
	"harrow_07": "07_three_hander",
	"deduce_01": "08_deduction",
	"qte_01": "09_qte",
	"escape_converge_01": "10_treeline",
	"close_08": "11_close_final",
}

var _play: Node
var _pending_shot := ""
var _shots_taken := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("Capture -> %s" % ProjectSettings.globalize_path(OUT_DIR))

	var packed: PackedScene = load("res://src/scenes/PlayScene.tscn")
	_play = packed.instantiate()
	_play.set("episode", 1)
	_play.set("scene_id", "s01_the_tremor")
	add_child(_play)

	await get_tree().process_frame
	await get_tree().process_frame

	var rt: DialogueRuntime = _play.get("runtime")
	if rt == null:
		push_error("Capture: PlayScene exposed no runtime")
		get_tree().quit(1)
		return

	rt.node_entered.connect(func(id: String, _n: Dictionary):
		if SHOTS.has(id):
			_pending_shot = SHOTS[id]
	)
	var finished := [false]
	rt.finished.connect(func(_s: String): finished[0] = true)

	# Drive the scene. Generous settle time before each capture so tweens (camera push-ins,
	# typewriter reveals, panel fades) have actually landed in the captured frame.
	var guard := 0
	while not finished[0] and guard < 400:
		guard += 1
		await get_tree().create_timer(0.16).timeout

		if _pending_shot != "":
			await get_tree().create_timer(1.1).timeout
			await _capture(_pending_shot)
			_pending_shot = ""

		if not rt.is_awaiting():
			continue

		var node: Dictionary = rt.graph["nodes"].get(rt.current_id, {})
		match String(node.get("type", "line")):
			"line": rt.advance()
			"choice": rt.pick_choice(0)
			"qte": rt.resolve_qte(true)
			"deduction": rt.resolve_deduction(0)

	print("Captured %d frame(s)." % _shots_taken)
	get_tree().quit(0)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	if err != OK:
		push_error("Capture: failed to write %s (%d)" % [path, err])
		return
	_shots_taken += 1
	print("  %s" % name)
