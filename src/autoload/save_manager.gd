extends Node
## Versioned, migration-aware save/load.
##
## The episodic model makes this load-bearing: an Ep1 save written today must still be readable by
## an Ep3 binary shipped a year from now, across app updates. So:
##   - every save carries SAVE_VERSION and is run through _migrate() on load
##   - unknown keys are preserved, never dropped, so a downgrade doesn't destroy data
##   - saves live in user:// (iOS app-container Documents), which survives app updates
##
## There are two kinds of save: the rolling autosave (one per profile, written at scene
## boundaries and checkpoints) and the durable episode record (written once when an episode is
## completed, so Ep2 can read Ep1's outcome even if the player later restarts Ep1).

signal saved(slot: String)
signal loaded(slot: String)
signal save_failed(slot: String, reason: String)

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := "autosave"

## Keys we know about. Anything else found in a save file is carried through untouched.
const KNOWN_KEYS := ["version", "saved_at", "world", "episode_records", "settings"]

var settings: Dictionary = {
	"text_speed": 1.0,
	"skip_seen_text": false,
	"timed_choices": true,   ## accessibility: off makes every timed choice untimed
	"reduce_shake": false,
	"master_volume": 0.9,
}

## episode number (as String key) -> snapshot of WorldState at that episode's end
var episode_records: Dictionary = {}

var _unknown: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# Settings are global to the install, not per-slot, so pull them up front.
	_load_settings()


func _path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


# --- write ------------------------------------------------------------------------------------

func save(slot: String = AUTOSAVE_SLOT) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"world": WorldState.to_dict(),
		"episode_records": episode_records.duplicate(true),
		"settings": settings.duplicate(true),
	}
	# Preserve anything a future version wrote that we don't understand.
	for k in _unknown:
		if not payload.has(k):
			payload[k] = _unknown[k]

	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		var reason := "cannot open %s for write (err %d)" % [_path(slot), FileAccess.get_open_error()]
		push_error("SaveManager: " + reason)
		save_failed.emit(slot, reason)
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	saved.emit(slot)
	return true


func autosave() -> bool:
	return save(AUTOSAVE_SLOT)


## Called when an episode is finished. Freezes that episode's outcome so later episodes can read
## it regardless of what the player does to their rolling save afterwards.
func record_episode_complete(episode: int) -> void:
	episode_records[str(episode)] = WorldState.to_dict()
	save(AUTOSAVE_SLOT)


func episode_record(episode: int) -> Dictionary:
	return episode_records.get(str(episode), {})


# --- read -------------------------------------------------------------------------------------

func has_save(slot: String = AUTOSAVE_SLOT) -> bool:
	return FileAccess.file_exists(_path(slot))


func load_game(slot: String = AUTOSAVE_SLOT) -> bool:
	if not has_save(slot):
		return false
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		save_failed.emit(slot, "cannot open for read")
		return false
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SaveManager: save '%s' is corrupt; refusing to load." % slot)
		save_failed.emit(slot, "corrupt save file")
		return false

	var data: Dictionary = parsed
	data = _migrate(data)

	_unknown.clear()
	for k in data:
		if not k in KNOWN_KEYS:
			_unknown[k] = data[k]

	WorldState.from_dict(data.get("world", {}))
	episode_records = data.get("episode_records", {}).duplicate(true)
	var s: Dictionary = data.get("settings", {})
	for k in s:
		settings[k] = s[k]

	loaded.emit(slot)
	return true


func delete_save(slot: String = AUTOSAVE_SLOT) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(slot)))


## Metadata for a continue button without loading the whole thing into WorldState.
func peek(slot: String = AUTOSAVE_SLOT) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return {}
	var world: Dictionary = parsed.get("world", {})
	return {
		"saved_at": parsed.get("saved_at", ""),
		"episode": world.get("current_episode", 1),
		"scene": world.get("current_scene", ""),
		"choices": (world.get("choice_log", []) as Array).size(),
	}


# --- migration --------------------------------------------------------------------------------

func _migrate(data: Dictionary) -> Dictionary:
	var v: int = int(data.get("version", 0))
	if v > SAVE_VERSION:
		# A newer build wrote this. Load what we recognise rather than refusing outright — the
		# player's Ep1 choices matter more than our version pride.
		push_warning("SaveManager: save version %d is newer than %d; loading best-effort." % [v, SAVE_VERSION])
		return data

	# v0 -> v1: pre-release saves had no rumor verdicts, only a flat list of heard rumor ids.
	if v < 1:
		var world: Dictionary = data.get("world", {})
		var r: Variant = world.get("rumors", {})
		if r is Array:
			var converted := {}
			for id in r:
				converted[String(id)] = {"source": "", "verdict": "unknown"}
			world["rumors"] = converted
			data["world"] = world
		data["version"] = 1

	# Future: if v < 2: ... (and never delete the v<1 block above)
	return data


# --- settings ---------------------------------------------------------------------------------

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_save_settings()


func setting(key: String, default: Variant = null) -> Variant:
	return settings.get(key, default)


func _settings_path() -> String:
	return "%s/settings.json" % SAVE_DIR


func _save_settings() -> void:
	var f := FileAccess.open(_settings_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))
		f.close()


func _load_settings() -> void:
	if not FileAccess.file_exists(_settings_path()):
		return
	var f := FileAccess.open(_settings_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for k in parsed:
			settings[k] = parsed[k]
