class_name Dish
extends RigidBody3D
## One plate in the conserved dish pool. Every dish is always in exactly one
## state; the whole game economy is this state machine:
##   CLEAN -> AT_PASS -> COOKING -> SERVED -> DIRTY -> AT_PIT -> WASHING -> CLEAN
## plus HELD (in a busser's hands) and BROKEN (pool permanently shrinks).
## Server simulates physics + owns state; clients freeze their local body and
## receive position/rotation/state through the MultiplayerSynchronizer.

enum State { DIRTY, HELD, AT_PIT, WASHING, CLEAN, BROKEN, AT_PASS, COOKING, SERVED }

const BREAK_SPEED := 6.0  # generous: only genuine yeets break plates

const STATE_COLORS := {
	State.DIRTY: Color(0.45, 0.31, 0.18),
	State.HELD: Color(0.55, 0.4, 0.25),
	State.AT_PIT: Color(0.78, 0.52, 0.2),
	State.WASHING: Color(0.35, 0.55, 0.9),
	State.CLEAN: Color(0.95, 0.95, 0.92),
	State.BROKEN: Color(0.18, 0.18, 0.18),
	State.AT_PASS: Color(0.85, 0.9, 0.95),
	State.COOKING: Color(0.95, 0.45, 0.15),
	State.SERVED: Color(0.72, 0.5, 0.2),   # food on the plate
}

static var _materials: Dictionary = {}

## The state a scene-placed dish starts in. Plates pre-staged on the clean
## counter want CLEAN; loose dirties on a table want DIRTY (the default).
@export var start_state: State = State.DIRTY

const STACK_STEP := 0.05             # vertical gap between plates in a hand-stack

var state: int = State.DIRTY: set = _set_state
var holder: Busser = null            # server-side only
var in_tub: BusTub = null            # server-side only; set while stowed in a tub
var hold_index := 0                  # server-side only; height in the holder's stack
var _state_before_hold: int = State.DIRTY

@onready var mesh: MeshInstance3D = find_children("*", "MeshInstance3D", true, false)[0]
@onready var shape := $Shape as CollisionShape3D

var _col_layer := 1
var _col_mask := 1

func _ready() -> void:
	_col_layer = collision_layer
	_col_mask = collision_mask
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

func throw(impulse: Vector3) -> void:
	drop()
	if multiplayer.is_server() and state != State.BROKEN:
		apply_central_impulse(impulse)

func land_at_pit() -> void:
	state = State.AT_PIT

func land_at_pass() -> void:
	state = State.AT_PASS

func begin_wash(machine_pos: Vector3) -> void:
	freeze = true
	global_position = machine_pos
	state = State.WASHING

func finish_wash(shelf_pos: Vector3) -> void:
	freeze = true
	global_position = shelf_pos
	global_rotation = Vector3.ZERO
	state = State.CLEAN

func begin_cook(cook_pos: Vector3) -> void:
	freeze = true
	global_position = cook_pos
	state = State.COOKING

func serve_at(spot: Vector3) -> void:
	freeze = true
	global_position = spot
	global_rotation = Vector3.ZERO
	state = State.SERVED

func eaten() -> void:
	state = State.DIRTY
	if multiplayer.is_server():
		freeze = false

func _set_state(value: int) -> void:
	if state == value:
		return
	state = value
	if is_node_ready():
		_apply_state()
	DishLedger.notify_changed()

func _apply_state() -> void:
	mesh.material_override = _material_for(state)
	if state == State.BROKEN:
		mesh.scale = Vector3(1.3, 0.15, 1.3)
		shape.set_deferred("disabled", true)
		freeze = true

func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if state in [State.DIRTY, State.CLEAN] and linear_velocity.length() > BREAK_SPEED:
		state = State.BROKEN
		return
	# A clean plate that touches the floor is not a clean plate anymore.
	if state == State.CLEAN and body.is_in_group("dirties_dishes"):
		state = State.DIRTY

func _material_for(s: int) -> StandardMaterial3D:
	if not _materials.has(s):
		var m := StandardMaterial3D.new()
		m.albedo_color = STATE_COLORS[s]
		_materials[s] = m
	return _materials[s]
