class_name Busser
extends CharacterBody3D
## First-person busser. Movement is client-authoritative (owning peer simulates,
## MultiplayerSynchronizer streams it out). Interactions are server-authoritative:
## the client sends intent RPCs to peer 1, the server validates and mutates dishes.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 6.5
const JUMP_VELOCITY := 4.2
const MOUSE_SENSITIVITY := 0.002
const THROW_FORCE := 6.5
const GRAB_RANGE := 3.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var held_dish: Dish = null  # server-side truth only

@onready var head := $Head as Node3D
@onready var camera := $Head/Camera3D as Camera3D
@onready var reach := $Head/Camera3D/Reach as RayCast3D
@onready var hold_point := $Head/Camera3D/HoldPoint as Node3D
@onready var body_mesh := $Mesh as MeshInstance3D

func _enter_tree() -> void:
	# Spawned nodes are named after their peer id; authority follows the name.
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	reach.add_exception(self)
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color.from_hsv(fmod(name.to_int() * 0.173, 1.0), 0.55, 0.9)
	body_mesh.material_override = tint
	if is_multiplayer_authority():
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, -1.4, 1.4)
	elif event.is_action_pressed("grab"):
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			_send_grab_or_drop()
	elif event.is_action_pressed("throw"):
		_server_throw.rpc_id(1)
	elif event.is_action_pressed("interact"):
		_send_interact()
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	move_and_slide()

	if global_position.y < -10.0:
		global_position = Vector3(0.0, 1.0, 4.0)
		velocity = Vector3.ZERO

func _send_grab_or_drop() -> void:
	var target := NodePath()
	if reach.is_colliding() and reach.get_collider() is Dish:
		target = (reach.get_collider() as Node).get_path()
	_server_grab_or_drop.rpc_id(1, target)

func _send_interact() -> void:
	if reach.is_colliding():
		var collider := reach.get_collider() as Node
		if collider != null and collider.has_method("interact"):
			_server_interact.rpc_id(1, collider.get_path())

@rpc("any_peer", "call_local", "reliable")
func _server_grab_or_drop(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if held_dish != null:
		held_dish.drop()
		held_dish = null
		return
	if target_path.is_empty():
		return
	var dish := get_node_or_null(target_path) as Dish
	if dish == null or dish.holder != null:
		return
	if dish.state != Dish.State.DIRTY and dish.state != Dish.State.AT_PIT:
		return
	if dish.global_position.distance_to(head.global_position) > GRAB_RANGE:
		return
	dish.pick_up(self)
	held_dish = dish

@rpc("any_peer", "call_local", "reliable")
func _server_throw() -> void:
	if not multiplayer.is_server() or held_dish == null:
		return
	var dish := held_dish
	held_dish = null
	dish.throw(-camera.global_transform.basis.z * THROW_FORCE + Vector3.UP * 1.5)

@rpc("any_peer", "call_local", "reliable")
func _server_interact(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var target := get_node_or_null(target_path)
	if target == null or not target.has_method("interact"):
		return
	if target is Node3D and (target as Node3D).global_position.distance_to(head.global_position) > GRAB_RANGE + 1.0:
		return
	target.interact(self)
