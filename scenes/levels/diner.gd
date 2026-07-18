extends Node3D
## The diner graybox. Server spawns one Busser per peer under $Players;
## the MultiplayerSpawner replicates them to every client.

const BUSSER_SCENE := preload("res://scenes/actors/busser.tscn")

@onready var players := $Players as Node3D
@onready var spawn_points: Array[Node] = $SpawnPoints.get_children()

func _ready() -> void:
	GameState.start_shift()
	if multiplayer.is_server():
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

func _despawn_player(id: int) -> void:
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
