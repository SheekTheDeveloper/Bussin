extends Node
## Headless integration harness for the RETURN half of the dish loop:
##   DIRTY -> HELD -> AT_PIT -> WASHING -> CLEAN -> AT_PASS
##
## The guest soak (BUSSER_SOAK=1, see guest_manager.gd) proves the AI half, but
## it cannot press a button, so the player half had no automated coverage. This
## harness fills that hole by driving a real Busser through the same
## server-side entry points a client's intent RPCs land on
## (_server_grab_or_drop / _server_interact) and asserting the state machine
## after each step.
##
## Run it:
##   BUSSER_RETURN_SOAK=1 godot --headless --path . res://scenes/levels/diner.tscn
##
## Exit code 0 = every check passed, 1 = something regressed. Inert (zero cost)
## unless that env var is set.
##
## What this DOES prove: the dish state machine, the grab/stack/drop verbs, the
## tub scoop/carry/dump path, the machine cycle, and pass delivery all still
## work end to end on the server.
## What it does NOT prove: game FEEL. Reach angles, carry speed, wobble, and
## throw arcs still need a human in the editor. This is a regression net, not a
## substitute for playing it.

const SETTLE_TIMEOUT := 3.0     # ceiling for dropped dishes to fall into a station zone
const MACHINE_TIMEOUT := 12.0   # generous ceiling for a 3-dish wash cycle
const NEST_TOLERANCE := 0.6     # how close a stowed plate must stay to its tub (m)

var _enabled := OS.get_environment("BUSSER_RETURN_SOAK") == "1"
var _checks := 0
var _failures := 0

@onready var players := $"../Players" as Node3D
@onready var tables := $"../Tables" as Node3D
@onready var dirty_counter := $"../DirtyCounter" as DirtyCounter
@onready var machine := $"../DishMachine" as DishMachine
@onready var kitchen := $"../KitchenPass" as KitchenPass
@onready var tubs := $"../Tubs" as Node3D
@onready var guest_manager := $"../GuestManager" as GuestManager

func _ready() -> void:
	if not _enabled or not multiplayer.is_server():
		return
	_run.call_deferred()

# --- assertions -------------------------------------------------------------

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	var tag := "PASS" if ok else "FAIL"
	print("  [%s] %s%s" % [tag, label, "" if detail.is_empty() else "  (%s)" % detail])

func _check_state(label: String, dishes: Array, want: int) -> void:
	var wrong := 0
	for d in dishes:
		if not is_instance_valid(d) or d.state != want:
			wrong += 1
	_check(label, wrong == 0, "%d/%d not in %s" % [wrong, dishes.size(), _state_name(want)])

func _has_wrong_state(dishes: Array, want: int) -> bool:
	for d in dishes:
		if not is_instance_valid(d) or d.state != want:
			return true
	return false

func _state_name(s: int) -> String:
	return Dish.State.keys()[s]

## Diagnostic dump for the pit-zone checks, so a failure says WHY (out of the
## zone? collider still muted? area not monitoring?) instead of just "not AT_PIT".
func _dump_zone(label: String, zone: Area3D, dishes: Array) -> void:
	var bodies := zone.get_overlapping_bodies()
	print("    ~ %s: zone=%s monitoring=%s overlapping=%d" % [
		label, str(zone.global_position), str(zone.monitoring), bodies.size()])
	for d in dishes:
		if is_instance_valid(d):
			print("      dish pos=%s dist=%.2f state=%s layer=%d frozen=%s" % [
				str(d.global_position), d.global_position.distance_to(zone.global_position),
				_state_name(d.state), d.collision_layer, str(d.freeze)])

# --- helpers ----------------------------------------------------------------

func _frames(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame

## Poll until every dish reaches `want`, or give up after `timeout` seconds.
## Dropped plates fall into a station's trigger zone under gravity and the zone
## flags them a frame or two later, so the settle time is physical, not fixed -
## polling keeps the harness from failing on timing instead of on behavior.
func _await_state(dishes: Array, want: int, timeout: float = SETTLE_TIMEOUT) -> void:
	var waited := 0.0
	while waited < timeout:
		var done := true
		for d in dishes:
			if not is_instance_valid(d) or d.state != want:
				done = false
				break
		if done:
			return
		await get_tree().physics_frame
		waited += 1.0 / 60.0

## Teleport the busser so its head sits at `pos`, putting anything there well
## inside GRAB_RANGE. Locomotion is not what this harness tests, so the body is
## moved directly rather than walked.
func _head_to(busser: Busser, pos: Vector3) -> void:
	busser.global_position += pos - busser.head.global_position

## Teleport the busser so its hold point sits exactly at `pos`, so a dropped
## stack lands precisely where we want it (inside a station's trigger zone)
## instead of depending on where the body happened to stop.
func _hold_point_to(busser: Busser, pos: Vector3) -> void:
	busser.global_position += pos - busser.hold_point.global_position

## Reset dishes to a known DIRTY state parked on a table, clear of every
## station zone, so each test starts from the same place.
func _stage_dirty(count: int, exclude: Array) -> Array:
	var staged: Array = []
	var table := tables.get_child(0) as Node3D
	for d in DishLedger.dishes:
		if staged.size() >= count:
			break
		if d in exclude or d.holder != null or d.in_tub != null or d.state == Dish.State.BROKEN:
			continue
		d.freeze = true
		d.global_position = table.global_position + Vector3(0.0, 1.2, 0.0) + Vector3(0.3 * staged.size(), 0.0, 0.0)
		d.state = Dish.State.DIRTY
		staged.append(d)
	return staged

# --- the run ----------------------------------------------------------------

func _run() -> void:
	await _frames(6)  # let the level spawn its player and bake the navmesh

	var busser := players.get_child(0) as Busser if players.get_child_count() > 0 else null
	if busser == null:
		print("RETURN SOAK: no Busser spawned - cannot run")
		get_tree().quit(1)
		return

	# Freeze the AI half so guests can't seat, eat, or re-dirty plates mid-check.
	# The return half is what's under test here; the guest soak covers the rest.
	guest_manager.set_process(false)
	for g in get_tree().get_nodes_in_group("guests"):
		g.queue_free()
	# Locomotion is out of scope and would fight the teleports.
	busser.set_physics_process(false)
	await _frames(2)

	print("=== RETURN-HALF SOAK ===")
	var hand_dishes := await _test_hand_to_pit(busser)
	await _test_machine_cycle(busser, hand_dishes)
	await _test_deliver_to_pass(busser, hand_dishes)
	await _test_tub_path(busser)

	print("=== RETURN SOAK: %d/%d checks passed ===" % [_checks - _failures, _checks])
	print("RETURN SOAK FINAL: %s" % ("OK" if _failures == 0 else "FAIL"))
	get_tree().quit(1 if _failures > 0 else 0)

## DIRTY -> HELD (hand stack) -> AT_PIT, the bare-hands bussing run.
func _test_hand_to_pit(busser: Busser) -> Array:
	print("[1] hand-stack: table -> pit counter")
	var dishes := _stage_dirty(3, [])
	if dishes.size() < 3:
		_check("staged 3 dirty plates", false, "only got %d" % dishes.size())
		return dishes

	for i in dishes.size():
		var d := dishes[i] as Dish
		_head_to(busser, d.global_position)
		busser._server_grab_or_drop(d.get_path())
		_check("grab plate %d -> HELD" % (i + 1), d.state == Dish.State.HELD, _state_name(d.state))
	_check("stack_load tracks the hand stack", busser.stack_load == 3, "got %d" % busser.stack_load)
	# HELD plates are driven to the hold point in Dish._physics_process, so let a
	# frame pass or they would still be sitting back on the table when released.
	await _frames(2)

	# Set the whole run down in the pit's drop zone. Aiming at nothing is what
	# drops a stack, so we pass an empty path exactly like the client does.
	_hold_point_to(busser, dirty_counter.zone.global_position)
	await _frames(2)
	busser._server_grab_or_drop(NodePath())
	_check("hand stack released", busser.stack_load == 0, "got %d" % busser.stack_load)
	await _await_state(dishes, Dish.State.AT_PIT)
	if _has_wrong_state(dishes, Dish.State.AT_PIT):
		_dump_zone("hand-drop", dirty_counter.zone, dishes)
	_check_state("plates flagged AT_PIT", dishes, Dish.State.AT_PIT)
	return dishes

## AT_PIT -> WASHING -> CLEAN, driven by interacting with the machine.
func _test_machine_cycle(busser: Busser, dishes: Array) -> void:
	print("[2] dish machine: AT_PIT -> WASHING -> CLEAN")
	_head_to(busser, machine.global_position)
	busser._server_interact(machine.get_path())
	_check("machine accepted interact", machine.washing)

	var waited := 0.0
	while waited < MACHINE_TIMEOUT:
		var done := true
		for d in dishes:
			if is_instance_valid(d) and d.state != Dish.State.CLEAN:
				done = false
				break
		if done:
			break
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	_check_state("plates came out CLEAN", dishes, Dish.State.CLEAN)
	_check("machine cycle finished", not machine.washing)

## CLEAN -> AT_PASS: the expo run that feeds the kitchen. If this breaks, the
## chef starves and the whole economy stalls.
func _test_deliver_to_pass(busser: Busser, dishes: Array) -> void:
	print("[3] expo run: clean shelf -> kitchen pass")
	var carried: Array = []
	for d in dishes:
		if not is_instance_valid(d) or d.state != Dish.State.CLEAN:
			continue
		_head_to(busser, d.global_position)
		busser._server_grab_or_drop(d.get_path())
		if d.state == Dish.State.HELD:
			carried.append(d)
	_check("picked up the clean run", carried.size() > 0, "%d plates" % carried.size())

	await _frames(2)
	_hold_point_to(busser, kitchen.zone.global_position)
	await _frames(2)
	busser._server_grab_or_drop(NodePath())
	await _await_state(carried, Dish.State.AT_PASS)
	_check_state("plates staged AT_PASS", carried, Dish.State.AT_PASS)

## The bus-tub path, including a regression check on the fix from GDD 10:
## stowed plates must stay nested in the tub after it is SET DOWN, not float
## at the old hold point.
func _test_tub_path(busser: Busser) -> void:
	print("[4] bus tub: scoop -> set down -> carry -> dump at pit")
	var dishes := _stage_dirty(3, [])
	var tub := tubs.get_child(0) as BusTub

	_head_to(busser, tub.global_position)
	busser._server_grab_or_drop(tub.get_path())
	_check("picked up the tub", busser.carried_tub == tub)

	for i in dishes.size():
		var d := dishes[i] as Dish
		_head_to(busser, d.global_position)
		busser._server_grab_or_drop(d.get_path())
		_check("scooped plate %d into the tub" % (i + 1), d.in_tub == tub)
	_check("tub contents tracked", tub.contents.size() == dishes.size(), "got %d" % tub.contents.size())
	_check("carry_load mirrors the tub", busser.carry_load == dishes.size(), "got %d" % busser.carry_load)

	# Regression: set the tub down and confirm the plates ride it to the floor.
	# The old bug stopped driving contents once carrier was null, leaving them
	# frozen in mid-air at the hold point.
	busser._server_grab_or_drop(NodePath())
	_check("tub set down", busser.carried_tub == null)
	await _frames(20)
	var floating := 0
	for d in dishes:
		if not is_instance_valid(d) or d.global_position.distance_to(tub.global_position) > NEST_TOLERANCE:
			floating += 1
	_check("plates stayed nested in the grounded tub", floating == 0, "%d floated free" % floating)

	# Pick it back up and dump it at the pit the way a player would.
	_head_to(busser, tub.global_position)
	busser._server_grab_or_drop(tub.get_path())
	_check("picked the loaded tub back up", busser.carried_tub == tub)
	_head_to(busser, dirty_counter.global_position)
	busser._server_interact(dirty_counter.get_path())
	_check("tub emptied on dump", tub.contents.is_empty(), "%d left" % tub.contents.size())
	_check("carry_load reset to empty tub", busser.carry_load == 0, "got %d" % busser.carry_load)
	await _await_state(dishes, Dish.State.AT_PIT)
	if _has_wrong_state(dishes, Dish.State.AT_PIT):
		_dump_zone("tub-dump", dirty_counter.zone, dishes)
	_check_state("dumped plates flagged AT_PIT", dishes, Dish.State.AT_PIT)
