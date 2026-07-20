extends Node
## Autoload "Audio" - one-shot sound playback.
##
## Gameplay code never creates AudioStreamPlayers; it calls Audio.play_3d() or
## Audio.play_ui() with a sound id. This keeps the player pool, bus routing, and
## pitch variation in one place instead of scattered across every prop.
##
## NETWORKING: audio needs NO new RPCs. Dish/tub/machine state is already
## replicated, so every peer observes the same transitions and plays the sound
## locally off its own copy of the state - the same "derive it, don't replicate
## it" rule the money readout follows. If you find yourself wanting to RPC a
## sound, the state driving it is probably what should be replicated instead.
##
## The sounds in assets/audio/ are synthesized PLACEHOLDERS (see
## tools/gen_placeholder_audio.py). Swap any file in place, keep the filename.

## Pooled 3D voices. Beyond this, the quietest/oldest voice is recycled - a
## dropped stack of plates should not spawn a node per plate.
const POOL_SIZE := 24
const DEFAULT_MAX_DISTANCE := 22.0

## Sound library. Keys are what gameplay code passes to play_3d/play_ui.
const SOUNDS := {
	&"grab": "res://assets/audio/grab.wav",
	&"drop": "res://assets/audio/drop.wav",
	&"clatter_light": "res://assets/audio/clatter_light.wav",
	&"clatter_mid": "res://assets/audio/clatter_mid.wav",
	&"clatter_heavy": "res://assets/audio/clatter_heavy.wav",
	&"shatter": "res://assets/audio/shatter.wav",
	&"tub_scoop": "res://assets/audio/tub_scoop.wav",
	&"tub_down": "res://assets/audio/tub_down.wav",
	&"plate_to_pit": "res://assets/audio/plate_to_pit.wav",
	&"machine_loop": "res://assets/audio/machine_loop.wav",
	&"machine_done": "res://assets/audio/machine_done.wav",
	&"chef_bark": "res://assets/audio/chef_bark.wav",
	&"plate_served": "res://assets/audio/plate_served.wav",
	&"ambience_loop": "res://assets/audio/ambience_loop.wav",
	&"ui_click": "res://assets/audio/ui_click.wav",
}

## Sounds that must loop seamlessly. Set here rather than in each .import file
## so the loop points live next to the library they belong to.
const LOOPING := [&"machine_loop", &"ambience_loop"]

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _ui_player: AudioStreamPlayer
var _warned: Dictionary = {}
## Cleared by silence() so nothing new starts while the tree is being torn down.
var _accepting := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # pausing is client-local; sound keeps running
	_load_library()
	_build_pool()

func _load_library() -> void:
	for id in SOUNDS:
		var path: String = SOUNDS[id]
		if not ResourceLoader.exists(path):
			# Missing audio is a content gap, not a crash. The game stays playable
			# and silent, which is what you want mid-asset-swap.
			push_warning("Audio: missing stream for '%s' at %s" % [id, path])
			continue
		var stream := load(path) as AudioStream
		if stream is AudioStreamWAV and id in LOOPING:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		_streams[id] = stream

func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.max_distance = DEFAULT_MAX_DISTANCE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = &"SFX"
	add_child(_ui_player)

func has_sound(id: StringName) -> bool:
	return _streams.has(id)

## Grab a free voice, or steal the one that has been playing longest. Stealing
## beats dropping the sound: a smashed plate should always be audible.
func _free_voice() -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = null
	var oldest_pos := -1.0
	for p in _pool:
		if not p.playing:
			return p
		var pos := p.get_playback_position()
		if pos > oldest_pos:
			oldest_pos = pos
			oldest = p
	return oldest

func _stream_for(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	if not _warned.has(id):
		_warned[id] = true
		push_warning("Audio: no sound registered for '%s'" % id)
	return null

## Play a one-shot in the world. `pitch_jitter` de-machine-guns repeated sounds
## (a stack of plates hitting the counter should not be one sample six times).
func play_3d(id: StringName, position: Vector3, volume_db: float = 0.0,
		pitch: float = 1.0, pitch_jitter: float = 0.08) -> void:
	if not _accepting:
		return
	var stream := _stream_for(id)
	if stream == null:
		return
	var voice := _free_voice()
	if voice == null:
		return
	voice.stream = stream
	voice.global_position = position
	voice.volume_db = volume_db
	voice.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_jitter, pitch_jitter))
	voice.play()

## Non-positional one-shot for menus and HUD.
func play_ui(id: StringName, volume_db: float = 0.0) -> void:
	if not _accepting:
		return
	var stream := _stream_for(id)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()

## Cut every pooled voice immediately. Call this on scene transitions so a plate
## that smashed on the last frame does not ring out over the main menu. Owned
## loops (make_loop_3d) are not pooled, so they die with their parent.
## Clearing `stream` as well as stopping matters: a stopped voice still holds a
## reference to its stream (and the audio server its playback), which shows up
## as a leak if the tree is torn down straight afterwards.
func stop_all() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	if _ui_player != null:
		_ui_player.stop()
		_ui_player.stream = null

## Stop everything AND refuse new playback from here on.
##
## Use this when the tree is about to be torn down (quitting, or a headless
## harness finishing). stop_all() alone is not enough: teardown itself churns
## dish state and machine flags, so fresh one-shots start during the frames
## between the stop and the actual exit, and any voice still playing when the
## tree dies leaks its stream and playback.
func silence() -> void:
	_accepting = false
	stop_all()

## Build a dedicated looping voice (machine hum, room tone). Loops are owned by
## the prop that emits them, not by the shared one-shot pool, so they can be
## started and stopped independently.
func make_loop_3d(id: StringName, parent: Node3D, volume_db: float = 0.0,
		bus: StringName = &"SFX") -> AudioStreamPlayer3D:
	if not _accepting:
		return null
	var stream := _stream_for(id)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	p.max_distance = DEFAULT_MAX_DISTANCE
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	return p
