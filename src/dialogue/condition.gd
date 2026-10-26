class_name Condition
extends RefCounted
## Evaluates content-authored condition strings against WorldState.
##
## Conditions in dialogue JSON are plain GDScript expressions with WorldState as the base
## instance, so every public method on WorldState is callable directly:
##
##     "has_flag('told_medic')"
##     "trust('brother') >= 3 and not knows('tunnel_was_vaethari')"
##     "believes('the_hold_still_burns') or deductions_made() >= 2"
##     "flag('route') == 'north'"
##
## Using Godot's own Expression parser rather than a hand-rolled mini-language means authors get
## real operators and precedence for free, and a typo produces a parse error at validation time
## instead of a silently-false branch at runtime.

static var _cache: Dictionary = {}
static var _errors: Array[String] = []


## Returns true for an empty/absent condition, so `"if"` is optional everywhere in content.
static func check(expr: Variant) -> bool:
	if expr == null:
		return true
	var s := String(expr).strip_edges()
	if s == "":
		return true

	var e: Expression = _compile(s)
	if e == null:
		return false

	var result: Variant = e.execute([], WorldState, true)
	if e.has_execute_failed():
		_report("Condition failed at runtime: `%s`" % s)
		return false
	if result is bool:
		return result
	# Truthiness for authors who write `flag('x')` bare.
	if result is int or result is float:
		return result != 0
	if result is String:
		return result != ""
	return result != null


static func _compile(s: String) -> Expression:
	if _cache.has(s):
		return _cache[s]
	var e := Expression.new()
	var err := e.parse(s, [])
	if err != OK:
		_report("Condition parse error in `%s`: %s" % [s, e.get_error_text()])
		_cache[s] = null
		return null
	_cache[s] = e
	return e


## Used by the offline validator to surface bad conditions before a player ever hits them.
static func validate(expr: Variant) -> String:
	if expr == null or String(expr).strip_edges() == "":
		return ""
	var e := Expression.new()
	var s := String(expr).strip_edges()
	var err := e.parse(s, [])
	if err != OK:
		return e.get_error_text()
	return ""


static func _report(msg: String) -> void:
	if msg in _errors:
		return
	_errors.append(msg)
	push_error("Condition: " + msg)


static func errors() -> Array[String]:
	return _errors
