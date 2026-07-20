class_name BusTub
extends RigidBody3D
## A two-handed bus tub. Bussers scoop DIRTY plates off tables into it, haul it
## to the pit counter, and dump it - bigger capacity than a single grab, but
## slower to carry and it fills your view as it loads. Server owns the truth;
## the tub body and its stowed dishes replicate through their synchronizers.
## Standalone prop: swap the scene for skins/upgrades (bigger CAPACITY, a cart)
## without touching the carry logic.

const CAPACITY := 6

var carrier: Busser = null      # server-side only
var contents: Array[Dish] = []  # server-side only

var _col_layer := 1
var _col_mask := 1
var _settle_pending := false    # server: drop the tub onto the floor next physics tick

func _ready() -> void:
	_col_layer = collision_layer
	_col_mask = collision_mask
	if not multiplayer.is_server():
		freeze = true
	# Tubs never collide with player capsules on any peer (see busser.gd): the
	# body you carry is glued to your face and a body you drop can clip geometry,
	# so a physical tub↔player contact only ever means jitter or a launch. Each
	# local Busser excepts every tub on spawn; this covers the reverse order -
	# a tub entering the tree after the local player already exists.
	add_to_group("tubs")
	if Busser.local != null:
		Busser.local.add_collision_exception_with(self)

## While carried the tub is driven to the busser's hold point each frame, so
## its collider is muted to stop it fighting the player/world; restored on
## set-down so it falls and rests, and plates can be tossed into it.
func _set_collision(on: bool) -> void:
	set_deferred("collision_layer", _col_layer if on else 0)
	set_deferred("collision_mask", _col_mask if on else 0)

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	# While carried, the tub is driven to the busser's hold point. When set
	# down it simulates and rests on its own.
	if carrier != null:
		global_position = carrier.tub_hold.global_position
		global_rotation = Vector3(0.0, carrier.rotation.y, 0.0)
	elif _settle_pending:
		# Space queries are only valid inside the physics step, so the set-down
		# floor-snap is deferred to here rather than run from the RPC handler.
		_settle_pending = false
		_settle_on_floor()
	# Either way, stowed plates stay nested inside the tub's hollow every frame -
	# they are logically attached to the tub (contents <-> Dish.in_tub), so they
	# ride with it whether it is carried, grounded, or knocked around, and never
	# float free or fall through. Driving only stops when a plate leaves contents
	# (dumped at the pit).
	for i in contents.size():
		var d := contents[i]
		if is_instance_valid(d):
			d.global_position = global_position + Vector3(0.0, 0.06 + i * 0.03, 0.0)
			d.global_rotation = global_rotation

func is_grabbable() -> bool:
	return carrier == null

func has_room() -> bool:
	return contents.size() < CAPACITY

func pick_up(by: Busser) -> void:
	carrier = by
	freeze = true
	_set_collision(false)
	# No per-carrier exception needed: tubs are excepted from every local player
	# capsule at spawn, on every peer, so no busser can ever be launched by one.

func set_down() -> void:
	carrier = null
	_set_collision(true)
	if multiplayer.is_server():
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_settle_pending = true

## Drop the tub straight down onto whatever surface is beneath its carried
## position, so it rests on the floor/counter instead of being freed mid-air
## inside geometry (the other half of the anti-launch fix). Runs from
## _physics_process, where space-state queries are valid.
func _settle_on_floor() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
		# Seat the tub's base (its Floor shape sits ~0.03 above the origin) on
		# the surface, nudged up a hair to avoid starting interpenetrated.
		global_position.y = (hit.position as Vector3).y + 0.04

func load_dish(dish: Dish) -> bool:
	if not has_room():
		return false
	contents.append(dish)
	dish.stow(self)
	return true

## Empties the tub onto the pit counter. Dishes land DIRTY in the drop zone;
## the DirtyCounter flags them AT_PIT next frame, same as a hand-placed plate.
func dump_at(world_pos: Vector3) -> int:
	var n := contents.size()
	for i in n:
		var d := contents[i]
		if not is_instance_valid(d):
			continue
		var spot := world_pos + Vector3(-0.3 + (i % 3) * 0.3, 0.35 + i * 0.03, -0.15 + (i / 3) * 0.3)
		d.release_to_pit(spot)
	contents.clear()
	return n
