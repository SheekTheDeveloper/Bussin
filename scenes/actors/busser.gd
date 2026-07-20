class_name Busser
extends CharacterBody3D
## First-person busser. Movement is client-authoritative (owning peer simulates,
## MultiplayerSynchronizer streams it out). Interactions are server-authoritative:
## the client sends intent RPCs to peer 1, the server validates and mutates dishes.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 6.5
const CARRY_SPEED := 3.0  # hauling a tub is slower, and you can't sprint
const JUMP_VELOCITY := 4.2
const MOUSE_SENSITIVITY := 0.002
const STICK_LOOK_SPEED := 2.8  # rad/s at full right-stick deflection
const THROW_FORCE := 6.5
const GRAB_RANGE := 3.0
const STACK_MAX := 5  # plates you can hand-carry at once (expo run to the pass)

## The local (authority) busser, so the HUD can read this peer's carry state.
static var local: Busser = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var held_stack: Array[Dish] = []   # server-side truth only; hand-carried plate stack
var carried_tub: BusTub = null  # server-side truth only
## How many plates are in this busser's hand (server truth, mirrored to the
## owner for its HUD, like carry_load). 0 = empty hands.
var stack_load: int = 0
## -1 = not carrying a tub, else how many plates are in it. Server truth, but
## only the owning peer needs it (carry slowdown + its own HUD view-fill), so
## the server pushes it to the owner by RPC - NOT through the body synchronizer,
## whose authority is the client and would clobber the server's value.
var carry_load: int = -1

@onready var head := $Head as Node3D
@onready var camera := $Head/Camera3D as Camera3D
@onready var reach := $Head/Camera3D/Reach as RayCast3D
@onready var hold_point := $Head/Camera3D/HoldPoint as Node3D
@onready var tub_hold := $Head/Camera3D/TubHold as Node3D
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
		local = self
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		# Only the authority capsule runs move_and_slide, so it's the only body
		# that can be launched/blocked by a tub. Except every tub from it (bus
		# tubs are carried/placed via raycast, never body-checked) so carried and
		# dropped tubs stay smooth for this peer. Tubs spawned later self-register
		# the reverse (see bus_tub.gd).
		for tub in get_tree().get_nodes_in_group("tubs"):
			add_collision_exception_with(tub as PhysicsBody3D)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENSITIVITY * Settings.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens * Settings.look_pitch_sign())
		head.rotation.x = clampf(head.rotation.x, -1.4, 1.4)
	elif event.is_action_pressed("grab"):
		# A mouse click while the cursor is free just recaptures it;
		# controller grab (R1) always grabs.
		if event is InputEventMouseButton and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			_send_grab_or_drop()
	elif event.is_action_pressed("throw"):
		_server_throw.rpc_id(1)
	elif event.is_action_pressed("interact"):
		_send_interact()
	# Escape / gamepad Start is owned by the pause menu (pause_menu.gd), which
	# consumes the event and drives the cursor. The busser no longer frees the
	# mouse itself, so opening the pause overlay is the only way to unlock it.

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		var stick := STICK_LOOK_SPEED * Settings.stick_sensitivity * delta
		rotate_y(-look.x * stick)
		head.rotate_x(-look.y * stick * Settings.look_pitch_sign())
		head.rotation.x = clampf(head.rotation.x, -1.4, 1.4)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := WALK_SPEED
	if carry_load >= 0:
		speed = CARRY_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
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
	if reach.is_colliding():
		var c := reach.get_collider()
		if c is Dish or c is BusTub:
			target = (c as Node).get_path()
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
	var node := get_node_or_null(target_path)
	# Carrying a tub: aim at a dirty plate to scoop it in, else set the tub down.
	if carried_tub != null:
		var scooped := node is Dish and _in_reach(node) and carried_tub.has_room() \
			and (node as Dish).state == Dish.State.DIRTY \
			and (node as Dish).holder == null and (node as Dish).in_tub == null
		if scooped:
			carried_tub.load_dish(node as Dish)
			server_set_carry(carried_tub.contents.size())
		else:
			carried_tub.set_down()
			carried_tub = null
			server_set_carry(-1)
		return
	# Aiming at a grabbable plate: add it to the hand-stack (up to STACK_MAX), so
	# you can gather a whole run of cleans and carry them to the pass in one trip.
	var dish := node as Dish
	var aiming_plate := dish != null and dish.is_grabbable() and _in_reach(dish)
	if aiming_plate and held_stack.size() < STACK_MAX:
		dish.pick_up(self, held_stack.size())
		held_stack.append(dish)
		server_set_stack(held_stack.size())
		return
	if aiming_plate:
		return  # stack full and aimed at a plate - hold, don't dump the stack
	# Not aimed at a grabbable plate: holding a stack sets the whole thing down
	# (face the pass and press grab to deliver the run).
	if not held_stack.is_empty():
		_drop_stack()
		return
	# Empty hands, aimed at a tub: pick it up.
	if node is BusTub and (node as BusTub).is_grabbable() and _in_reach(node):
		carried_tub = node as BusTub
		carried_tub.pick_up(self)
		server_set_carry(carried_tub.contents.size())

## Server: set the whole hand-stack down where the busser is looking. Each plate
## resolves to CLEAN/DIRTY on its own (Dish.drop), so cleans dropped in the pass
## zone flag AT_PASS just like a single hand-placed plate.
func _drop_stack() -> void:
	# One clatter for the whole run, weighted by how many plates are coming down,
	# so a five-plate set-down reads as heavier and less controlled than one.
	# Each plate also makes its own state-transition sound (see dish.gd); this
	# layers on top rather than replacing them.
	_play_stack_clatter(held_stack.size())
	for d in held_stack:
		if is_instance_valid(d):
			d.drop()
	held_stack.clear()
	server_set_stack(0)

func _play_stack_clatter(count: int) -> void:
	if count <= 0:
		return
	var id := &"clatter_light"
	if count >= 4:
		id = &"clatter_heavy"
	elif count >= 2:
		id = &"clatter_mid"
	Audio.play_3d(id, hold_point.global_position, -1.0)

func _in_reach(n: Node) -> bool:
	return n is Node3D and (n as Node3D).global_position.distance_to(head.global_position) <= GRAB_RANGE + 0.5

## Server-only: record the carry count and make sure the owning peer learns it,
## whether that's the host itself or a remote client.
func server_set_carry(value: int) -> void:
	carry_load = value
	var owner_id := get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_recv_carry_load.rpc_id(owner_id, value)

@rpc("any_peer", "call_remote", "reliable")
func _recv_carry_load(value: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:  # only trust the server
		carry_load = value

## Same owner-sync path as carry_load, for the hand-stack plate count.
func server_set_stack(value: int) -> void:
	stack_load = value
	var owner_id := get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_recv_stack_load.rpc_id(owner_id, value)

@rpc("any_peer", "call_remote", "reliable")
func _recv_stack_load(value: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:  # only trust the server
		stack_load = value

@rpc("any_peer", "call_local", "reliable")
func _server_throw() -> void:
	if not multiplayer.is_server() or held_stack.is_empty():
		return
	# Chuck the top plate off the stack - toss cleans into the pass or dirties
	# into a tub from range, one at a time.
	var dish: Dish = held_stack.pop_back()
	server_set_stack(held_stack.size())
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
