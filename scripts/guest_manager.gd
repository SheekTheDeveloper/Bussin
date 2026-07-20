class_name GuestManager
extends Node
## Server-side host stand: spawns parties at the door, queues them, seats
## them at READY tables, and handles walkouts when the queue backs up. Guests
## pathfind to their destinations with a NavigationAgent over the baked navmesh
## (see diner.gd), and replicate to clients through the GuestSpawner.

const GUEST_SCENE := preload("res://scenes/actors/guest.tscn")
## Guest pressure scales with crew size so per-person workload stays roughly
## flat: solo is casual, a full crew is slammed. Interval shrinks and the queue
## deepens as more bussers clock in.
const BASE_SPAWN_INTERVAL := 14.0   # solo cadence (gentle - one busser can keep up)
const PER_PLAYER_SPEEDUP := 0.72    # each extra busser multiplies the interval
const MIN_SPAWN_INTERVAL := 4.0     # floor, so 4-tops never machine-gun the door
const BASE_QUEUE_PATIENCE := 45.0   # solo grace before a queued party bails
const MIN_QUEUE_PATIENCE := 30.0    # a full crew gets the tighter original patience
const BASE_MAX_QUEUE := 3           # +1 slot per extra busser
const DOOR := Vector3(-8.5, 0.1, 6.3)

var _parties: Array = []       # queued: {guests, born, seated_count}
var _spawn_timer := 3.0
var _guest_seq := 0

# Headless soak harness: run with env BUSSER_SOAK=1 to auto-feed the pass and
# print lifecycle telemetry. Inert in normal play.
var _soak := OS.get_environment("BUSSER_SOAK") == "1"
var _soak_t := 0.0
var _soak_fed := false
var _soak_report := 0

@onready var guests_root := $"../Guests" as Node3D
@onready var tables: Array[Node] = $"../Tables".get_children()
@onready var kitchen := $"../KitchenPass" as KitchenPass
@onready var players_root := $"../Players" as Node3D

func _ready() -> void:
	if not multiplayer.is_server():
		set_process(false)

func _process(delta: float) -> void:
	if not GameState.running:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _parties.size() < _max_queue():
		_spawn_timer = _spawn_interval() * randf_range(0.8, 1.2)
		_spawn_party()
	_try_seat_front_party()
	_check_patience(delta)
	if _soak:
		_soak_tick(delta)

## Live crew size (server truth). At least 1 so the math never divides by an
## empty diner during the spawn frame before players attach.
func _player_count() -> int:
	return maxi(players_root.get_child_count(), 1)

## Spawn cadence tightens with each extra busser, floored so a big crew still
## gets gaps between parties.
func _spawn_interval() -> float:
	var players := _player_count()
	return maxf(BASE_SPAWN_INTERVAL * pow(PER_PLAYER_SPEEDUP, players - 1), MIN_SPAWN_INTERVAL)

## Deeper queue with more hands on deck, capped by how many parties can wait.
func _max_queue() -> int:
	return mini(BASE_MAX_QUEUE + (_player_count() - 1), tables.size())

## Queued parties are more patient when the diner is short-staffed, since one
## busser turns tables slower; a full crew gets the tighter original window.
func _queue_patience() -> float:
	return maxf(BASE_QUEUE_PATIENCE - (_player_count() - 1) * 5.0, MIN_QUEUE_PATIENCE)

func _soak_tick(delta: float) -> void:
	_soak_t += delta
	if _soak_t > 12.0 and not _soak_fed:
		_soak_fed = true
		var moved := 0
		for d in DishLedger.dishes:
			if d.state == Dish.State.CLEAN and moved < 6:
				d.global_position = kitchen.zone.global_position + Vector3(-1.0 + moved * 0.4, 0.0, 0.0)
				moved += 1
		print("[soak t=%.0f] fed %d clean plates to the pass" % [_soak_t, moved])
	if int(_soak_t) / 15 > _soak_report:
		_soak_report = int(_soak_t) / 15
		var states := {}
		for d in DishLedger.dishes:
			states[d.state] = states.get(d.state, 0) + 1
		print("[soak t=%.0f] guests=%d covers=%d walkouts=%d dish_states=%s" % [
			_soak_t, get_tree().get_nodes_in_group("guests").size(),
			GameState.covers, GameState.walkouts, str(states)])
	if _soak_t > 75.0:
		print("SOAK FINAL: covers=%d walkouts=%d -> %s" % [GameState.covers,
				GameState.walkouts, "OK" if GameState.covers > 0 else "FAIL"])
		get_tree().quit()

func _spawn_party() -> void:
	var size := randi_range(1, 4)
	var party := {"guests": [], "born": 0.0, "seated_count": 0}
	for i in size:
		_guest_seq += 1
		var g := GUEST_SCENE.instantiate() as Guest
		g.name = "Guest%d" % _guest_seq
		guests_root.add_child(g, true)
		g.global_position = DOOR + Vector3(0.3 * i, 0.0, randf_range(-0.2, 0.2))
		g.arrived.connect(_on_guest_arrived)
		g.finished_eating.connect(_on_guest_finished_eating)
		party["guests"].append(g)
	_parties.append(party)
	_restack_queue()

func _restack_queue() -> void:
	var slot := 0
	for party in _parties:
		for g in party["guests"]:
			var spot := DOOR + Vector3(0.7 * slot, 0.0, 0.0)
			if g.activity == Guest.Activity.QUEUED or g.purpose == "queueing":
				g.walk_to(spot, "queueing")
			slot += 1

func _try_seat_front_party() -> void:
	if _parties.is_empty():
		return
	var party: Dictionary = _parties[0]
	var table := _find_ready_table()
	if table == null:
		return
	_parties.pop_front()
	var guests: Array = party["guests"]
	table.party = guests.duplicate()
	for i in guests.size():
		var g := guests[i] as Guest
		g.table = table
		g.seat_index = i
		g.walk_to(table.seat_global(i), "seating")
	party["seated_count"] = 0
	party["table"] = table
	_restack_queue()

func _find_ready_table() -> DinerTable:
	for t in tables:
		if t is DinerTable and t.is_ready_for_party():
			return t
	return null

func _check_patience(delta: float) -> void:
	var patience := _queue_patience()
	for party in _parties.duplicate():
		party["born"] += delta
		if party["born"] > patience:
			_parties.erase(party)
			for g in party["guests"]:
				g.walk_to(DOOR, "walkout")
			GameState.add_walkout()
	_restack_queue()

func _on_guest_arrived(g: Guest) -> void:
	match g.purpose:
		"seating":
			g.activity = Guest.Activity.WAITING_FOOD
			g.rotation.y = atan2(-(g.table.global_position.x - g.global_position.x),
					-(g.table.global_position.z - g.global_position.z))
			var seated := 0
			for other in g.table.party:
				if is_instance_valid(other) and other.activity != Guest.Activity.WALKING:
					seated += 1
			if seated == g.table.party.size():
				kitchen.place_order(g.table.party)
		"leaving", "walkout":
			g.queue_free()
		"queueing":
			g.activity = Guest.Activity.QUEUED

func _on_guest_finished_eating(g: Guest) -> void:
	var table := g.table
	if table == null:
		return
	for other in table.party:
		if is_instance_valid(other) and other.purpose != "done":
			return  # party still eating; wait
	# whole party done -> leave together, mess stays on the table
	var size := table.party.size()
	for other in table.party:
		if is_instance_valid(other):
			other.table = null
			other.walk_to(DOOR, "leaving")
	table.party = []
	GameState.add_cover(size)
