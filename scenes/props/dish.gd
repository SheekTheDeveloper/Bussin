class_name Dish
extends RigidBody3D
## One plate in the conserved dish pool. Every dish is always in exactly one
## state; the whole game economy is this state machine:
##   CLEAN -> AT_PASS -> COOKING -> SERVED -> DIRTY -> AT_PIT -> WASHING -> CLEAN
## plus HELD (in a busser's hands) and BROKEN (pool permanently shrinks).
## Server simulates physics + owns state; clients freeze their local body and
## receive position/rotation/state through the MultiplayerSynchronizer.

enum State { DIRTY, HELD, AT_PIT, WASHING, CLEAN, BROKEN, AT_PASS, COOKING, SERVED }

## Impact speed above which a plate shatters. Sits above what a gently lobbed
## plate is doing when it lands (about 6.8 m/s falling to the floor from hand
## height) and below a fully charged throw (11 m/s), so a pass survives and a
## deliberate yeet does not. Retuned from 6.0, which every throw exceeded.
const BREAK_SPEED := 7.5

## A thrower cannot re-catch its own plate for this long, or a throw would land
## straight back in your hands on the next frame.
const CATCH_BLOCK_MS := 250

## What each state LOOKS like: which visual parts are shown, and an optional
## tint for the plate body.
##
## The rule: states the player reads at a glance across the room get real
## geometry (grime on a dirty plate, food on a served one, shards on a broken
## one). States that are brief and read from LOCATION instead - it is in the
## machine, it is on the pass - keep a tint, which costs no art. As real meshes
## land, drop the tint from that row; nothing else has to change.
##
## Parts are resolved by name against the Visuals subtree and missing ones are
## skipped, so this table can name art that does not exist yet.
const STATE_PARTS := {
	State.CLEAN:   {"parts": ["Body"]},
	State.AT_PASS: {"parts": ["Body"], "tint": Color(0.85, 0.9, 0.95)},
	State.COOKING: {"parts": ["Body", "Food"], "tint": Color(0.95, 0.45, 0.15)},
	State.SERVED:  {"parts": ["Body", "Food"]},
	State.DIRTY:   {"parts": ["Body", "Grime"]},
	State.HELD:    {"parts": ["Body", "Grime"]},
	State.AT_PIT:  {"parts": ["Body", "Grime"], "tint": Color(0.78, 0.52, 0.2)},
	State.WASHING: {"parts": ["Body"], "tint": Color(0.35, 0.55, 0.9)},
	State.BROKEN:  {"parts": ["Shards"], "tint": Color(0.18, 0.18, 0.18)},
}

## HELD keeps whatever the plate already looked like, so picking a clean plate up
## does not make it look dirty in your hands. Resolved at apply time from the
## state it was in before the pickup.
const HELD_FOLLOWS_PREVIOUS := true

## The state a scene-placed dish starts in. Plates pre-staged on the clean
## counter want CLEAN; loose dirties on a table want DIRTY (the default).
@export var start_state: State = State.DIRTY

const STACK_STEP := 0.05             # vertical gap between plates in a hand-stack

var state: int = State.DIRTY: set = _set_state
var holder: Busser = null            # server-side only
var in_tub: BusTub = null            # server-side only; set while stowed in a tub
var hold_index := 0                  # server-side only; height in the holder's stack
var _state_before_hold: int = State.DIRTY
var _thrown_by: Busser = null       # server-side; who launched it
var _catch_block_until: int = 0     # server-side; ms ticks

@onready var visuals := get_node_or_null("Visuals") as DishVisuals
@onready var shape := $Shape as CollisionShape3D

## How far this vessel's origin sits above its base, taken from its own
## collider. Placement code positions the SURFACE and each dish lifts itself by
## this, so a tall glass and a flat plate both rest ON a counter instead of a
## plate-shaped guess sinking the glass and floating nothing.
var base_offset: float = 0.0

var _col_layer := 1
var _col_mask := 1

func _ready() -> void:
	_col_layer = collision_layer
	_col_mask = collision_mask
	var cyl := shape.shape as CylinderShape3D
	base_offset = cyl.height * 0.5 if cyl != null else 0.0
	DishLedger.register(self)
	body_entered.connect(_on_body_entered)
	if not multiplayer.is_server():
		freeze = true
	# Adopt the authored starting state (e.g. CLEAN for plates staged on the
	# clean counter). The server owns truth; clients then track via the
	# synchronizer, and both start from the same authored value.
	if start_state != State.DIRTY:
		state = start_state
	_apply_state()

## Held/stowed plates are driven to a hold point each frame; leaving their
## collider live makes them fight the player capsule and the world (jitter,
## z-fighting). Muting layer+mask keeps them purely visual while carried, then
## restores them so a thrown plate still lands, rests, and can break.
func _set_collision(on: bool) -> void:
	set_deferred("collision_layer", _col_layer if on else 0)
	set_deferred("collision_mask", _col_mask if on else 0)

func _physics_process(_delta: float) -> void:
	if multiplayer.is_server() and state == State.HELD and holder != null:
		# Plates nest into a stack above the hold point, so a full expo run of
		# clean plates rides in one hand instead of one trip each.
		global_position = holder.hold_point.global_position + Vector3.UP * (hold_index * STACK_STEP)
		global_rotation = Vector3(0.0, holder.rotation.y, 0.0)

func is_grabbable() -> bool:
	return state in [State.DIRTY, State.AT_PIT, State.CLEAN] and holder == null and in_tub == null

## Scooped into a bus tub: frozen, DIRTY, and driven by the tub each frame.
func stow(tub: BusTub) -> void:
	in_tub = tub
	holder = null
	freeze = true
	_set_collision(false)
	if state != State.DIRTY:
		state = State.DIRTY

## Tipped out of the tub onto the pit counter; the DirtyCounter flags AT_PIT.
func release_to_pit(spot: Vector3) -> void:
	in_tub = null
	global_position = spot
	_set_collision(true)
	if multiplayer.is_server():
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

func pick_up(by: Busser, index: int = 0) -> void:
	_state_before_hold = state
	_thrown_by = null
	holder = by
	hold_index = index
	freeze = true
	_set_collision(false)
	state = State.HELD

func drop() -> void:
	holder = null
	if state == State.HELD:
		# Clean plates stay clean in careful hands; everything else is dirty.
		state = State.CLEAN if _state_before_hold == State.CLEAN else State.DIRTY
	if state != State.BROKEN:
		_set_collision(true)
	if multiplayer.is_server() and state != State.BROKEN:
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

## Launch at an exact SPEED rather than by impulse. Impulse divides by mass, so
## tuning it means tuning against the dish's mass by hand; a velocity is what the
## design actually talks about ("a pass", "a yeet") and what BREAK_SPEED compares
## against.
func launch(launch_velocity: Vector3, thrower: Busser) -> void:
	drop()
	if not multiplayer.is_server() or state == State.BROKEN:
		return
	_thrown_by = thrower
	_catch_block_until = Time.get_ticks_msec() + CATCH_BLOCK_MS
	linear_velocity = launch_velocity

## Can `by` pluck this plate out of the air right now? Only moving plates count,
## so a plate resting on a counter is never sucked into a passing busser's hands.
func is_catchable(by: Busser) -> bool:
	if holder != null or in_tub != null or freeze:
		return false
	if not state in [State.DIRTY, State.CLEAN]:
		return false
	if linear_velocity.length() < Busser.CATCH_MIN_SPEED:
		return false
	if by == _thrown_by and Time.get_ticks_msec() < _catch_block_until:
		return false
	return true

func land_at_pit() -> void:
	state = State.AT_PIT

func land_at_pass() -> void:
	state = State.AT_PASS

func begin_wash(machine_pos: Vector3) -> void:
	freeze = true
	global_position = machine_pos
	state = State.WASHING

func finish_wash(surface_pos: Vector3) -> void:
	freeze = true
	global_position = surface_pos + Vector3.UP * base_offset
	global_rotation = Vector3.ZERO
	state = State.CLEAN

func begin_cook(cook_pos: Vector3) -> void:
	freeze = true
	global_position = cook_pos
	state = State.COOKING

func serve_at(surface_pos: Vector3) -> void:
	freeze = true
	global_position = surface_pos + Vector3.UP * base_offset
	global_rotation = Vector3.ZERO
	state = State.SERVED

func eaten() -> void:
	state = State.DIRTY
	if multiplayer.is_server():
		freeze = false

## Sound for entering a state. Driven off the state machine rather than off the
## verb that caused it, so every peer plays it from its own replicated copy with
## no sound RPCs. States not listed here are silent on purpose.
const STATE_SOUNDS := {
	State.HELD: [&"grab", 0.0],
	State.BROKEN: [&"shatter", 2.0],
	State.AT_PIT: [&"plate_to_pit", -2.0],
	State.SERVED: [&"plate_served", -4.0],
	State.CLEAN: [&"clatter_light", -8.0],   # quiet: the machine's own sound carries this moment
}

func _set_state(value: int) -> void:
	if state == value:
		return
	state = value
	if is_node_ready():
		_apply_state()
		_play_state_sound(value)
	DishLedger.notify_changed()

## `is_node_ready()` gates this so authored start states (a plate staged CLEAN
## on the shelf) do not fire a chorus of sounds on level load.
func _play_state_sound(value: int) -> void:
	if not STATE_SOUNDS.has(value):
		return
	var entry: Array = STATE_SOUNDS[value]
	Audio.play_3d(entry[0], global_position, entry[1])

func _apply_state() -> void:
	_apply_visuals()
	if state == State.BROKEN:
		shape.set_deferred("disabled", true)
		freeze = true

## Presentation only. Gameplay never reads this back.
func _apply_visuals() -> void:
	if visuals == null:
		return
	# A held plate looks like whatever it was before it was picked up, so a clean
	# plate stays clean-looking in your hands.
	var shown := state
	if HELD_FOLLOWS_PREVIOUS and state == State.HELD:
		shown = _state_before_hold
	var entry: Dictionary = STATE_PARTS.get(shown, {})
	visuals.show_only(entry.get("parts", ["Body"]))
	visuals.tint_body(entry.get("tint", Color.WHITE), entry.has("tint"))
	if state == State.BROKEN:
		visuals.apply_broken()
	else:
		visuals.clear_broken()

func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if state in [State.DIRTY, State.CLEAN] and linear_velocity.length() > BREAK_SPEED:
		state = State.BROKEN
		return
	# A clean plate that touches the floor is not a clean plate anymore.
	if state == State.CLEAN and body.is_in_group("dirties_dishes"):
		state = State.DIRTY

