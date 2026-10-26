extends Node
## Ambient beds, stings, and UI ticks.
##
## The brief puts extra weight here because there's no voice acting — atmosphere is carried
## entirely by sound. So the model is:
##   BED   : one looping ambient layer per location, crossfaded on scene change (never cut)
##   PULSE : a second looping layer for tension that can be faded in/out independently, so a
##           scene can get scarier without changing location
##   STING : one-shots for reveals, hits, magic, and the remember-toast
##
## Missing files degrade to silence with a warning rather than crashing, so content can reference
## audio that hasn't been produced yet.

const BUS_MASTER := "Master"

const BEDS := {
	"battlefield": "res://assets/audio/bed_battlefield.wav",
	"wind": "res://assets/audio/bed_wind.wav",
	"cave": "res://assets/audio/bed_cave.wav",
	"forest": "res://assets/audio/bed_forest.wav",
}

const PULSES := {
	"dread": "res://assets/audio/pulse_dread.wav",
	"heartbeat": "res://assets/audio/pulse_heartbeat.wav",
}

const STINGS := {
	"magic": "res://assets/audio/sting_magic.wav",
	"reveal": "res://assets/audio/sting_reveal.wav",
	"impact": "res://assets/audio/sting_impact.wav",
	"remember": "res://assets/audio/sting_remember.wav",
	"tick": "res://assets/audio/ui_tick.wav",
	"select": "res://assets/audio/ui_select.wav",
}

const FADE := 1.4
const SILENT_DB := -60.0

var _bed: AudioStreamPlayer
var _pulse: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []

var _current_bed := ""
var _current_pulse := ""
var _cache: Dictionary = {}


func _ready() -> void:
	_bed = _make_player("Bed", -8.0)
	_pulse = _make_player("Pulse", SILENT_DB)
	# A small pool so overlapping stings don't cut each other off.
	for i in 4:
		var p := _make_player("OneShot%d" % i, -4.0)
		_oneshots.append(p)

	Notifier.toast_shown.connect(func(_who): sting("remember"))


func _make_player(n: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.volume_db = db
	p.bus = BUS_MASTER
	add_child(p)
	return p


func _stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_warning("AudioDirector: missing audio '%s' — playing silence." % path)
		_cache[path] = null
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD if path.contains("bed_") or path.contains("pulse_") else AudioStreamWAV.LOOP_DISABLED
		if s.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			s.loop_end = s.data.size() / (4 if s.stereo else 2)
	_cache[path] = s
	return s


# --- beds -------------------------------------------------------------------------------------

func play_bed(id: String, fade: float = FADE) -> void:
	if id == _current_bed:
		return
	_current_bed = id
	if id == "":
		_fade_out(_bed, fade)
		return
	var path: String = BEDS.get(id, "")
	if path == "":
		push_warning("AudioDirector: unknown bed '%s'" % id)
		return
	var s := _stream(path)
	if s == null:
		return
	await _crossfade(_bed, s, fade, -8.0)


func _crossfade(player: AudioStreamPlayer, next: AudioStream, dur: float, target_db: float) -> void:
	if player.playing:
		var out := create_tween()
		out.tween_property(player, "volume_db", SILENT_DB, dur * 0.5)
		await out.finished
	player.stream = next
	player.volume_db = SILENT_DB
	player.play()
	var tw := create_tween()
	tw.tween_property(player, "volume_db", target_db, dur * 0.5)


func _fade_out(player: AudioStreamPlayer, dur: float) -> void:
	if not player.playing:
		return
	var tw := create_tween()
	tw.tween_property(player, "volume_db", SILENT_DB, dur)
	await tw.finished
	player.stop()


# --- tension pulse ----------------------------------------------------------------------------

## intensity 0.0 (silent) .. 1.0 (full). Lets a scene ratchet dread without changing location.
func set_pulse(id: String, intensity: float, fade: float = 1.0) -> void:
	if id != _current_pulse and id != "":
		var path: String = PULSES.get(id, "")
		var s := _stream(path)
		if s == null:
			return
		_current_pulse = id
		_pulse.stream = s
		_pulse.volume_db = SILENT_DB
		_pulse.play()

	var target: float = SILENT_DB if intensity <= 0.001 else lerpf(-26.0, -6.0, clampf(intensity, 0.0, 1.0))
	var tw := create_tween()
	tw.tween_property(_pulse, "volume_db", target, fade)
	if intensity <= 0.001:
		_current_pulse = ""
		await tw.finished
		_pulse.stop()


# --- one-shots --------------------------------------------------------------------------------

func sting(id: String, pitch_variance: float = 0.06) -> void:
	var path: String = STINGS.get(id, "")
	if path == "":
		return
	var s := _stream(path)
	if s == null:
		return
	for p in _oneshots:
		if not p.playing:
			p.stream = s
			p.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
			p.play()
			return
	# All busy — steal the first.
	_oneshots[0].stream = s
	_oneshots[0].play()


func stop_all(fade: float = 0.8) -> void:
	_current_bed = ""
	_current_pulse = ""
	_fade_out(_bed, fade)
	_fade_out(_pulse, fade)
