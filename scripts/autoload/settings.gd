extends Node
## Autoload "Settings" - persistent player options + input rebinds.
##
## One flat ConfigFile at user://busser_settings.cfg holds audio/controls/video
## prefs plus any keybind overrides. Everything is applied on boot (before the
## first scene reads it) and re-applied the instant a value changes, so the diner
## and the breakroom share one source of truth. Gameplay reads the plain
## properties (e.g. Settings.mouse_sensitivity); UI mutates through the setters,
## which apply + save + emit `changed`.

const CONFIG_PATH := "user://busser_settings.cfg"

## Emitted after any setting changes so open panels/HUDs can refresh live.
signal changed

# --- Defaults (also the reset targets) -------------------------------------
const DEF_MASTER := 1.0
const DEF_MUSIC := 0.8
const DEF_SFX := 1.0
const DEF_AMBIENCE := 0.7
const DEF_MOUSE_SENS := 1.0
const DEF_STICK_SENS := 1.0
const DEF_INVERT_Y := false
const DEF_FULLSCREEN := false

# Sensitivity sliders are multipliers over the busser's base look constants, so
# 1.0 is "stock feel" and the UI can offer a friendly 0.2x .. 3.0x range.
const MOUSE_SENS_MIN := 0.2
const MOUSE_SENS_MAX := 3.0
const STICK_SENS_MIN := 0.2
const STICK_SENS_MAX := 3.0

## Actions the player is allowed to rebind, in display order, paired with the
## label the settings panel shows. Look axes stay fixed (mouse + right stick).
const REBINDABLE := [
	["move_forward", "Move Forward"],
	["move_back", "Move Back"],
	["move_left", "Move Left"],
	["move_right", "Move Right"],
	["jump", "Jump"],
	["sprint", "Sprint"],
	["grab", "Grab / Drop"],
	["throw", "Throw"],
	["interact", "Interact"],
	["pause", "Pause"],
]

# Live values (read directly by gameplay).
var master_volume := DEF_MASTER
var music_volume := DEF_MUSIC
var sfx_volume := DEF_SFX
var ambience_volume := DEF_AMBIENCE
var mouse_sensitivity := DEF_MOUSE_SENS
var stick_sensitivity := DEF_STICK_SENS
var invert_y := DEF_INVERT_Y
var fullscreen := DEF_FULLSCREEN

## The stock event for each rebindable action, captured from the project's
## InputMap on boot BEFORE any overrides are applied, so "reset to defaults"
## always restores the shipped bindings.
var _defaults: Dictionary = {}

func _ready() -> void:
	# Autoloads init before the first scene, so capturing here means the defaults
	# reflect project.godot, never a user override.
	_capture_defaults()
	load_all()

## --- Persistence ----------------------------------------------------------

func load_all() -> void:
	var cfg := ConfigFile.new()
	# Missing file on first launch is fine - we just keep the defaults.
	if cfg.load(CONFIG_PATH) == OK:
		master_volume = clampf(cfg.get_value("audio", "master", DEF_MASTER), 0.0, 1.0)
		music_volume = clampf(cfg.get_value("audio", "music", DEF_MUSIC), 0.0, 1.0)
		sfx_volume = clampf(cfg.get_value("audio", "sfx", DEF_SFX), 0.0, 1.0)
		ambience_volume = clampf(cfg.get_value("audio", "ambience", DEF_AMBIENCE), 0.0, 1.0)
		mouse_sensitivity = clampf(cfg.get_value("controls", "mouse_sensitivity", DEF_MOUSE_SENS), MOUSE_SENS_MIN, MOUSE_SENS_MAX)
		stick_sensitivity = clampf(cfg.get_value("controls", "stick_sensitivity", DEF_STICK_SENS), STICK_SENS_MIN, STICK_SENS_MAX)
		invert_y = bool(cfg.get_value("controls", "invert_y", DEF_INVERT_Y))
		fullscreen = bool(cfg.get_value("video", "fullscreen", DEF_FULLSCREEN))
		_load_keybinds(cfg)
	apply_all()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ambience", ambience_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "stick_sensitivity", stick_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("video", "fullscreen", fullscreen)
	# Only persist bindings that actually diverge from the shipped defaults, so a
	# fresh project change to a default flows through to existing players.
	for pair in REBINDABLE:
		var action: String = pair[0]
		var ev := _primary_event(action)
		if ev != null and not _matches_default(action, ev):
			cfg.set_value("keybinds", action, ev)
	cfg.save(CONFIG_PATH)

## --- Apply ----------------------------------------------------------------

func apply_all() -> void:
	_apply_audio()
	_apply_video()
	changed.emit()

## Push every slider onto its bus. Bus volumes are set ONLY from here, so the
## saved config and what you actually hear can never disagree.
func _apply_audio() -> void:
	_apply_bus(&"Master", master_volume)
	_apply_bus(&"Music", music_volume)
	_apply_bus(&"SFX", sfx_volume)
	_apply_bus(&"Ambience", ambience_volume)

## Mute at zero rather than sending volume to -inf dB, which some drivers treat
## as an audible near-silence. Missing bus = layout drift, warn instead of crash.
func _apply_bus(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("Settings: no audio bus named '%s' (check default_bus_layout.tres)" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	AudioServer.set_bus_mute(idx, linear <= 0.0)

func _apply_video() -> void:
	# Headless (import/soak) has no window to size - guard so autoload boot is safe.
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

## --- Setters (apply + save + notify) --------------------------------------

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save()
	changed.emit()

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save()
	changed.emit()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save()
	changed.emit()

func set_ambience_volume(v: float) -> void:
	ambience_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save()
	changed.emit()

func set_mouse_sensitivity(v: float) -> void:
	mouse_sensitivity = clampf(v, MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	save()
	changed.emit()

func set_stick_sensitivity(v: float) -> void:
	stick_sensitivity = clampf(v, STICK_SENS_MIN, STICK_SENS_MAX)
	save()
	changed.emit()

func set_invert_y(on: bool) -> void:
	invert_y = on
	save()
	changed.emit()

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_video()
	save()
	changed.emit()

## Convenience for movement/look code: +1 normally, -1 when invert-Y is on.
func look_pitch_sign() -> float:
	return -1.0 if invert_y else 1.0

## --- Keybinds -------------------------------------------------------------

func _capture_defaults() -> void:
	for pair in REBINDABLE:
		var action: String = pair[0]
		if not InputMap.has_action(action):
			continue
		# Store a duplicate so a later InputMap edit can't mutate our defaults.
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey or ev is InputEventMouseButton:
				_defaults[action] = ev.duplicate()
				break

func _load_keybinds(cfg: ConfigFile) -> void:
	for pair in REBINDABLE:
		var action: String = pair[0]
		if not cfg.has_section_key("keybinds", action):
			continue
		var ev = cfg.get_value("keybinds", action)
		if ev is InputEvent:
			_set_primary_event(action, ev)

## Replace the keyboard/mouse half of an action's bindings, leaving any joypad
## events intact so a rebind never silently kills controller support.
func _set_primary_event(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey or existing is InputEventMouseButton:
			InputMap.action_erase_event(action, existing)
	InputMap.action_add_event(action, ev)

func _primary_event(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return ev
	return null

func _matches_default(action: String, ev: InputEvent) -> bool:
	if not _defaults.has(action):
		return false
	return _event_label(_defaults[action]) == _event_label(ev)

## Rebind an action to a new keyboard/mouse event, then persist.
func rebind(action: String, ev: InputEvent) -> void:
	_set_primary_event(action, ev)
	save()
	changed.emit()

## Restore every rebindable action to its shipped default (the "RESET ALL
## BINDINGS" button). There is deliberately no per-action reset yet - add one
## here if the settings panel ever grows a per-row revert.
func reset_all_bindings() -> void:
	for pair in REBINDABLE:
		var action: String = pair[0]
		if _defaults.has(action):
			_set_primary_event(action, (_defaults[action] as InputEvent).duplicate())
	save()
	changed.emit()

## Human-readable label for a binding ("W", "SPACE", "MOUSE 1", "-").
func _event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var key := ev as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		# Map physical->logical for the active layout so non-QWERTY keyboards read
		# right; the headless display server can't, so fall back to the raw code.
		if key.physical_keycode != 0 and DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(code)
		return OS.get_keycode_string(code).to_upper()
	elif ev is InputEventMouseButton:
		return "MOUSE %d" % (ev as InputEventMouseButton).button_index
	return "-"

func label_for(action: String) -> String:
	var ev := _primary_event(action)
	return _event_label(ev) if ev != null else "UNBOUND"
