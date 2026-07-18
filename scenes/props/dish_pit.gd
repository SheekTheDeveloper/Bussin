class_name DishPit
extends Node3D
## The dish pit: a drop counter, a pass-through machine, and a clean shelf.
## Server flags dirty dishes that land in the DropZone as AT_PIT, and the
## machine cycle converts AT_PIT -> WASHING -> CLEAN onto shelf slots.

const WASH_INTERVAL := 1.2

@onready var zone := $DropZone as Area3D
@onready var machine := $Machine as StaticBody3D
@onready var shelf_base := $ShelfBase as Node3D

var washing := false
var shelf_count := 0
var _lamp: MeshInstance3D = null
var _lamp_mat := StandardMaterial3D.new()

func _ready() -> void:
	# The status lamp is a named object inside the imported machine GLB.
	var lamps := $Machine/Model.find_children("Lamp*", "MeshInstance3D", true, false)
	if not lamps.is_empty():
		_lamp = lamps[0]
		_lamp_mat.emission_enabled = true
		_lamp.material_override = _lamp_mat

func _physics_process(_delta: float) -> void:
	# Lamp: red idle, green while a wash is in progress - derived from replicated
	# dish states, so it works on clients without extra sync.
	if _lamp != null:
		var busy := DishLedger.count(Dish.State.WASHING) > 0
		var c := Color(0.25, 0.9, 0.35) if busy else Color(0.9, 0.15, 0.1)
		_lamp_mat.albedo_color = c
		_lamp_mat.emission = c

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
