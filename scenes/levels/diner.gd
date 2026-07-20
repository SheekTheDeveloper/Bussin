extends Node3D
## The diner graybox. Server spawns one Busser per peer under $Players;
## the MultiplayerSpawner replicates them to every client.

const BUSSER_SCENE := preload("res://scenes/actors/busser.tscn")

@onready var players := $Players as Node3D
@onready var spawn_points: Array[Node] = $SpawnPoints.get_children()
@onready var nav_region := $NavRegion as NavigationRegion3D

func _ready() -> void:
	GameState.start_shift()
	if multiplayer.is_server():
		# Bake the guest navmesh from the level's static colliders (group
		# "nav_geo" = this scene). Deferred so runtime-built collision (the tub
		# rack) is already in the tree. Only the server pathfinds guests, so only
		# it needs the baked mesh; clients just receive replicated positions.
		nav_region.call_deferred("bake_navigation_mesh", false)
		multiplayer.peer_connected.connect(_spawn_player)
		multiplayer.peer_disconnected.connect(_despawn_player)
		_spawn_player(multiplayer.get_unique_id())
		for id in multiplayer.get_peers():
			_spawn_player(id)

func _exit_tree() -> void:
	GameState.stop_shift()
	if multiplayer.is_server():
		if multiplayer.peer_connected.is_connected(_spawn_player):
			multiplayer.peer_connected.disconnect(_spawn_player)
		if multiplayer.peer_disconnected.is_connected(_despawn_player):
			multiplayer.peer_disconnected.disconnect(_despawn_player)

func _spawn_player(id: int) -> void:
	if players.has_node(str(id)):
		return
	var busser := BUSSER_SCENE.instantiate() as Busser
	busser.name = str(id)
	players.add_child(busser, true)
	var idx := players.get_child_count() - 1
	busser.global_position = (spawn_points[idx % spawn_points.size()] as Node3D).global_position
	_apply_crew_difficulty()

func _despawn_player(id: int) -> void:
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
		# Node frees next frame; count it as gone now.
		_apply_crew_difficulty(1)

## Server-only: scale forgiveness to crew size. Solo gets extra walkout grace
## (7), tightening to the stock 5 as the crew fills - mirrors the guest-pressure
## scaling in GuestManager so the shift stays winnable at any headcount.
func _apply_crew_difficulty(leaving: int = 0) -> void:
	var crew := maxi(players.get_child_count() - leaving, 1)
	GameState.set_walkout_limit.rpc(clampi(8 - crew, GameState.BASE_WALKOUT_LIMIT, 7))
