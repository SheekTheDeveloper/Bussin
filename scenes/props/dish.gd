class_name Dish
extends RigidBody3D
## One plate in the conserved dish pool. Every dish is always in exactly one
## state; the whole game economy is this state machine.
## Server simulates physics + owns state; clients freeze their local body and
## receive position/rotation/state through the MultiplayerSynchronizer.

enum State { DIRTY, HELD, AT_PIT, WASHING, CLEAN, BROKEN }

const BREAK_SPEED := 6.0  # generous: only genuine yeets break plates

const STATE_COLORS := {
	State.DIRTY: Color(0.45, 0.31, 0.18),
	State.HELD: Color(0.55, 0.4, 0.25),
	State.AT_PIT: Color(0.78, 0.52, 0.2),
	State.WASHING: Color(0.35, 0.55, 0.9),
	State.CLEAN: Color(0.95, 0.95, 0.92),
	State.BROKEN: Color(0.18, 0.18, 0.18),
}

static var _materials: Dictionary = {}

var state: int = State.DIRTY: set = _set_state
var holder: Busser = null  # server-side only

@onready var mesh := $Mesh as MeshInstance3D
@onready var shape := $Shape as CollisionShape3D

func _ready() -> void:
	DishLedger.register(self)
	body_entered.connect(_on_body_entered)
	if not multiplayer.is_server():
		freeze = true
	_apply_state()

func _physics_process(_delta: float) -> void:
	if multiplayer.is_server() and state == State.HELD and holder != null:
		global_position = holder.hold_point.global_position
		global_rotation = Vector3(0.0, holder.rotation.y, 0.0)

func pick_up(by: Busser) -> void:
	holder = by
	freeze = true
	state = State.HELD

func drop() -> void:
	holder = null
	if state == State.HELD:
		state = State.DIRTY
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

func begin_wash(machine_pos: Vector3) -> void:
	freeze = true
	global_position = machine_pos
	state = State.WASHING

func finish_wash(shelf_pos: Vector3) -> void:
	freeze = true
	global_position = shelf_pos
	global_rotation = Vector3.ZERO
	state = State.CLEAN

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

func _on_body_entered(_body: Node) -> void:
	if not multiplayer.is_server():
		return
	if state == State.DIRTY and linear_velocity.length() > BREAK_SPEED:
		state = State.BROKEN

func _material_for(s: int) -> StandardMaterial3D:
	if not _materials.has(s):
		var m := StandardMaterial3D.new()
		m.albedo_color = STATE_COLORS[s]
		_materials[s] = m
	return _materials[s]
