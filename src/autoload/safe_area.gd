extends Node
## Keeps UI out of the notch, the Dynamic Island, and the home-indicator gesture zone.
##
## Why this is needed at all: the project uses `canvas_items` stretch with `expand` aspect, so on a
## 19.5:9 iPhone the 480x960 design viewport becomes roughly 480x1040 — the extra height is real
## screen the game gets for free. Anything anchored to the bottom therefore lands *at the physical
## bottom edge*, which on a modern iPhone is underneath the home indicator, where a swipe-up dismisses
## the app instead of picking a dialogue option. The top is the same story with the Island.
##
## `DisplayServer.get_display_safe_area()` reports the safe rect in physical pixels. UI works in
## canvas units, so the insets are converted by the stretch scale before use.
##
## Usage: `SafeArea.apply(control)` in a UI root's `_ready()`. It sets full-rect anchors with inset
## offsets and re-applies whenever the window changes, so rotation and Split View stay correct.

signal changed()

## Extra breathing room beyond Apple's reported safe area, in canvas units. The reported bottom inset
## is the indicator itself; a few more pixels stop a thumb resting on the last option from
## triggering the system gesture.
const EXTRA_BOTTOM := 6.0
const EXTRA_TOP := 2.0

var _insets := Vector4.ZERO
var _registered: Array[Control] = []


func _ready() -> void:
	get_window().size_changed.connect(_recompute)
	_recompute()


## left, top, right, bottom — in canvas units.
func insets() -> Vector4:
	return _insets


func apply(control: Control) -> void:
	if control == null:
		return
	if not control in _registered:
		_registered.append(control)
		control.tree_exiting.connect(func(): _registered.erase(control))
	_apply_one(control)


func _apply_one(control: Control) -> void:
	if not is_instance_valid(control):
		return
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.offset_left = _insets.x
	control.offset_top = _insets.y
	control.offset_right = -_insets.z
	control.offset_bottom = -_insets.w


func _recompute() -> void:
	var before := _insets
	_insets = _compute()
	for c in _registered:
		_apply_one(c)
	if before != _insets:
		changed.emit()


func _compute() -> Vector4:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4.ZERO

	var safe: Rect2i = DisplayServer.get_display_safe_area()
	# On desktop (and in some simulator states) the safe area is reported as the whole screen, or as
	# a rect that doesn't correspond to this window at all. Treat anything implausible as "no insets"
	# rather than guessing, so a bad report can't shove the UI into the middle of the screen.
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO

	var l := float(maxi(0, safe.position.x))
	var t := float(maxi(0, safe.position.y))
	var r := float(maxi(0, win.x - (safe.position.x + safe.size.x)))
	var b := float(maxi(0, win.y - (safe.position.y + safe.size.y)))

	# Sanity clamp: no single inset should ever eat more than a fifth of the screen.
	var max_h := float(win.x) * 0.2
	var max_v := float(win.y) * 0.2
	l = minf(l, max_h)
	r = minf(r, max_h)
	t = minf(t, max_v)
	b = minf(b, max_v)

	# Physical pixels -> canvas units.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var sx: float = vp.x / float(win.x)
	var sy: float = vp.y / float(win.y)

	var out := Vector4(l * sx, t * sy, r * sx, b * sy)
	if out.y > 0.0:
		out.y += EXTRA_TOP
	if out.w > 0.0:
		out.w += EXTRA_BOTTOM
	return out
