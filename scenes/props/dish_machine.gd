class_name DishMachine
extends StaticBody3D
## The dishwasher. Interact (E / Square) starts a cycle: pulls AT_PIT dishes
## one at a time into the chamber, then places them CLEAN on the output
## counter. Standalone prop - upgrades (faster interval, batch washing) are
## just exported values or a swapped scene.

const WASH_INTERVAL := 1.2

@export var output_counter_path: NodePath

var washing := false
var _lamp: MeshInstance3D = null
var _lamp_mat := StandardMaterial3D.new()

@onready var output_counter: CleanCounter = get_node(output_counter_path) as CleanCounter

func _ready() -> void:
	# The status lamp is a named object inside the imported machine GLB.
	var lamps := $Model.find_children("Lamp*", "MeshInstance3D", true, false)
	if not lamps.is_empty():
		_lamp = lamps[0]
		_lamp_mat.emission_enabled = true
		_lamp.material_override = _lamp_mat
	if output_counter == null:
		push_error("DishMachine has no output CleanCounter assigned")

func _physics_process(_delta: float) -> void:
	# Lamp: red idle, green washing - derived from replicated dish states,
	# so it works on clients without extra sync.
	if _lamp != null:
		var busy := DishLedger.count(Dish.State.WASHING) > 0
		var c := Color(0.25, 0.9, 0.35) if busy else Color(0.9, 0.15, 0.1)
		_lamp_mat.albedo_color = c
		_lamp_mat.emission = c

func interact(_player: Busser) -> void:
	start_cycle()

func start_cycle() -> void:
	if washing or not multiplayer.is_server() or output_counter == null:
		return
	washing = true
	_run_cycle()

func _run_cycle() -> void:
	while true:
		var dish := _next_racked_dish()
		if dish == null:
			break
		dish.begin_wash(global_position + Vector3.UP * 0.9)
		await get_tree().create_timer(WASH_INTERVAL).timeout
		if not is_instance_valid(dish):
			break
		dish.finish_wash(output_counter.next_spot())
	washing = false

func _next_racked_dish() -> Dish:
	for d in DishLedger.dishes:
		if d.state == Dish.State.AT_PIT:
			return d
	return null
