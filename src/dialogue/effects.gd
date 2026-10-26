class_name Effects
extends RefCounted
## Applies content-authored effect lists to WorldState.
##
## An effect is one dictionary with exactly one "verb" key plus its arguments. Keeping the verb as
## the key (rather than {"op": "..."}) makes the JSON noticeably easier to skim when a scene has
## forty of them, which matters because story authors read this far more often than code does.
##
##     [{"flag": "saw_the_light"},
##      {"adjust": "brother", "stat": "trust", "by": 2},
##      {"learn": "tunnel_was_vaethari"},
##      {"rumor": "the_hold_still_burns", "source": "scavenger"},
##      {"resolve": "the_hold_still_burns", "verdict": "refuted"},
##      {"remember": "brother"}]

static func apply_all(list: Variant) -> void:
	if not list is Array:
		return
	for e in list:
		if e is Dictionary:
			apply(e)


static func apply(e: Dictionary) -> void:
	# Conditional effects: {"if": "...", "flag": "..."} only fires when the condition holds.
	if e.has("if") and not Condition.check(e["if"]):
		return

	if e.has("flag"):
		WorldState.set_flag(String(e["flag"]), e.get("value", true))

	if e.has("unflag"):
		WorldState.set_flag(String(e["unflag"]), false)

	if e.has("bump"):
		WorldState.bump_flag(String(e["bump"]), int(e.get("by", 1)))

	if e.has("adjust"):
		WorldState.adjust(String(e["adjust"]), String(e.get("stat", "trust")), int(e.get("by", 0)))

	if e.has("learn"):
		WorldState.learn(String(e["learn"]))

	if e.has("rumor"):
		WorldState.hear_rumor(String(e["rumor"]), String(e.get("source", "")))

	if e.has("resolve"):
		WorldState.resolve_rumor(String(e["resolve"]), String(e.get("verdict", "verified")))

	if e.has("meet"):
		WorldState.meet(String(e["meet"]))

	if e.has("remember"):
		Notifier.remember(String(e["remember"]))

	if e.has("remember_text"):
		Notifier.remember_custom(String(e["remember_text"]))

	if e.has("sting"):
		AudioDirector.sting(String(e["sting"]))

	if e.has("bed"):
		AudioDirector.play_bed(String(e["bed"]))

	if e.has("pulse"):
		AudioDirector.set_pulse(String(e["pulse"]), float(e.get("intensity", 1.0)))


## Verbs the validator knows about, so a misspelled effect is caught offline.
const VERBS := [
	"if", "flag", "value", "unflag", "bump", "by", "adjust", "stat", "learn", "rumor",
	"source", "resolve", "verdict", "meet", "remember", "remember_text", "sting", "bed",
	"pulse", "intensity",
]
