extends Node
## Offline validator for every dialogue graph in data/.
##
## Runs as a *scene* rather than via `--script`, because `--script` starts a bare SceneTree with no
## autoloads — and every condition expression in content is evaluated against the WorldState
## autoload, so a script-mode validator can't compile the very code it needs to check.
##
## Catches the failure modes that are invisible until a player walks into them:
##   - a `next` pointing at a node that doesn't exist (soft lock)
##   - unreachable nodes (content written and then orphaned by a rewrite)
##   - condition expressions that don't parse (silently-false branches)
##   - a timed choice with neither `default` nor `on_timeout` (silence does nothing)
##   - unknown effect verbs (typos that no-op forever)
##   - speakers and companion keys that aren't real
##   - backdrops, palettes, beds and stings that don't resolve
##
## Run:  Godot --headless --path . --script src/tools/validate_data.gd

const DATA_ROOT := "res://data"

var errors: Array[String] = []
var warnings: Array[String] = []
var files_checked := 0
var nodes_checked := 0


func _ready() -> void:
	var files := _find_json(DATA_ROOT)
	files.sort()
	if files.is_empty():
		print("No dialogue data found under %s" % DATA_ROOT)
		_finish(1)
		return

	for f in files:
		_check_file(f)

	print("")
	print("Checked %d scene file(s), %d node(s)." % [files_checked, nodes_checked])

	if not warnings.is_empty():
		print("\n%d warning(s):" % warnings.size())
		for w in warnings:
			print("  ~ " + w)

	if not errors.is_empty():
		print("\n%d ERROR(S):" % errors.size())
		for e in errors:
			print("  x " + e)
		print("\nFAILED")
		_finish(1)
		return

	print("\nAll graphs valid.")
	_finish(0)


func _finish(code: int) -> void:
	# Non-zero exit so this is usable as a pre-commit / CI gate, not just something a human reads.
	get_tree().quit(code)


func _find_json(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_find_json(full))
		elif name.ends_with(".json"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _check_file(path: String) -> void:
	files_checked += 1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: cannot open" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()

	if not parsed is Dictionary:
		errors.append("%s: not a JSON object" % path)
		return

	var graph: Dictionary = parsed
	var short := path.get_file()
	var nodes: Variant = graph.get("nodes", null)
	if not nodes is Dictionary or (nodes as Dictionary).is_empty():
		errors.append("%s: no `nodes` object" % short)
		return

	var entry := String(graph.get("entry", ""))
	if entry == "":
		warnings.append("%s: no `entry`; first key will be used" % short)
	elif not nodes.has(entry):
		errors.append("%s: entry `%s` is not a node" % [short, entry])

	_check_effects(short, "on_enter", graph.get("on_enter", []))
	_check_effects(short, "on_exit", graph.get("on_exit", []))
	if graph.has("stage"):
		_check_stage(short, "graph.stage", graph["stage"])

	# Reachability: walk every edge out of every node.
	var reachable := {}
	var targets_of := {}
	for id in nodes:
		targets_of[id] = []

	for id in nodes:
		nodes_checked += 1
		var node: Dictionary = nodes[id]
		var where := "%s:%s" % [short, id]
		var type := String(node.get("type", "line"))

		if not type in ["line", "choice", "qte", "deduction", "branch", "jump", "end"]:
			errors.append("%s: unknown type `%s`" % [where, type])

		if type == "line":
			if String(node.get("text", "")) == "":
				errors.append("%s: line has no text" % where)
			var sp := String(node.get("speaker", "narrator"))
			if sp != "narrator" and sp != "protagonist" and not sp in WorldState.COMPANIONS:
				errors.append("%s: unknown speaker `%s`" % [where, sp])

		if node.has("stage"):
			_check_stage(where, "stage", node["stage"])
		if node.has("shot"):
			_check_shot(where, node["shot"])
		_check_effects(where, "effects", node.get("effects", []))

		# Collect edges.
		var edges: Array[String] = []
		edges.append_array(_targets(where, "next", node.get("next", null)))

		match type:
			"choice":
				var opts: Variant = node.get("options", null)
				if not opts is Array or (opts as Array).is_empty():
					errors.append("%s: choice has no options" % where)
				else:
					var ids := {}
					for i in (opts as Array).size():
						var opt: Variant = opts[i]
						if not opt is Dictionary:
							errors.append("%s: option %d is not an object" % [where, i])
							continue
						var oid := String(opt.get("id", ""))
						if oid == "":
							warnings.append("%s: option %d has no id (logged as generated key)" % [where, i])
						elif ids.has(oid):
							errors.append("%s: duplicate option id `%s`" % [where, oid])
						else:
							ids[oid] = true
						if String(opt.get("text", "")) == "":
							errors.append("%s: option `%s` has no text" % [where, oid])
						_check_cond(where + "/" + oid, opt.get("if", null))
						_check_effects(where + "/" + oid, "effects", opt.get("effects", []))
						if opt.has("remember"):
							_check_who(where + "/" + oid, String(opt["remember"]))
						edges.append_array(_targets(where + "/" + oid, "next", opt.get("next", null)))

					# A timed choice must have an authored outcome for silence.
					if float(node.get("timer", 0.0)) > 0.0:
						var has_default := String(node.get("default", "")) != ""
						var has_timeout := node.has("on_timeout")
						if not has_default and not has_timeout:
							errors.append("%s: timed choice has neither `default` nor `on_timeout` — silence would fall through" % where)
						if has_default and not ids.has(String(node["default"])):
							errors.append("%s: `default` id `%s` is not one of the options" % [where, node["default"]])
				_check_effects(where, "timeout_effects", node.get("timeout_effects", []))
				edges.append_array(_targets(where, "on_timeout", node.get("on_timeout", null)))
				edges.append_array(_targets(where, "fallback", node.get("fallback", null)))

			"qte":
				var kind := String(node.get("kind", ""))
				if not kind in ["tap", "rapid_tap", "hold", "swipe"]:
					errors.append("%s: unknown qte kind `%s`" % [where, kind])
				if kind == "rapid_tap" and int(node.get("target", 0)) <= 0:
					errors.append("%s: rapid_tap needs a positive `target`" % where)
				if kind == "swipe" and not String(node.get("direction", "")) in ["left", "right", "up", "down"]:
					errors.append("%s: swipe needs a valid `direction`" % where)
				if float(node.get("duration", 0.0)) <= 0.0:
					errors.append("%s: qte needs a positive `duration`" % where)
				if not node.has("success") or not node.has("fail"):
					errors.append("%s: qte must declare both `success` and `fail`" % where)
				_check_effects(where, "success_effects", node.get("success_effects", []))
				_check_effects(where, "fail_effects", node.get("fail_effects", []))
				edges.append_array(_targets(where, "success", node.get("success", null)))
				edges.append_array(_targets(where, "fail", node.get("fail", null)))

			"deduction":
				var sts: Variant = node.get("statements", null)
				if not sts is Array or (sts as Array).size() < 2:
					errors.append("%s: deduction needs at least 2 statements to reconcile" % where)
				else:
					for st in sts:
						if st is Dictionary and st.has("who"):
							_check_who(where, String(st["who"]))
				var dopts: Variant = node.get("options", null)
				if not dopts is Array or (dopts as Array).is_empty():
					errors.append("%s: deduction has no options" % where)
				else:
					for i in (dopts as Array).size():
						var opt2: Dictionary = dopts[i]
						_check_cond("%s/opt%d" % [where, i], opt2.get("if", null))
						_check_effects("%s/opt%d" % [where, i], "effects", opt2.get("effects", []))
						edges.append_array(_targets("%s/opt%d" % [where, i], "next", opt2.get("next", null)))

		targets_of[id] = edges
		for t in edges:
			if t == "" or t == "END":
				continue
			if not nodes.has(t):
				errors.append("%s: points at missing node `%s`" % [where, t])

	# BFS from entry to find orphans.
	var start := entry if nodes.has(entry) else String(nodes.keys()[0])
	var queue := [start]
	reachable[start] = true
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for t in targets_of.get(id, []):
			if t == "" or t == "END" or reachable.has(t) or not nodes.has(t):
				continue
			reachable[t] = true
			queue.append(t)

	for id in nodes:
		if not reachable.has(id):
			warnings.append("%s:%s is unreachable from `%s`" % [short, id, start])

	# A graph with no path to an ending is a soft lock.
	var has_end := false
	for id in nodes:
		if not reachable.has(id):
			continue
		if String(nodes[id].get("type", "line")) == "end":
			has_end = true
			break
		for t in targets_of.get(id, []):
			if t == "END" or t == "":
				has_end = true
				break
		if has_end:
			break
	if not has_end:
		errors.append("%s: no reachable ending — the scene can never finish" % short)


func _targets(where: String, key: String, spec: Variant) -> Array[String]:
	var out: Array[String] = []
	if spec == null:
		return out
	if spec is String:
		out.append(String(spec))
		return out
	if spec is Array:
		var saw_unconditional := false
		for entry in spec:
			if not entry is Dictionary:
				errors.append("%s: `%s` array entry is not an object" % [where, key])
				continue
			if not entry.has("to"):
				errors.append("%s: `%s` branch entry has no `to`" % [where, key])
				continue
			out.append(String(entry["to"]))
			_check_cond(where, entry.get("if", null))
			if not entry.has("if") or String(entry.get("if", "")).strip_edges() == "":
				saw_unconditional = true
		if not saw_unconditional:
			warnings.append("%s: every `%s` branch is conditional — all-false falls through to the end of the scene" % [where, key])
		return out
	errors.append("%s: `%s` must be a string or array" % [where, key])
	return out


func _check_cond(where: String, expr: Variant) -> void:
	var err := Condition.validate(expr)
	if err != "":
		errors.append("%s: bad condition `%s` — %s" % [where, expr, err])


## Strict: relationship and remember targets must be real companions. The protagonist can't have a
## relationship with himself and can't remember his own choice, so he is deliberately rejected here.
func _check_who(where: String, who: String) -> void:
	if who == "" or who == "world" or who == "custom":
		return
	if not who in WorldState.COMPANIONS:
		errors.append("%s: unknown companion `%s`" % [where, who])


## Looser: anything that can stand on stage or be framed by a shot, which includes the protagonist.
func _check_cast_who(where: String, who: String) -> void:
	if who == "" or who == "protagonist":
		return
	if not who in WorldState.COMPANIONS:
		errors.append("%s: unknown cast key `%s`" % [where, who])


func _check_effects(where: String, key: String, list: Variant) -> void:
	if list == null:
		return
	if not list is Array:
		errors.append("%s: `%s` must be an array" % [where, key])
		return
	for e in list:
		if not e is Dictionary:
			errors.append("%s: `%s` entry is not an object" % [where, key])
			continue
		var recognised := false
		for k in e:
			if not k in Effects.VERBS:
				errors.append("%s: `%s` has unknown effect key `%s`" % [where, key, k])
			elif not k in ["if", "value", "by", "stat", "source", "verdict", "intensity"]:
				recognised = true
		if not recognised:
			warnings.append("%s: `%s` entry has no actual effect verb" % [where, key])
		_check_cond(where, e.get("if", null))
		if e.has("adjust"):
			_check_who(where, String(e["adjust"]))
			if not String(e.get("stat", "trust")) in WorldState.STATS:
				errors.append("%s: unknown stat `%s`" % [where, e.get("stat")])
		if e.has("meet"):
			_check_who(where, String(e["meet"]))
		if e.has("remember"):
			_check_who(where, String(e["remember"]))
		if e.has("bed") and not ArtRegistry.BACKDROPS.is_empty():
			if not AudioDirector.BEDS.has(String(e["bed"])):
				errors.append("%s: unknown audio bed `%s`" % [where, e["bed"]])
		if e.has("pulse") and not AudioDirector.PULSES.has(String(e["pulse"])):
			errors.append("%s: unknown audio pulse `%s`" % [where, e["pulse"]])
		if e.has("sting") and not AudioDirector.STINGS.has(String(e["sting"])):
			errors.append("%s: unknown audio sting `%s`" % [where, e["sting"]])
		if e.has("verdict") and not String(e["verdict"]) in ["verified", "refuted"]:
			errors.append("%s: verdict must be verified or refuted, got `%s`" % [where, e["verdict"]])


func _check_stage(where: String, key: String, d: Variant) -> void:
	if not d is Dictionary:
		errors.append("%s: `%s` must be an object" % [where, key])
		return
	var st: Dictionary = d
	if st.has("bg") and not ArtRegistry.BACKDROPS.has(String(st["bg"])):
		errors.append("%s: unknown backdrop `%s`" % [where, st["bg"]])
	if st.has("palette") and not ArtRegistry.PALETTES.has(String(st["palette"])):
		errors.append("%s: unknown palette `%s`" % [where, st["palette"]])
	if st.has("bed") and not AudioDirector.BEDS.has(String(st["bed"])):
		errors.append("%s: unknown audio bed `%s`" % [where, st["bed"]])
	if st.has("pulse") and not AudioDirector.PULSES.has(String(st["pulse"])):
		errors.append("%s: unknown audio pulse `%s`" % [where, st["pulse"]])
	if st.has("sting") and not AudioDirector.STINGS.has(String(st["sting"])):
		errors.append("%s: unknown audio sting `%s`" % [where, st["sting"]])
	for k in ["cast", "exit"]:
		if st.has(k):
			if not st[k] is Array:
				errors.append("%s: `%s.%s` must be an array" % [where, key, k])
			else:
				for who in st[k]:
					_check_cast_who(where, String(who))
	if st.has("enter"):
		for entry in st["enter"]:
			if entry is Dictionary:
				_check_cast_who(where, String(entry.get("who", "")))
				var at := String(entry.get("at", "center"))
				if not Stage.SLOTS.has(at):
					errors.append("%s: unknown stage slot `%s`" % [where, at])
			elif entry is String:
				_check_cast_who(where, String(entry))
	for k in ["glow", "unglow"]:
		if st.has(k):
			_check_cast_who(where, String(st[k]))


func _check_shot(where: String, d: Variant) -> void:
	if not d is Dictionary:
		errors.append("%s: `shot` must be an object" % where)
		return
	var shot: Dictionary = d
	var fr := String(shot.get("framing", "wide"))
	if not ArtRegistry.FRAMING.has(fr):
		errors.append("%s: unknown framing `%s`" % [where, fr])
	if shot.has("focus"):
		var focus := String(shot["focus"])
		if focus != "" and focus != "protagonist" and not focus in WorldState.COMPANIONS:
			errors.append("%s: shot focus `%s` is not a cast key" % [where, focus])
