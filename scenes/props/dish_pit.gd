class_name DishPit
extends Node3D
## The dish pit: a drop counter, a pass-through machine, and a clean shelf.
## Server flags dirty dishes that land in the DropZone as AT_PIT, and the
## machine cycle converts AT_PIT -> WASHING -> CLEAN onto shelf slots.

const WASH_INTERVAL := 1.2

@onready var zone := $DropZone as Area3D
@onready var machine := $Machine as StaticBody3D
@onready var machine_mesh := $Machine/Mesh as MeshInstance3D
@onready var shelf_base := $ShelfBase as Node3D

var washing := false
var shelf_count := 0
var _machine_mat := StandardMaterial3D.new()

func _ready() -> void:
	machine_mesh.material_override = _machine_mat

func _physics_process(_delta: float) -> void:
	# Machine glows green while a wash is in progress - derived from replicated
	# dish states, so it works on clients without extra sync.
	var busy := DishLedger.count(Dish.State.WASHING) > 0
	_machine_mat.albedo_color = Color(0.3, 0.8, 0.4) if busy else Color(0.5, 0.55, 0.62)

	if not multiplayer.is_server():
		return
	for body in zone.get_overlapping_bodies():
		if body is Dish and body.state == Dish.State.DIRTY and body.holder == null:
			body.land_at_pit()

func start_cycle() -> void:
	if washing or not multiplayer.is_server():
		return
	washing = true
	_run_cycle()

func _run_cycle() -> void:
	while true:
		var dish := _next_racked_dish()
		if dish == null:
			break
		dish.begin_wash(machine.global_position + Vector3.UP * 0.75)
		await get_tree().create_timer(WASH_INTERVAL).timeout
		if not is_instance_valid(dish):
			break
		dish.finish_wash(_next_shelf_spot())
	washing = false

func _next_racked_dish() -> Dish:
	for d in DishLedger.dishes:
		if d.state == Dish.State.AT_PIT:
			return d
	return null

func _next_shelf_spot() -> Vector3:
	var col := shelf_count % 4
	var row := floori(shelf_count / 4.0)
	shelf_count += 1
	var local_offset := Vector3(-0.45 + col * 0.3, 0.03, -0.5 + row * 0.35)
	return shelf_base.global_position + shelf_base.global_transform.basis * local_offset
