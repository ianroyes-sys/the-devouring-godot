class_name QteWidget
extends Control
## Touch-native quick-time events: tap, rapid_tap, hold, swipe.
##
## iOS-specific choices:
##   - The target is a large centred ring, comfortably inside thumb reach and far from the screen
##     edges where iOS system gestures live. No corner targets, ever.
##   - Every kind accepts input anywhere on screen except the ring's own miss zone, because a
##     panicking player does not aim.
##   - Failure is never silent: the ring flashes red and the caption changes before the runtime is
##     told, so the player learns what the verb was even when they lose.
##
## Per docs/DIALOGUE_FORMAT.md, failing a QTE in Episode 1 costs state, never a life.

signal resolved(success: bool)

const RING_RADIUS := 92.0
const SWIPE_MIN_DISTANCE := 70.0
## Fallback design width, used only before the first real layout pass.
const BASE_W := 480.0

var palette_id := "CRYPT"

var _kind := "tap"
var _duration := 2.5
var _target_taps := 10
var _direction := "right"

var _time_left := 0.0
var _active := false
var _done := false
var _taps := 0
var _holding := false
var _hold_progress := 0.0
var _swipe_start := Vector2.ZERO
var _swipe_tracking := false

var _ring: Control
var _caption: Label
var _hint: Label
var _catcher: Control
var _flash: ColorRect


func _ready() -> void:
	SafeArea.apply(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SafeArea.changed.connect(_layout)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_catcher = Control.new()
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_input)
	add_child(_catcher)

	# Explicit rects, deliberately *not* anchor presets: a preset recomputes offsets on every layout
	# pass and silently discards a manually-set size, which is how the caption ends up clipped to
	# "GET H". Positions are recomputed in _layout() from this control's real rect rather than from
	# the 480x960 design constants, because `expand` aspect means the actual viewport is taller on a
	# 19.5:9 phone and the safe-area inset shrinks it again.
	var ring_d := RING_RADIUS * 2 + 24

	_ring = Control.new()
	_ring.custom_minimum_size = Vector2(ring_d, ring_d)
	_ring.size = Vector2(ring_d, ring_d)
	_ring.pivot_offset = Vector2(ring_d, ring_d) * 0.5
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)

	_caption = UiKit.label("", 26, UiKit.INK)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	_hint = UiKit.label("", UiKit.SIZE_SMALL, UiKit.INK_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	resized.connect(_layout)
	_layout()
	hide()


## Centre the target on whatever rect we actually have. Kept in one place so a rotation, a
## safe-area change, and first layout all go through identical maths.
func _layout() -> void:
	if _ring == null:
		return
	var rect: Vector2 = size
	if rect.x <= 1.0 or rect.y <= 1.0:
		rect = Vector2(BASE_W, 960.0)
	var ring_d: float = RING_RADIUS * 2 + 24
	# Slightly above centre: leaves room for the caption above and the hint below.
	var cy: float = rect.y * 0.45
	_ring.position = Vector2(rect.x * 0.5 - ring_d * 0.5, cy - ring_d * 0.5)
	_caption.position = Vector2(0, cy - RING_RADIUS - 74)
	_caption.size = Vector2(rect.x, 40)
	_hint.position = Vector2(0, cy + RING_RADIUS + 34)
	_hint.size = Vector2(rect.x, 24)


func set_palette(id: String) -> void:
	palette_id = id
	_ring.queue_redraw()


func begin(node: Dictionary) -> void:
	_kind = String(node.get("kind", "tap"))
	_duration = float(node.get("duration", 2.5))
	_target_taps = int(node.get("target", 10))
	_direction = String(node.get("direction", "right"))

	_time_left = _duration
	_taps = 0
	_hold_progress = 0.0
	_holding = false
	_swipe_tracking = false
	_done = false
	_active = true

	_caption.text = String(node.get("caption", _default_caption()))
	_hint.text = _hint_for_kind()

	show()
	_ring.scale = Vector2(0.7, 0.7)
	_ring.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_ring, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ring, "modulate:a", 1.0, 0.15)
	AudioDirector.sting("tick")


func _default_caption() -> String:
	match _kind:
		"rapid_tap": return "TAP"
		"hold": return "HOLD"
		"swipe": return "SWIPE"
		_: return "NOW"


func _hint_for_kind() -> String:
	match _kind:
		"rapid_tap": return "tap fast"
		"hold": return "press and hold"
		"swipe": return "swipe %s" % _direction
		_: return "tap"


func _process(delta: float) -> void:
	if not _active or _done:
		return

	if _kind == "hold":
		if _holding:
			_hold_progress = minf(1.0, _hold_progress + delta / _duration)
			if _hold_progress >= 1.0:
				_finish(true)
				return
		else:
			# Bleeds back down rather than resetting, so a momentary slip is recoverable.
			_hold_progress = maxf(0.0, _hold_progress - delta * 0.7)
		_ring.queue_redraw()
		return

	_time_left -= delta
	_ring.queue_redraw()
	if _time_left <= 0.0:
		_finish(_kind == "rapid_tap" and _taps >= _target_taps)


func _on_input(event: InputEvent) -> void:
	if not _active or _done:
		return

	var down: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	var up: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
		or (event is InputEventScreenTouch and not event.pressed)

	match _kind:
		"tap":
			if down:
				_finish(true)
		"rapid_tap":
			if down:
				_taps += 1
				_pop()
				AudioDirector.sting("tick", 0.14)
				if _taps >= _target_taps:
					_finish(true)
		"hold":
			if down:
				_holding = true
			elif up:
				_holding = false
		"swipe":
			if down:
				_swipe_start = _event_pos(event)
				_swipe_tracking = true
			elif up and _swipe_tracking:
				_swipe_tracking = false
				var delta_v: Vector2 = _event_pos(event) - _swipe_start
				_finish(_matches_direction(delta_v))


func _event_pos(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return event.position
	if event is InputEventMouseButton:
		return event.position
	return Vector2.ZERO


func _matches_direction(d: Vector2) -> bool:
	if d.length() < SWIPE_MIN_DISTANCE:
		return false
	match _direction:
		"left": return d.x < 0 and absf(d.x) > absf(d.y)
		"right": return d.x > 0 and absf(d.x) > absf(d.y)
		"up": return d.y < 0 and absf(d.y) > absf(d.x)
		"down": return d.y > 0 and absf(d.y) > absf(d.x)
	return false


func _pop() -> void:
	var tw := create_tween()
	tw.tween_property(_ring, "scale", Vector2(1.09, 1.09), 0.05)
	tw.tween_property(_ring, "scale", Vector2.ONE, 0.09)


func _finish(success: bool) -> void:
	if _done:
		return
	_done = true
	_active = false

	if success:
		AudioDirector.sting("impact")
		_flash.color = ArtRegistry.accent_hi(palette_id)
		_flash.color.a = 0.28
	else:
		_caption.text = "TOO SLOW" if _kind != "swipe" else "MISSED"
		_caption.add_theme_color_override("font_color", Color(0.78, 0.24, 0.22))
		_flash.color = Color(0.55, 0.09, 0.09, 0.34)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_flash, "color:a", 0.0, 0.45)
	tw.tween_property(_ring, "modulate:a", 0.0, 0.3)
	tw.tween_property(_caption, "modulate:a", 0.0, 0.4).set_delay(0.25)
	await tw.finished

	hide()
	_caption.add_theme_color_override("font_color", UiKit.INK)
	_caption.modulate.a = 1.0
	resolved.emit(success)


# --- drawing ----------------------------------------------------------------------------------

func _draw_ring() -> void:
	var c: Vector2 = _ring.size * 0.5
	var accent := ArtRegistry.accent(palette_id)
	var track := accent
	track.a = 0.18

	# Track
	_ring.draw_arc(c, RING_RADIUS, 0, TAU, 72, track, 5.0)

	var progress := 0.0
	match _kind:
		"hold":
			progress = _hold_progress
		"rapid_tap":
			progress = float(_taps) / maxf(1.0, float(_target_taps))
		_:
			progress = clampf(_time_left / maxf(0.01, _duration), 0.0, 1.0)

	if progress > 0.0:
		var col := accent
		if _kind != "hold" and _kind != "rapid_tap" and progress < 0.34:
			col = Color(0.78, 0.24, 0.22)
		_ring.draw_arc(c, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * progress, 72, col, 5.0)

	# Inner fill hints at the safe target area for tap kinds.
	var inner := accent
	inner.a = 0.07
	_ring.draw_circle(c, RING_RADIUS - 8.0, inner)

	if _kind == "rapid_tap":
		var remaining := maxi(0, _target_taps - _taps)
		var f := UiKit.font()
		var fs := 30
		var txt := str(remaining)
		var w := 16.0 * float(txt.length())
		if f:
			_ring.draw_string(f, c + Vector2(-w * 0.5, 11), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, ArtRegistry.accent_hi(palette_id))
		else:
			var df := ThemeDB.fallback_font
			_ring.draw_string(df, c + Vector2(-w * 0.5, 11), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, ArtRegistry.accent_hi(palette_id))
