extends Control
## Breakroom (main menu). Diegetic nav over the Busser design system: CLOCK IN =
## solo, HOST SHIFT = open an ENet server, JOIN CREW = connect to a host,
## CLOCK OUT = quit. Functionality is unchanged from the old Solo/Host/Join menu;
## only the voice and skin match the Figma mockup now.

@onready var ip_edit := %IpEdit as LineEdit
@onready var status := %Status as Label
@onready var join_row := %JoinRow as HBoxContainer
@onready var lobby_line := %LobbyLine as Label

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	(%ClockIn as Button).pressed.connect(Net.play_solo)
	(%HostShift as Button).pressed.connect(_on_host)
	(%JoinCrew as Button).pressed.connect(_on_toggle_join)
	(%JoinGo as Button).pressed.connect(_on_join)
	%IpEdit.text_submitted.connect(func(_t): _on_join())
	Net.join_failed.connect(_on_join_failed)
	(%ShiftSettings as Button).pressed.connect(_open_settings)
	(%ClockOut as Button).pressed.connect(func(): get_tree().quit())
	(%ClockIn as Button).grab_focus()  # controller menu navigation

var _settings: SettingsPanel = null

## Open the shared settings overlay (same panel the in-shift pause menu uses).
func _open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsPanel.new()
	_settings.closed.connect(func():
		_settings = null
		(%ShiftSettings as Button).grab_focus())
	add_child(_settings)

func _on_host() -> void:
	status.text = "OPENING PORT %d…" % Net.PORT
	lobby_line.text = "LOBBY  //  HOSTING"
	Net.host_game()

func _on_toggle_join() -> void:
	join_row.visible = not join_row.visible
	if join_row.visible:
		ip_edit.grab_focus()

func _on_join() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	status.text = "CONNECTING TO %s…" % ip
	Net.join_game(ip)

func _on_join_failed(reason: String) -> void:
	status.text = reason.to_upper()
