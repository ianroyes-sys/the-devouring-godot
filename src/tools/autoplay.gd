extends Node
## Headless branch-coverage harness.
##
## Drives DialogueRuntime directly (no UI) through many randomised playthroughs, resolving every
## player-facing node automatically. The validator proves the graph is *shaped* correctly; this
## proves it *executes* — that every effect verb applies, every branch condition evaluates, and no
## path hits a missing node or a runtime error.
##
## It also reports which nodes and choice options were never reached, which is how you find content
## you wrote and then orphaned behind a condition that can't be true.
##
##   Godot --headless --path . res://src/tools/Autoplay.tscn

const RUNS := 400
const MAX_STEPS := 600

var _visited_nodes := {}
var _taken_options := {}
var _all_options := {}
var _qte_outcomes := {"success": 0, "fail": 0}
var _timeouts := 0
var _errors: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var scenes := SceneDirector.scene_list(1)
	print("Autoplay: %d run(s) over %d scene(s)\n" % [RUNS, scenes.size()])

	var total_steps := 0
	for run in RUNS:
		_rng.seed = 1000 + run
		WorldState.reset()
		for scene_id in scenes:
			total_steps += _play(1, scene_id, run)

	_report(scenes)


func _play(episode: int, scene_id: String, run: int) -> int:
	var rt := DialogueRuntime.new()
	add_child(rt)
	var path := SceneDirector.data_path(episode, scene_id)
	if not rt.load_graph(path):
		_errors.append("run %d: could not load %s" % [run, path])
		rt.free()
		return 0

	var graph_nodes: Dictionary = rt.graph.get("nodes", {})
	if run == 0:
		for id in graph_nodes:
			var n: Dictionary = graph_nodes[id]
			if String(n.get("type", "line")) == "choice":
				for i in (n.get("options", []) as Array).size():
					var oid := String((n["options"][i] as Dictionary).get("id", "#%d" % i))
					_all_options["%s/%s" % [id, oid]] = true

	var pending := {"kind": "", "node": {}, "options": []}
	var done := [false]

	rt.node_entered.connect(func(id: String, _n: Dictionary):
		_visited_nodes[id] = true
	)
	rt.line_shown.connect(func(_n: Dictionary):
		pending["kind"] = "line"
	)
	rt.choices_offered.connect(func(n: Dictionary, opts: Array):
		pending["kind"] = "choice"
		pending["node"] = n
		pending["options"] = opts
	)
	rt.qte_requested.connect(func(_n: Dictionary):
		pending["kind"] = "qte"
	)
	rt.deduction_requested.connect(func(n: Dictionary):
		pending["kind"] = "deduction"
		pending["node"] = n
	)
	rt.finished.connect(func(_s: String):
		done[0] = true
	)

	rt.start()

	var steps := 0
	while not done[0] and steps < MAX_STEPS:
		steps += 1
		match pending["kind"]:
			"line":
				pending["kind"] = ""
				rt.advance()
			"choice":
				var node: Dictionary = pending["node"]
				var opts: Array = pending["options"]
				pending["kind"] = ""
				# Occasionally let a timed choice expire, so the timeout paths get exercised too —
				# they're the easiest branches to write and never test.
				var timer := float(node.get("timer", 0.0))
				if timer > 0.0 and _rng.randf() < 0.18:
					_timeouts += 1
					rt.timeout_choice()
				else:
					var pickable: Array[int] = []
					for i in opts.size():
						if not (opts[i] as Dictionary).get("_locked", false):
							pickable.append(i)
					if pickable.is_empty():
						_errors.append("run %d: choice `%s` had no pickable options" % [run, rt.current_id])
						break
					var idx: int = pickable[_rng.randi_range(0, pickable.size() - 1)]
					var oid := String((opts[idx] as Dictionary).get("id", "#%d" % idx))
					_taken_options["%s/%s" % [rt.current_id, oid]] = true
					rt.pick_choice(idx)
			"qte":
				pending["kind"] = ""
				var ok := _rng.randf() < 0.5
				_qte_outcomes["success" if ok else "fail"] += 1
				rt.resolve_qte(ok)
			"deduction":
				var dnode: Dictionary = pending["node"]
				pending["kind"] = ""
				var available: Array[int] = []
				for i in (dnode.get("options", []) as Array).size():
					var opt: Dictionary = dnode["options"][i]
					if Condition.check(opt.get("if", null)):
						available.append(i)
				if available.is_empty():
					_errors.append("run %d: deduction `%s` had no available options" % [run, rt.current_id])
					break
				rt.resolve_deduction(available[_rng.randi_range(0, available.size() - 1)])
			_:
				_errors.append("run %d: stalled at `%s` with nothing pending" % [run, rt.current_id])
				break

	if steps >= MAX_STEPS:
		_errors.append("run %d: exceeded %d steps in %s — possible cycle" % [run, MAX_STEPS, scene_id])

	# Free synchronously: 400 runs of deferred frees would otherwise all land at quit() and
	# report as leaked instances, which looks like a game bug and isn't one.
	rt.free()
	return steps


func _report(scenes: Array) -> void:
	var total_nodes := 0
	var unvisited: Array[String] = []
	for scene_id in scenes:
		var path := SceneDirector.data_path(1, scene_id)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var g: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not g is Dictionary:
			continue
		var ns: Dictionary = (g as Dictionary).get("nodes", {})
		total_nodes += ns.size()
		for id in ns:
			if not _visited_nodes.has(id):
				unvisited.append("%s:%s" % [scene_id, id])

	var untaken: Array[String] = []
	for key in _all_options:
		if not _taken_options.has(key):
			untaken.append(key)

	print("Node coverage:   %d / %d (%.1f%%)" % [
		total_nodes - unvisited.size(), total_nodes,
		100.0 * float(total_nodes - unvisited.size()) / maxf(1.0, float(total_nodes))])
	print("Option coverage: %d / %d" % [_all_options.size() - untaken.size(), _all_options.size()])
	print("QTE outcomes:    %d success / %d fail" % [_qte_outcomes["success"], _qte_outcomes["fail"]])
	print("Choice timeouts: %d" % _timeouts)

	if not unvisited.is_empty():
		print("\nNever reached (%d):" % unvisited.size())
		unvisited.sort()
		for n in unvisited:
			print("  ~ " + n)

	if not untaken.is_empty():
		print("\nOptions never taken (%d) — check their `if` conditions:" % untaken.size())
		untaken.sort()
		for o in untaken:
			print("  ~ " + o)

	if not _errors.is_empty():
		print("\n%d ERROR(S):" % _errors.size())
		for e in _errors:
			print("  x " + e)
		print("\nFAILED")
		get_tree().quit(1)
		return

	print("\nAll runs completed without error.")
	get_tree().quit(0)
