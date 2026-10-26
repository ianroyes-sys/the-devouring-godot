class_name DialogueRuntime
extends Node
## Walks a scene's dialogue graph and tells the presentation layer what to show.
##
## The runtime knows nothing about UI, art, or input. It emits a signal describing what should
## happen and then waits to be told the player resolved it. That split is what makes the same
## content playable in the editor, in a headless test, and eventually in a Godot-free tool.
##
## Graph JSON shape is documented in docs/DIALOGUE_FORMAT.md.

signal line_shown(node: Dictionary)
signal choices_offered(node: Dictionary, options: Array)
signal qte_requested(node: Dictionary)
signal deduction_requested(node: Dictionary)
signal stage_directive(directive: Dictionary)
signal shot_requested(shot: Dictionary)
signal node_entered(id: String, node: Dictionary)
signal finished(scene_id: String)

## Guard against a content author writing a branch/jump cycle with no player-facing node in it.
const MAX_SILENT_HOPS := 64

var scene_id := ""
var graph: Dictionary = {}
var current_id := ""

var _nodes: Dictionary = {}
var _awaiting := false     ## true while a player-facing node is on screen
var _silent_hops := 0


func load_graph(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("DialogueRuntime: no scene data at %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_error("DialogueRuntime: %s is not valid JSON object" % path)
		return false

	graph = parsed
	scene_id = String(graph.get("id", path.get_file().get_basename()))
	_nodes = graph.get("nodes", {})
	if _nodes.is_empty():
		push_error("DialogueRuntime: %s has no nodes" % path)
		return false
	return true


func start() -> void:
	var entry := String(graph.get("entry", ""))
	if entry == "":
		entry = _nodes.keys()[0]
	# Scene-level opening directives (backdrop, palette, ambient bed) before the first line.
	if graph.has("stage"):
		stage_directive.emit(graph["stage"])
	Effects.apply_all(graph.get("on_enter", []))
	_goto(entry)


func is_awaiting() -> bool:
	return _awaiting


# --- graph walking ----------------------------------------------------------------------------

func _goto(id: String) -> void:
	if id == "" or id == "END":
		_finish()
		return
	if not _nodes.has(id):
		push_error("DialogueRuntime[%s]: node '%s' does not exist. Ending scene to avoid a soft lock." % [scene_id, id])
		_finish()
		return

	_silent_hops += 1
	if _silent_hops > MAX_SILENT_HOPS:
		push_error("DialogueRuntime[%s]: %d hops without a player-facing node near '%s' — likely a branch cycle." % [scene_id, MAX_SILENT_HOPS, id])
		_finish()
		return

	current_id = id
	var node: Dictionary = _nodes[id]
	node_entered.emit(id, node)

	Effects.apply_all(node.get("effects", []))

	if node.has("stage"):
		stage_directive.emit(node["stage"])
	if node.has("shot"):
		shot_requested.emit(node["shot"])

	match String(node.get("type", "line")):
		"line":
			_awaiting = true
			_silent_hops = 0
			line_shown.emit(node)
		"choice":
			var opts := _visible_options(node)
			if opts.is_empty():
				# Every option was gated out. Fall through rather than trapping the player.
				push_warning("DialogueRuntime[%s]: choice '%s' has no available options; using fallback." % [scene_id, id])
				_goto(_resolve_next(node.get("fallback", node.get("next", ""))))
				return
			_awaiting = true
			_silent_hops = 0
			choices_offered.emit(node, opts)
		"qte":
			_awaiting = true
			_silent_hops = 0
			qte_requested.emit(node)
		"deduction":
			_awaiting = true
			_silent_hops = 0
			deduction_requested.emit(node)
		"branch":
			_goto(_resolve_next(node.get("next", "")))
		"jump":
			_goto(_resolve_next(node.get("next", "")))
		"end":
			_finish()
		_:
			push_error("DialogueRuntime[%s]: unknown node type '%s' at '%s'" % [scene_id, node.get("type"), id])
			_finish()


## `next` is either a node id, or an array of {"if": cond, "to": id} evaluated in order with the
## last entry conventionally unconditional. Inline branching keeps small forks readable without
## a separate branch node for every two-way split.
func _resolve_next(spec: Variant) -> String:
	if spec is String:
		return spec
	if spec is Array:
		for entry in spec:
			if not entry is Dictionary:
				continue
			if Condition.check(entry.get("if", null)):
				return String(entry.get("to", ""))
		return ""
	return ""


func _visible_options(node: Dictionary) -> Array:
	var out: Array = []
	for opt in node.get("options", []):
		if not opt is Dictionary:
			continue
		if not Condition.check(opt.get("if", null)):
			# `locked_text` shows the option greyed out so the player can see what they missed.
			if opt.has("locked_text"):
				var ghost: Dictionary = opt.duplicate()
				ghost["_locked"] = true
				ghost["text"] = String(opt["locked_text"])
				out.append(ghost)
			continue
		out.append(opt)
	return out


func _finish() -> void:
	_awaiting = false
	Effects.apply_all(graph.get("on_exit", []))
	finished.emit(scene_id)


# --- player resolutions -----------------------------------------------------------------------

func advance() -> void:
	if not _awaiting:
		return
	var node: Dictionary = _nodes.get(current_id, {})
	if String(node.get("type", "line")) != "line":
		return
	_awaiting = false
	_goto(_resolve_next(node.get("next", "")))


func pick_choice(index: int) -> void:
	if not _awaiting:
		return
	var node: Dictionary = _nodes.get(current_id, {})
	if String(node.get("type", "")) != "choice":
		return
	var opts := _visible_options(node)
	if index < 0 or index >= opts.size():
		return
	var opt: Dictionary = opts[index]
	if opt.get("_locked", false):
		return

	_awaiting = false

	var choice_id := String(opt.get("id", "%s#%d" % [current_id, index]))
	WorldState.log_choice(scene_id, current_id, choice_id, String(opt.get("text", "")))
	Effects.apply_all(opt.get("effects", []))
	if opt.has("remember"):
		Notifier.remember(String(opt["remember"]))

	_goto(_resolve_next(opt.get("next", node.get("next", ""))))


## Called when a timed choice runs out. Uses the node's declared default so silence is an
## authored position, not an accident — the brief's grimdark register wants "you said nothing"
## to be a real choice with real consequences.
func timeout_choice() -> void:
	if not _awaiting:
		return
	var node: Dictionary = _nodes.get(current_id, {})
	if String(node.get("type", "")) != "choice":
		return

	var default_id := String(node.get("default", ""))
	if default_id != "":
		var opts := _visible_options(node)
		for i in opts.size():
			if String(opts[i].get("id", "")) == default_id:
				pick_choice(i)
				return

	_awaiting = false
	WorldState.log_choice(scene_id, current_id, "%s#silence" % current_id, "[said nothing]")
	Effects.apply_all(node.get("timeout_effects", []))
	var target := _resolve_next(node.get("on_timeout", node.get("next", "")))
	_goto(target)


func resolve_qte(success: bool) -> void:
	if not _awaiting:
		return
	var node: Dictionary = _nodes.get(current_id, {})
	if String(node.get("type", "")) != "qte":
		return
	_awaiting = false
	Effects.apply_all(node.get("success_effects" if success else "fail_effects", []))
	var key := "success" if success else "fail"
	_goto(_resolve_next(node.get(key, node.get("next", ""))))


func resolve_deduction(index: int) -> void:
	if not _awaiting:
		return
	var node: Dictionary = _nodes.get(current_id, {})
	if String(node.get("type", "")) != "deduction":
		return
	var options: Array = node.get("options", [])
	if index < 0 or index >= options.size():
		return
	var opt: Dictionary = options[index]

	_awaiting = false
	WorldState.log_choice(scene_id, current_id, String(opt.get("id", "%s#%d" % [current_id, index])), String(opt.get("text", "")))
	Effects.apply_all(opt.get("effects", []))
	_goto(_resolve_next(opt.get("next", node.get("next", ""))))
