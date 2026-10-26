extends Node
## Central authority for everything the player has done, learned, and broken.
##
## Everything branching in the game reads from here and nowhere else. Dialogue conditions are
## GDScript expressions evaluated with this node as the base instance, so any method below is
## callable from content JSON — e.g. `trust("brother") >= 3 and not has_flag("burned_the_body")`.
##
## Design note: `rumors` is deliberately separate from `truths`. The world premise is that nobody
## knows what's real, so the player accumulates *claims* long before (or instead of) facts. A rumor
## being marked verified/refuted is a story event, not a bookkeeping detail.

signal flag_changed(key: String, value: Variant)
signal relationship_changed(who: String, stat: String, value: int, delta: int)
signal truth_learned(id: String)
signal rumor_heard(id: String)
signal rumor_resolved(id: String, verdict: String)

const COMPANIONS := ["brother", "medic", "enemy_soldier", "prophet", "scavenger"]

## Display names, kept here so "X will remember that" and speaker plates never disagree.
const DISPLAY_NAMES := {
	"brother": "Cael",
	"medic": "Harrow",
	"enemy_soldier": "Vesk",
	"prophet": "The Prophet",
	"scavenger": "Rook",
	"protagonist": "You",
	"narrator": "",
}

const STATS := ["trust", "loyalty", "romance"]
const STAT_MIN := -10
const STAT_MAX := 10

# --- state ------------------------------------------------------------------------------------

## Arbitrary story flags. Bools, ints, strings, enums-as-strings.
var flags: Dictionary = {}

## who -> {trust: int, loyalty: int, romance: int, met: bool}
var relationships: Dictionary = {}

## Things the player has established as actually true. id -> true
var truths: Dictionary = {}

## Claims the player has heard. id -> {"source": String, "verdict": "unknown"|"verified"|"refuted"}
var rumors: Dictionary = {}

## Ordered log of consequential choices, for an end-of-episode recap and for Ep2+ to read.
## Each entry: {"scene": String, "node": String, "choice": String, "label": String}
var choice_log: Array = []

## Episode/scene progress.
var current_episode: int = 1
var current_scene: String = ""
var completed_scenes: Array = []


func _ready() -> void:
	reset()


func reset() -> void:
	flags.clear()
	truths.clear()
	rumors.clear()
	choice_log.clear()
	relationships.clear()
	for who in COMPANIONS:
		relationships[who] = {"trust": 0, "loyalty": 0, "romance": 0, "met": false}
	current_episode = 1
	current_scene = ""
	completed_scenes = []


# --- flags ------------------------------------------------------------------------------------

func set_flag(key: String, value: Variant = true) -> void:
	var old: Variant = flags.get(key, null)
	if old == value:
		return
	flags[key] = value
	flag_changed.emit(key, value)


func has_flag(key: String) -> bool:
	## True only if the flag exists AND is truthy. `has_flag("x")` on a flag set to false is false,
	## which is almost always what content authors mean.
	var v: Variant = flags.get(key, false)
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return v != null


func flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)


func bump_flag(key: String, delta: int = 1) -> void:
	var v: Variant = flags.get(key, 0)
	var n: int = (int(v) if (v is int or v is float) else 0) + delta
	flags[key] = n
	flag_changed.emit(key, n)


# --- relationships ----------------------------------------------------------------------------

func adjust(who: String, stat: String, delta: int) -> void:
	if not relationships.has(who):
		push_warning("WorldState.adjust: unknown companion '%s'" % who)
		return
	if not stat in STATS:
		push_warning("WorldState.adjust: unknown stat '%s'" % stat)
		return
	var before: int = relationships[who][stat]
	var after: int = clampi(before + delta, STAT_MIN, STAT_MAX)
	if after == before:
		return
	relationships[who][stat] = after
	relationship_changed.emit(who, stat, after, after - before)


func trust(who: String) -> int:
	return _stat(who, "trust")


func loyalty(who: String) -> int:
	return _stat(who, "loyalty")


func romance(who: String) -> int:
	return _stat(who, "romance")


func _stat(who: String, stat: String) -> int:
	if not relationships.has(who):
		return 0
	return relationships[who][stat]


func meet(who: String) -> void:
	if relationships.has(who):
		relationships[who]["met"] = true


func has_met(who: String) -> bool:
	return relationships.has(who) and relationships[who]["met"]


func display_name(who: String) -> String:
	return DISPLAY_NAMES.get(who, who.capitalize())


# --- truths & rumors --------------------------------------------------------------------------

func learn(id: String) -> void:
	if truths.has(id):
		return
	truths[id] = true
	truth_learned.emit(id)


func knows(id: String) -> bool:
	return truths.has(id)


func hear_rumor(id: String, source: String = "") -> void:
	if rumors.has(id):
		return
	rumors[id] = {"source": source, "verdict": "unknown"}
	rumor_heard.emit(id, source)


func heard(id: String) -> bool:
	return rumors.has(id)


func resolve_rumor(id: String, verdict: String) -> void:
	## verdict: "verified" | "refuted"
	if not rumors.has(id):
		rumors[id] = {"source": "", "verdict": verdict}
	else:
		rumors[id]["verdict"] = verdict
	if verdict == "verified":
		learn(id)
	rumor_resolved.emit(id, verdict)


func rumor_verdict(id: String) -> String:
	if not rumors.has(id):
		return "unheard"
	return rumors[id]["verdict"]


func believes(id: String) -> bool:
	return rumor_verdict(id) == "verified"


## Count of rumors the player has resolved either way — a decent proxy for "how carefully is
## this person actually listening", usable to gate insight-flavoured dialogue options.
func deductions_made() -> int:
	var n := 0
	for id in rumors:
		if rumors[id]["verdict"] != "unknown":
			n += 1
	return n


# --- choice log -------------------------------------------------------------------------------

func log_choice(scene: String, node: String, choice_id: String, label: String) -> void:
	choice_log.append({
		"scene": scene, "node": node, "choice": choice_id, "label": label,
	})


func chose(choice_id: String) -> bool:
	for entry in choice_log:
		if entry["choice"] == choice_id:
			return true
	return false


# --- scene progress ---------------------------------------------------------------------------

func mark_scene_complete(scene_id: String) -> void:
	if not scene_id in completed_scenes:
		completed_scenes.append(scene_id)


func completed(scene_id: String) -> bool:
	return scene_id in completed_scenes


# --- serialisation ----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"relationships": relationships.duplicate(true),
		"truths": truths.duplicate(true),
		"rumors": rumors.duplicate(true),
		"choice_log": choice_log.duplicate(true),
		"current_episode": current_episode,
		"current_scene": current_scene,
		"completed_scenes": completed_scenes.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	reset()
	flags = d.get("flags", {}).duplicate(true)
	truths = d.get("truths", {}).duplicate(true)
	rumors = d.get("rumors", {}).duplicate(true)
	choice_log = d.get("choice_log", []).duplicate(true)
	current_episode = int(d.get("current_episode", 1))
	current_scene = String(d.get("current_scene", ""))
	completed_scenes = d.get("completed_scenes", []).duplicate()

	# Merge rather than replace, so a save written before a companion existed still loads with
	# that companion present at defaults. This is the whole reason Ep2 can read Ep1 saves.
	var saved: Dictionary = d.get("relationships", {})
	for who in saved:
		if not relationships.has(who):
			relationships[who] = {"trust": 0, "loyalty": 0, "romance": 0, "met": false}
		for stat in saved[who]:
			relationships[who][stat] = saved[who][stat]
