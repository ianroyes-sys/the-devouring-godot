class_name Stage
extends Node2D
## The visual layer: parallax backdrop planes, rim-lit character silhouettes, and Telltale-style
## camera framing.
##
## Everything here is driven by stage/shot directives from dialogue data — the Stage never reads
## story state and never decides anything. That keeps "what the scene looks like" fully authored
## in JSON, which is what makes 20+ scenes tractable.
##
## Depth model (art direction §3): planes don't scroll sideways, because a narrative game's camera
## mostly pushes *in*. So parallax is produced by scaling each plane away from the camera by its
## depth factor during a push-in. Near planes swell, far planes barely move. Same perceptual
## payoff as side-scrolling parallax, correct for this camera.

const BASE_SIZE := Vector2(480, 960)

## Where characters stand, as a fraction of viewport width.
const SLOTS := {
	"left": 0.24,
	"center": 0.5,
	"right": 0.76,
	"far_left": 0.10,
	"far_right": 0.90,
}

var palette_id := "CRYPT"
var current_bg := ""

var _plane_root: Node2D
var _planes: Dictionary = {}          ## plane name -> Sprite2D
var _cast_root: Node2D
var _cast: Dictionary = {}            ## who -> Sprite2D
var _fog: ColorRect
var _vignette: ColorRect
var _camera: Camera2D

var _shake_amount := 0.0
var _shake_decay := 4.0
var _cam_home := BASE_SIZE * 0.5
var _focus_who := ""

## Register B (art direction §4): the close-up bust plate. Zooming a 48x96 tableau silhouette to
## 2.2x just gives you eight enormous pixels — a real close-up needs its own artwork, so `close`
## and `insert` framings swap in the character's `bust` sprite instead of relying on camera zoom.
var _plate: Sprite2D
var _plate_layer: CanvasLayer
var _plate_who := ""

## Where a close-up's face lands, as a fraction of screen height. Upper-middle third is the natural
## reading position for a face held at arm's length on a phone.
const EYELINE := 0.34
## Where the head sits inside the bust texture (matches head_cy in tools/gen_art.py `_bust`).
## Positioning by the head rather than the canvas keeps the face on the eyeline at any scale.
const PLATE_HEAD_FRAC := 0.30

signal shot_settled()


func _ready() -> void:
	_plane_root = Node2D.new()
	_plane_root.name = "Planes"
	add_child(_plane_root)

	_cast_root = Node2D.new()
	_cast_root.name = "Cast"
	add_child(_cast_root)

	# Atmospheric wash between planes and cast. Tinted per palette; multiplies toward the
	# palette's mid tone so distance reads as haze rather than as a grey overlay.
	_fog = ColorRect.new()
	_fog.name = "Fog"
	_fog.size = BASE_SIZE * 3.0
	_fog.position = -BASE_SIZE
	_fog.color = Color(0, 0, 0, 0)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.z_index = -1
	add_child(_fog)

	# The plate lives on its own CanvasLayer, not in world space. A close-up portrait must not be
	# dragged around by the stage camera's push-in and pan — it's a framing device, not scenery.
	# Layer 5 keeps it above the backdrop and below PlayScene's UI layer (10), so the dialogue box
	# always covers the plate's shoulders rather than the other way round.
	_plate_layer = CanvasLayer.new()
	_plate_layer.name = "PlateLayer"
	_plate_layer.layer = 5
	add_child(_plate_layer)

	_plate = Sprite2D.new()
	_plate.name = "BustPlate"
	_plate.centered = false
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plate.visible = false
	_plate_layer.add_child(_plate)

	_camera = Camera2D.new()
	_camera.name = "StageCamera"
	_camera.position = _cam_home
	_camera.zoom = Vector2.ONE
	_camera.ignore_rotation = true
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	if _shake_amount > 0.001:
		if SaveManager.setting("reduce_shake", false):
			_shake_amount = 0.0
			_camera.offset = Vector2.ZERO
			return
		_camera.offset = Vector2(
			randf_range(-_shake_amount, _shake_amount),
			randf_range(-_shake_amount, _shake_amount)
		)
		_shake_amount = maxf(0.0, _shake_amount - _shake_decay * delta * _shake_amount)
		if _shake_amount < 0.05:
			_shake_amount = 0.0
			_camera.offset = Vector2.ZERO


# --- stage directives -------------------------------------------------------------------------

func apply_directive(d: Dictionary) -> void:
	if d.has("bg"):
		set_backdrop(String(d["bg"]), String(d.get("palette", "")))
	elif d.has("palette"):
		set_palette(String(d["palette"]))

	if d.has("cast"):
		set_cast(d["cast"])

	for entry in d.get("enter", []):
		if entry is Dictionary:
			add_character(String(entry.get("who", "")), String(entry.get("at", "center")), true)
		elif entry is String:
			add_character(String(entry), "center", true)

	for who in d.get("exit", []):
		remove_character(String(who), true)

	if d.has("glow"):
		set_glow(String(d["glow"]), true)
	if d.has("unglow"):
		set_glow(String(d["unglow"]), false)

	if d.has("bed"):
		AudioDirector.play_bed(String(d["bed"]))
	if d.has("pulse"):
		AudioDirector.set_pulse(String(d["pulse"]), float(d.get("intensity", 1.0)))

	if d.has("shake"):
		shake(float(d["shake"]))


func set_backdrop(bg_id: String, palette_override: String = "") -> void:
	if bg_id == current_bg and palette_override == "":
		return
	current_bg = bg_id

	for child in _planes.values():
		child.queue_free()
	_planes.clear()

	var pal := palette_override
	if pal == "":
		pal = ArtRegistry.backdrop_palette(bg_id)
	set_palette(pal)

	var planes := ArtRegistry.backdrop_planes(bg_id)
	for i in planes.size():
		var plane_name := String(planes[i])
		var tex := ArtRegistry.backdrop_texture(bg_id, plane_name)
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.name = "Plane_%s" % plane_name
		s.texture = tex
		s.centered = false
		s.position = Vector2.ZERO
		s.z_index = -100 + i * 5
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_plane_root.add_child(s)
		_planes[plane_name] = s

	_refresh_parallax()


func set_palette(id: String) -> void:
	palette_id = id
	# Haze toward the palette's third ramp entry at low alpha — enough to unify planes without
	# flattening them.
	var haze := ArtRegistry.ramp_color(id, 2)
	haze.a = 0.10
	var tw := create_tween()
	tw.tween_property(_fog, "color", haze, 0.8)


func set_cast(list: Array) -> void:
	var wanted: Array = []
	for w in list:
		wanted.append(String(w))
	for who in _cast.keys():
		if not who in wanted:
			remove_character(who, false)
	# Spread the cast across slots so a 3-hander doesn't pile up in the centre.
	var slot_order := ["center"] if wanted.size() == 1 else (["left", "right"] if wanted.size() == 2 else ["far_left", "center", "far_right"])
	for i in wanted.size():
		var slot: String = slot_order[i] if i < slot_order.size() else "center"
		add_character(wanted[i], slot, false)


func add_character(who: String, slot: String = "center", animate: bool = true) -> void:
	if who == "" or who == "narrator":
		return
	if _cast.has(who):
		_place(_cast[who], slot)
		return

	var tex := ArtRegistry.character_texture(who, "full")
	if tex == null:
		return

	var s := Sprite2D.new()
	s.name = "Cast_%s" % who
	s.texture = tex
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = 10
	_cast_root.add_child(s)
	_cast[who] = s
	_place(s, slot)

	if animate:
		s.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(s, "modulate:a", 1.0, 0.5)


func remove_character(who: String, animate: bool = true) -> void:
	if not _cast.has(who):
		return
	var s: Sprite2D = _cast[who]
	_cast.erase(who)
	if not animate:
		s.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.4)
	tw.tween_callback(s.queue_free)


func _place(s: Sprite2D, slot: String) -> void:
	var frac: float = SLOTS.get(slot, 0.5)
	var tex_size: Vector2 = s.texture.get_size()
	# Characters stand on a ground line at 78% of frame height — matches where the reference
	# board consistently puts its horizon.
	s.position = Vector2(
		roundf(BASE_SIZE.x * frac - tex_size.x * 0.5),
		roundf(BASE_SIZE.y * 0.78 - tex_size.y)
	)
	s.set_meta("slot", slot)


## The magic override: a Marked character is lit by a colour the scene doesn't own.
func set_glow(who: String, on: bool) -> void:
	if not _cast.has(who):
		return
	var s: Sprite2D = _cast[who]
	var target := Color.WHITE
	if on:
		target = ArtRegistry.color(ArtRegistry.MAGIC_GLOW_HI)
		target = target.lerp(Color.WHITE, 0.35)
	var tw := create_tween()
	tw.tween_property(s, "modulate", target, 0.9)
	if on:
		# Slow breathing pulse so the glow reads as alive and uncontrolled, not as a UI highlight.
		var pulse := create_tween().set_loops()
		pulse.tween_property(s, "self_modulate:a", 0.82, 1.3).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(s, "self_modulate:a", 1.0, 1.3).set_trans(Tween.TRANS_SINE)
		s.set_meta("glow_tween", pulse)
	elif s.has_meta("glow_tween"):
		var t: Tween = s.get_meta("glow_tween")
		if t and t.is_valid():
			t.kill()
		s.self_modulate.a = 1.0


# --- camera / shots ---------------------------------------------------------------------------

func apply_shot(shot: Dictionary) -> void:
	var framing := String(shot.get("framing", "wide"))
	var focus := String(shot.get("focus", ""))
	var dur := float(shot.get("hold", 0.55))

	_focus_who = focus

	# Close registers use a bust plate, not camera zoom. The camera still creeps in a little so the
	# parallax planes shift and the push reads as a push, but not far enough to reveal big pixels.
	var is_plate := (framing == "close" or framing == "insert") and focus != ""
	if is_plate:
		_show_plate(focus, framing, dur)
	else:
		_hide_plate(dur)

	var zoom: float = ArtRegistry.framing_zoom(framing)
	if is_plate:
		zoom = 1.18 if framing == "close" else 1.32

	var target := _cam_home
	if focus != "" and _cast.has(focus):
		var s: Sprite2D = _cast[focus]
		var c: Vector2 = s.position + s.texture.get_size() * Vector2(0.5, 0.35)
		# Blend toward the subject rather than centring hard on it, so tight framings still keep
		# some environment in frame — the board's whole appeal is the environment.
		var blend: float = 0.35 if framing == "wide" else (0.7 if framing == "mid" else 0.85)
		target = _cam_home.lerp(c, blend)

	# Keep the camera inside the backdrop so a push-in never reveals the void.
	var half := BASE_SIZE * 0.5 / zoom
	target.x = clampf(target.x, half.x, BASE_SIZE.x - half.x)
	target.y = clampf(target.y, half.y, BASE_SIZE.y - half.y)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_camera, "zoom", Vector2(zoom, zoom), dur) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_camera, "position", target, dur) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(func():
		_refresh_parallax()
		shot_settled.emit()
	)
	# Update parallax continuously through the move, not just at the end.
	var driver := create_tween()
	driver.tween_method(func(_v: float): _refresh_parallax(), 0.0, 1.0, dur)


## Push each plane away from centre in proportion to its depth and the current zoom. At zoom 1.0
## this is a no-op, so wide shots show the art exactly as painted.
func _refresh_parallax() -> void:
	var zoom: float = _camera.zoom.x
	var excess: float = zoom - 1.0
	for plane_name in _planes:
		var s: Sprite2D = _planes[plane_name]
		var depth: float = ArtRegistry.PLANE_DEPTH.get(plane_name, 0.5)
		var scale_factor: float = 1.0 + excess * depth * 0.16
		s.scale = Vector2(scale_factor, scale_factor)
		# Keep the plane's centre pinned while it swells.
		var grown: Vector2 = BASE_SIZE * (scale_factor - 1.0)
		s.position = -grown * 0.5


## Slide the focus character's bust in from the side they're standing on, so a close-up doesn't
## teleport them across the frame. The plate sits above the backdrop and below the dialogue box.
func _show_plate(who: String, framing: String, dur: float) -> void:
	var tex := ArtRegistry.character_texture(who, "bust")
	if tex == null:
		_hide_plate(dur)
		return

	var scale_factor: float = 2.0 if framing == "close" else 2.6
	var size: Vector2 = tex.get_size() * scale_factor

	# Which side of frame are they on? Keep them there — a close-up must not teleport the speaker
	# across the frame, or the player loses track of who is where.
	var from_right := true
	if _cast.has(who):
		var s: Sprite2D = _cast[who]
		from_right = (s.position.x + s.texture.get_size().x * 0.5) > BASE_SIZE.x * 0.5

	# Only a slight lateral bias: at this scale the bust is nearly frame-width, so pushing it far
	# to one side would crop the face rather than the shoulder.
	var centre_x: float = BASE_SIZE.x * (0.56 if from_right else 0.44)
	var rest_x: float = centre_x - size.x * 0.5
	# Position by the *head*, not the canvas: put the face at EYELINE regardless of scale, and let
	# the torso run down behind the dialogue panel.
	var rest_y: float = BASE_SIZE.y * EYELINE - PLATE_HEAD_FRAC * size.y

	var changed := who != _plate_who
	_plate_who = who
	_plate.texture = tex
	_plate.scale = Vector2(scale_factor, scale_factor)
	_plate.visible = true

	if changed:
		_plate.position = Vector2(rest_x + (26.0 if from_right else -26.0), rest_y)
		_plate.modulate.a = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_plate, "position", Vector2(roundf(rest_x), roundf(rest_y)), maxf(0.25, dur)) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_plate, "modulate:a", 1.0, 0.3)


func _hide_plate(dur: float) -> void:
	if not _plate.visible:
		return
	_plate_who = ""
	var tw := create_tween()
	tw.tween_property(_plate, "modulate:a", 0.0, minf(0.3, maxf(0.15, dur)))
	tw.tween_callback(func(): _plate.visible = false)


func shake(amount: float) -> void:
	_shake_amount = maxf(_shake_amount, amount * 6.0)


func reset_camera(dur: float = 0.6) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_camera, "zoom", Vector2.ONE, dur)
	tw.tween_property(_camera, "position", _cam_home, dur)
