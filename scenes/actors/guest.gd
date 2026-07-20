class_name Guest
extends CharacterBody3D
## An AI guest. Server drives the whole lifecycle via waypoints + timers;
## clients receive position/rotation/activity and animate a bob locally.

enum Activity { WALKING, QUEUED, WAITING_FOOD, EATING, LEAVING }

const SPEED := 2.4
const ARRIVE_DIST := 0.4
const REPATH_INTERVAL := 0.4   # refresh the path this often so bumps self-correct

signal arrived(guest: Guest)
signal finished_eating(guest: Guest)

var activity: int = Activity.QUEUED  # replicated
var purpose := ""                    # server-side: "seating" | "leaving" | "walkout"
var table: DinerTable = null         # server-side
var seat_index := -1                 # server-side
var dish: Dish = null                # server-side

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _destination := Vector3.ZERO     # server-side: the true target (seat/door/queue spot)
var _repath_t := 0.0
var _arriving := false
var _bob_t := 0.0
var _last_pos := Vector3.ZERO

@onready var model := $Model as Node3D
@onready var agent := $Agent as NavigationAgent3D

func _ready() -> void:
	# Tint per guest from its name so every peer computes the same color.
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(fmod(hash(name) * 0.0001, 1.0), 0.45, 0.85)
		(meshes[0] as MeshInstance3D).material_override = m
	_last_pos = global_position

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	if activity != Activity.WALKING:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	# Arrival is judged by straight-line distance to the true target, not the
	# navmesh path: seats sit just inside the radius-eroded mesh, so the agent's
	# path ends a hair short and the guest finishes the approach directly.
	var flat := Vector3(_destination.x - global_position.x, 0.0, _destination.z - global_position.z)
	if flat.length() < ARRIVE_DIST:
		velocity = Vector3.ZERO
		move_and_slide()
		if not _arriving:
			_arriving = true
			arrived.emit(self)
		return
	# Re-request the path periodically so a guest shoved off-course (by the
	# player or a table corner) re-routes instead of grinding in place.
	_repath_t += delta
	if _repath_t >= REPATH_INTERVAL:
		_repath_t = 0.0
		agent.target_position = _destination
	# Steer toward the next navmesh corner; once the path is spent, walk straight
	# to the exact target for the final off-mesh step to the seat/door.
	var next := agent.get_next_path_position()
	var to_next := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	var step := to_next if to_next.length() > 0.15 else flat
	var dir := step.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
	move_and_slide()

func _process(delta: float) -> void:
	# Cosmetic bob on every peer, derived from replicated data only.
	var moved := (global_position - _last_pos).length() / maxf(delta, 0.0001)
	_last_pos = global_position
	if activity == Activity.EATING:
		_bob_t += delta * 9.0
		model.rotation.x = 0.12 + sin(_bob_t) * 0.1
		model.position.y = 0.0
	elif moved > 0.4:
		_bob_t += delta * 11.0
		model.position.y = absf(sin(_bob_t)) * 0.05
		model.rotation.x = 0.0
	else:
		model.position.y = 0.0
		model.rotation.x = 0.0

## Head to a single destination; the NavigationAgent routes around furniture.
## (The old lane-waypoint list is gone - the navmesh does that job now.)
func walk_to(destination: Vector3, new_purpose: String) -> void:
	_destination = destination
	purpose = new_purpose
	activity = Activity.WALKING
	_arriving = false
	_repath_t = 0.0
	agent.target_position = destination

func start_eating(served_dish: Dish) -> void:
	dish = served_dish
	activity = Activity.EATING
	_eat()

func _eat() -> void:
	await get_tree().create_timer(randf_range(6.0, 11.0)).timeout
	if not is_inside_tree():
		return
	if dish != null and is_instance_valid(dish):
		dish.eaten()
	dish = null
	purpose = "done"
	finished_eating.emit(self)
