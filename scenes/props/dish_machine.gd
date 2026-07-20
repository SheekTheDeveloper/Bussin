class_name DishMachine
extends StaticBody3D
## The dishwasher. Interact (E / Square) starts a cycle: pulls AT_PIT dishes
## one at a time into the chamber, then places them CLEAN on the output
## counter. Standalone prop - upgrades (faster interval, batch washing) are
## just exported values or a swapped scene.

const WASH_INTERVAL := 1.2

@export var output_counter_path: NodePath

var washing := false
var _was_washing := false
var _wash_loop: AudioStreamPlayer3D = null
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
	# Owned loop rather than a pooled one-shot: it runs for the whole cycle and
	# has to be stoppable independently of every other sound in the room.
	_wash_loop = Audio.make_loop_3d(&"machine_loop", self, -6.0)

func _physics_process(_delta: float) -> void:
	# Lamp AND wash audio are both derived from replicated dish states, so they
	# stay in sync on clients without any extra replication. `washing` itself is
	# server-only truth - do not drive presentation from it.
	var busy := DishLedger.count(Dish.State.WASHING) > 0
	if _lamp != null:
		var c := Color(0.25, 0.9, 0.35) if busy else Color(0.9, 0.15, 0.1)
		_lamp_mat.albedo_color = c
		_lamp_mat.emission = c
	_update_wash_audio(busy)

## Start/stop the hum on the edge, and punctuate the end of a load with the
## pneumatic hiss. Edge-triggered so the hiss fires once per cycle, not per frame.
func _update_wash_audio(busy: bool) -> void:
	if busy == _was_washing:
		return
	_was_washing = busy
	if _wash_loop == null:
		return
	if busy:
		_wash_loop.play()
	else:
		_wash_loop.stop()
		Audio.play_3d(&"machine_done", global_position, -2.0)

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
