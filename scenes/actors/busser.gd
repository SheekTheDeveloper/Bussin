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

# --- Stack stability: the greed dial (GDD 3, "Stack in-hand") ---------------
# Carrying more is faster but less stable. Wobble builds from how much you are
# carrying multiplied by how violently you are moving, and bleeds off when you
# settle. Max it out and the top plate slides off - it is not scripted damage,
# it is the plate leaving your hands, so it can land safely or smash depending
# on where you were standing. One plate NEVER wobbles: the punish is for greed,
# not for playing at all.
const WOBBLE_MAX := 1.0
# Tuned so the dial reads as a real choice (times = seconds to spill):
#   2 plates  always safe, at any speed - carrying a pair is never punished
#   3 plates  safe until you turn (8.5s walking+turning)
#   4 plates  sprinting is borderline; hard turns spill in ~1.9s
#   5 plates  sprinting straight spills in ~3.9s, sprint+whip in ~0.6s
# Walking is safe at every stack size, so the punish is always something you
# chose to do. FIRST-PASS VALUES - confirm them in the feel playtest (GDD 9).
const WOBBLE_RECOVER := 0.72       # per second bled off when you move calmly
const WOBBLE_FROM_SPEED := 0.15    # per m/s of horizontal speed
const WOBBLE_FROM_TURN := 0.5      # per rad/s of yaw change (whipping the camera)
const WOBBLE_LAND_KICK := 0.3      # instant spike when you land a jump
const WOBBLE_RELIEF := 0.45        # wobble remaining after a plate slides off
## Motion is measured by differencing the transform, so a teleport (the
## fall-through-floor respawn, or a test harness moving the body) would read as
## an impossible speed and dump the stack for no reason. Clamp what we believe.
const WOBBLE_MAX_SPEED := SPRINT_SPEED * 1.5
const WOBBLE_MAX_TURN := 12.0      # rad/s; faster than any human flick

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

## 0..1 how close the hand-stack is to spilling. Server truth (it decides when a
## plate falls) mirrored to the owner for its HUD, the same way carry_load is -
## never put this on the body synchronizer, whose authority is the client.
var wobble: float = 0.0

## Local-only: what the reach ray is pointing at, as a HUD prompt. Empty when
## there is nothing actionable. Computed on the owning peer from replicated
## state, so it costs no network traffic.
var focus_prompt: String = ""

# Server-side motion tracking, sampled from the replicated transform so the
# server can judge stability for remote clients without trusting their input.
var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _was_on_floor := true

# Local-only camera feel state.
var _head_base_y := 0.0
var _bob_t := 0.0
var _dip := 0.0
var _base_fov := 75.0
var _was_on_floor_local := true

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
	# Capture the authored eye height and FOV so the bob/dip/sprint effects
	# always return to the scene's values instead of drifting from them.
	_head_base_y = head.position.y
	_base_fov = camera.fov
	_prev_pos = global_position
	_prev_yaw = rotation.y
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
	# Stability is server truth (it mutates dishes), so it runs before the
	# authority gate - the server must simulate it for every busser, including
	# the client-owned ones whose movement it does not run.
	if multiplayer.is_server():
		_update_stack_stability(delta)
	if not is_multiplayer_authority():
		return
	_update_camera_feel(delta)
	_update_focus()
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
		reset_motion_tracking()

## Server-only. Motion is measured from the replicated transform rather than
## from input, so it works identically for the host's own busser and for a
## remote client's, and a client cannot lie about how carefully it is moving.
func _update_stack_stability(delta: float) -> void:
	if delta <= 0.0:
		return
	var flat := Vector3(global_position.x - _prev_pos.x, 0.0, global_position.z - _prev_pos.z)
	var speed := minf(flat.length() / delta, WOBBLE_MAX_SPEED)
	var turn_rate := minf(absf(angle_difference(_prev_yaw, rotation.y)) / delta, WOBBLE_MAX_TURN)
	_prev_pos = global_position
	_prev_yaw = rotation.y

	# Landing jars the stack even if you were moving in a straight line.
	var landed := is_on_floor() and not _was_on_floor
	_was_on_floor = is_on_floor()

	var plates := held_stack.size()
	if plates < 2:
		# Nothing to spill, so let any leftover wobble drain and stop here.
		if wobble > 0.0:
			_set_wobble(maxf(wobble - WOBBLE_RECOVER * delta, 0.0))
		return

	# 0 at two plates, 1 at a full stack: the greed dial.
	var load_factor := float(plates - 1) / float(STACK_MAX - 1)
	var agitation := speed * WOBBLE_FROM_SPEED + turn_rate * WOBBLE_FROM_TURN
	var next := wobble + (load_factor * agitation - WOBBLE_RECOVER) * delta
	if landed:
		next += WOBBLE_LAND_KICK * load_factor
	next = clampf(next, 0.0, WOBBLE_MAX)

	if next >= WOBBLE_MAX:
		_spill_top_plate()
		next = WOBBLE_RELIEF
	_set_wobble(next)

## Re-baseline the stability sampler. Call after deliberately moving the body,
## so the jump is not mistaken for a violent sprint on the next frame.
func reset_motion_tracking() -> void:
	_prev_pos = global_position
	_prev_yaw = rotation.y

## The top plate slides out of your hands. It is dropped, not deleted - it falls
## with real physics from where you were standing, so it may land fine on a
## counter or smash on the floor. That ambiguity is the point.
func _spill_top_plate() -> void:
	if held_stack.is_empty():
		return
	var dish: Dish = held_stack.pop_back()
	server_set_stack(held_stack.size())
	if is_instance_valid(dish):
		dish.drop()
		# A little outward shove so it visibly leaves the stack instead of
		# dropping straight back onto the plate below it.
		dish.apply_central_impulse(-camera.global_transform.basis.z * 0.9 + Vector3.UP * 0.6)

## Mirror wobble to the owning peer for its HUD, same pattern as carry_load.
func _set_wobble(value: float) -> void:
	if is_equal_approx(value, wobble):
		return
	wobble = value
	var owner_id := get_multiplayer_authority()
	if owner_id != multiplayer.get_unique_id():
		_recv_wobble.rpc_id(owner_id, value)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _recv_wobble(value: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:  # only trust the server
		wobble = value

## Local-only camera feel: walk bob, landing dip, and a small FOV push when
## sprinting. All cosmetic and all driven off this peer's own state, so it never
## touches replication. Bob moves the head's POSITION only - pitch belongs to
## the look code and must not be fought over.
func _update_camera_feel(delta: float) -> void:
	var flat_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if is_on_floor() and flat_speed > 0.5:
		# Bob frequency tracks speed so sprinting reads as faster footfalls.
		_bob_t += delta * (5.0 + flat_speed * 1.1)
		var amount := 0.022 * clampf(flat_speed / SPRINT_SPEED, 0.0, 1.0)
		head.position.y = _head_base_y + sin(_bob_t * 2.0) * amount
	else:
		_bob_t = 0.0
		head.position.y = lerpf(head.position.y, _head_base_y, 10.0 * delta)

	# Landing dip: a short compression on touchdown, eased back out.
	if is_on_floor() and not _was_on_floor_local:
		_dip = 0.12
	_was_on_floor_local = is_on_floor()
	_dip = lerpf(_dip, 0.0, 8.0 * delta)
	head.position.y -= _dip

	var sprinting := flat_speed > WALK_SPEED + 0.4 and carry_load < 0
	camera.fov = lerpf(camera.fov, _base_fov + (6.0 if sprinting else 0.0), 6.0 * delta)

## Local-only. Turns whatever the reach ray is on into a HUD prompt, using only
## replicated state (dish state, our own mirrored stack/carry counts), so the
## client can compute it without asking the server anything.
func _update_focus() -> void:
	focus_prompt = ""
	if not reach.is_colliding():
		return
	var node := reach.get_collider() as Node
	if node == null:
		return
	if node is Dish:
		var dish := node as Dish
		if carry_load >= 0:
			if dish.state == Dish.State.DIRTY:
				focus_prompt = "SCOOP INTO TUB"
		elif dish.is_grabbable():
			focus_prompt = "STACK FULL" if stack_load >= STACK_MAX else "PICK UP PLATE"
	elif node is BusTub:
		if carry_load < 0 and stack_load == 0 and (node as BusTub).is_grabbable():
			focus_prompt = "LIFT TUB"
	elif node is DishMachine:
		focus_prompt = "RUN DISH MACHINE"
	elif node is DirtyCounter:
		if carry_load > 0:
			focus_prompt = "DUMP TUB"
		elif stack_load > 0:
			focus_prompt = "SET DOWN PLATES"
	elif node is KitchenPass:
		if stack_load > 0:
			focus_prompt = "STOCK THE PASS"

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
