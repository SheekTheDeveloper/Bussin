extends Control

@onready var ip_edit := $Center/VBox/JoinRow/IpEdit as LineEdit
@onready var status := $Center/VBox/Status as Label

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	($Center/VBox/SoloButton as Button).pressed.connect(Net.play_solo)
	($Center/VBox/SoloButton as Button).grab_focus()  # controller menu navigation
	($Center/VBox/HostButton as Button).pressed.connect(_on_host)
	($Center/VBox/JoinRow/JoinButton as Button).pressed.connect(_on_join)
	Net.join_failed.connect(_on_join_failed)

func _on_host() -> void:
	status.text = "Hosting on port %d..." % Net.PORT
	Net.host_game()

func _on_join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	status.text = "Connecting to %s..." % ip
	Net.join_game(ip)

func _on_join_failed(reason: String) -> void:
	status.text = reason
