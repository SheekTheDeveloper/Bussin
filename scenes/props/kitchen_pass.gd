class_name KitchenPass
extends StaticBody3D
## The kitchen's window to the world. Players deliver CLEAN plates onto the
## pass; the (abstract) kitchen pulls one plate per pending order, cooks it,
## and serves it to the waiting guest's spot at their table.
## The chef behind the pass flashes red when orders are waiting but the pass
## has no clean plates - the diegetic "NEED PLATES!" alarm.

const COOK_TIME := 2.5

var orders: Array = []  # of Guest, FIFO; server-side
var _cooking := false
var _chef_mesh: MeshInstance3D = null
var _chef_red := StandardMaterial3D.new()
var _chef_t := 0.0

@onready var zone := $PassZone as Area3D
@onready var cook_spot := $CookSpot as Node3D
@onready var chef := $Chef as Node3D

func _ready() -> void:
	_chef_red.albedo_color = Color(0.9, 0.2, 0.15)
	var meshes := chef.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		_chef_mesh = meshes[0]

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body in zone.get_overlapping_bodies():
		if body is Dish and body.state == Dish.State.CLEAN and body.holder == null:
			body.land_at_pass()

func _process(delta: float) -> void:
	# Chef idle bob + plate-starvation flash. Derived from replicated dish
	# states and guest activity, so every peer agrees without extra sync.
	_chef_t += delta * 3.0
	chef.position.y = absf(sin(_chef_t)) * 0.04
	if _chef_mesh != null:
		var starving := _any_guest_waiting() and DishLedger.count(Dish.State.AT_PASS) == 0 \
				and DishLedger.count(Dish.State.COOKING) == 0
		_chef_mesh.material_override = _chef_red if starving and fmod(_chef_t, 1.0) < 0.5 else null

func _any_guest_waiting() -> bool:
	for g in get_tree().get_nodes_in_group("guests"):
		if g is Guest and g.activity == Guest.Activity.WAITING_FOOD:
			return true
	return false

func place_order(party: Array) -> void:
	for guest in party:
		orders.append(guest)
	if not _cooking:
		_cooking = true
		_cook_loop()

func _cook_loop() -> void:
	while not orders.is_empty():
		var plate := _next_pass_plate()
		if plate == null:
			await get_tree().create_timer(0.4).timeout
			continue
		var guest := orders.pop_front() as Guest
		if not is_instance_valid(guest) or guest.table == null:
			continue
		plate.begin_cook(cook_spot.global_position)
		await get_tree().create_timer(COOK_TIME).timeout
		if not is_instance_valid(plate):
			continue
		if not is_instance_valid(guest) or guest.table == null:
			plate.land_at_pass()  # order died; plate returns to the pass
			continue
		plate.serve_at(guest.table.dish_spot_global(guest.seat_index))
		guest.start_eating(plate)
	_cooking = false

func _next_pass_plate() -> Dish:
	for d in DishLedger.dishes:
		if d.state == Dish.State.AT_PASS:
			return d
	return null
