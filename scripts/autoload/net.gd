extends Node
## Autoload "Net" - connection lifecycle. Host-as-server over ENet.
## Gameplay code never touches peers directly; it only checks multiplayer.is_server().

const PORT := 7777
const MAX_PLAYERS := 4
const DINER_SCENE := "res://scenes/levels/diner.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"

signal join_failed(reason: String)

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

## Solo is the fast path - no crew to wait on, so it skips the lobby and drops
## straight onto the floor.
func play_solo() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file(DINER_SCENE)

## Host + join both land in the lobby (waiting room); the host starts the shift
## from there, which loads the diner on every peer.
func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		join_failed.emit("Could not open port %d (%s)" % [PORT, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(LOBBY_SCENE)

func join_game(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		join_failed.emit(error_string(err))
		return
	multiplayer.multiplayer_peer = peer

func back_to_menu() -> void:
	Audio.stop_all()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_connected_to_server() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit("Connection failed - check the IP and that a host is running.")

func _on_server_disconnected() -> void:
	back_to_menu()
