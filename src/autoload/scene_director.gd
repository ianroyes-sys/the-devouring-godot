extends Node
## Owns scene transitions and the episode manifest.
##
## Content never calls change_scene_to_file directly — everything routes through here so that
## fade-outs, autosaves, and the per-scene notifier dedupe all happen in the right order and in
## one place. Getting that order wrong is how you lose a player's choices on a crash.

signal scene_will_change(from_id: String, to_id: String)
signal scene_ready(scene_id: String)
signal episode_complete(episode: int)

const EPISODES := {
	1: {
		"title": "Kharwyn",
		"scenes": [
			"s01_the_tremor",
			# s02+ land as they're written; the runner walks this list in order.
		],
	},
}

const PLAY_SCENE := "res://src/scenes/PlayScene.tscn"
const MENU_SCENE := "res://src/scenes/MainMenu.tscn"

var _fade: ColorRect
var _layer: CanvasLayer
var _transitioning := false


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 200          # above the notifier — a fade must cover everything
	_layer.name = "TransitionLayer"
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0.024, 0.031, 0.047, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	_layer.add_child(_fade)


func scene_list(episode: int) -> Array:
	return EPISODES.get(episode, {}).get("scenes", [])


func episode_title(episode: int) -> String:
	return EPISODES.get(episode, {}).get("title", "")


func data_path(episode: int, scene_id: String) -> String:
	return "res://data/episode%d/%s.json" % [episode, scene_id]


# --- flow -------------------------------------------------------------------------------------

func start_new_game() -> void:
	WorldState.reset()
	WorldState.current_episode = 1
	await play_scene(1, scene_list(1)[0])


func continue_game() -> void:
	if not SaveManager.load_game():
		await start_new_game()
		return
	var ep: int = WorldState.current_episode
	var target: String = WorldState.current_scene
	if target == "" or not target in scene_list(ep):
		target = _first_unplayed(ep)
	await play_scene(ep, target)


func _first_unplayed(episode: int) -> String:
	for s in scene_list(episode):
		if not WorldState.completed(s):
			return s
	return scene_list(episode)[0]


func play_scene(episode: int, scene_id: String) -> void:
	if _transitioning:
		return
	_transitioning = true

	var from: String = WorldState.current_scene
	scene_will_change.emit(from, scene_id)

	await fade_out(0.5)

	WorldState.current_episode = episode
	WorldState.current_scene = scene_id
	Notifier.clear_scene_dedupe()
	# Save *before* loading the new scene, so a crash mid-load resumes at the boundary rather
	# than replaying the scene the player just finished.
	SaveManager.autosave()

	var packed: PackedScene = load(PLAY_SCENE)
	var inst := packed.instantiate()
	inst.set("episode", episode)
	inst.set("scene_id", scene_id)

	var tree := get_tree()
	if tree.current_scene:
		tree.current_scene.queue_free()
	tree.root.add_child(inst)
	tree.current_scene = inst

	await tree.process_frame
	scene_ready.emit(scene_id)
	await fade_in(0.7)
	_transitioning = false


## Called by PlayScene when a scene's dialogue graph reaches an end node.
func finish_scene(scene_id: String) -> void:
	WorldState.mark_scene_complete(scene_id)
	var ep: int = WorldState.current_episode
	var scenes := scene_list(ep)
	var idx := scenes.find(scene_id)

	if idx >= 0 and idx + 1 < scenes.size():
		await play_scene(ep, scenes[idx + 1])
		return

	# End of episode.
	SaveManager.record_episode_complete(ep)
	episode_complete.emit(ep)
	await go_to_menu()


func go_to_menu() -> void:
	await fade_out(0.6)
	AudioDirector.stop_all(0.6)
	get_tree().change_scene_to_file(MENU_SCENE)
	await get_tree().process_frame
	await fade_in(0.6)


# --- fades ------------------------------------------------------------------------------------

func fade_out(dur: float = 0.5) -> void:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, dur)
	await tw.finished


func fade_in(dur: float = 0.6) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, dur)
	await tw.finished
	_fade.visible = false
