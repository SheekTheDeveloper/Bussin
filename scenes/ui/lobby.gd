extends Control
## BREAKROOM LOBBY - the multiplayer waiting room. Host and joined clients land
## here after connecting (solo skips it, see Net.play_solo). The server owns the
## authoritative ready roster and broadcasts it; clients just mirror + render it.
## The host starts the shift once the whole crew is READY, which loads the diner
## on every peer at once.
##
## RPCs work peer-to-peer because this is the current scene on every client, so
## its node path (/root/Lobby) matches everywhere - same trick the GameState /
## DishLedger autoloads rely on.

const THEME := preload("res://ui/theme/busser_theme.tres")
const _YELLOW := Color(0.98, 0.8, 0.0824)
const _GREEN := Color(0.29, 0.8706, 0.502)
const _MUTED := Color(0.42, 0.4471, 0.502)

## peer_id -> ready(bool). Server truth; clients receive it via _sync_roster.
var _roster: Dictionary = {}
var _local_ready := false

var _crew: RichTextLabel = null
var _ready_btn: Button = null
var _start_btn: Button = null
var _hint: Label = null

func _ready() -> void:
	theme = THEME
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build()
	# Only the server tracks connect/disconnect and mutates the roster; clients
	# stay passive and render whatever the server broadcasts.
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_joined)
		multiplayer.peer_disconnected.connect(_on_peer_left)
		_roster[multiplayer.get_unique_id()] = false
		_broadcast()
	else:
		# Announce arrival so the server (re)broadcasts the roster to us - the
		# server's peer_connected for us may have fired before this scene existed.
		_hello.rpc_id(1)
	_render()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.custom_minimum_size = Vector2(520, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.add_child(col)

	var title := Label.new()
	title.text = "BREAKROOM LOBBY"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", _YELLOW)
	col.add_child(title)

	var mode := Label.new()
	mode.text = "HOSTING - WAITING FOR CREW" if multiplayer.is_server() else "CONNECTED - WAITING FOR HOST"
	mode.add_theme_color_override("font_color", _MUTED)
	col.add_child(mode)

	var rule := ColorRect.new()
	rule.color = Color(0.976, 0.98, 0.984, 0.12)
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)

	var panel := PanelContainer.new()
	col.add_child(panel)
	_crew = RichTextLabel.new()
	_crew.bbcode_enabled = true
	_crew.fit_content = true
	_crew.scroll_active = false
	_crew.custom_minimum_size = Vector2(0, 140)
	panel.add_child(_crew)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)

	_ready_btn = Button.new()
	_ready_btn.text = "READY UP"
	_ready_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_btn.pressed.connect(_on_ready_pressed)
	buttons.add_child(_ready_btn)

	if multiplayer.is_server():
		_start_btn = Button.new()
		_start_btn.text = "START SHIFT"
		_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_start_btn.pressed.connect(_on_start_pressed)
		buttons.add_child(_start_btn)

	var leave := Button.new()
	leave.text = "◄ CLOCK OUT"
	leave.pressed.connect(Net.back_to_menu)
	col.add_child(leave)

	_hint = Label.new()
	_hint.add_theme_color_override("font_color", _MUTED)
	_hint.add_theme_font_size_override("font_size", 13)
	col.add_child(_hint)

	_ready_btn.grab_focus()

## --- Server: roster maintenance -------------------------------------------

func _on_peer_joined(id: int) -> void:
	_roster[id] = false
	_broadcast()

func _on_peer_left(id: int) -> void:
	_roster.erase(id)
	_broadcast()

func _broadcast() -> void:
	# Parallel arrays keep the RPC to plain types. call_local so the host applies
	# the same snapshot it sends everyone else.
	var ids := PackedInt32Array()
	var readies := PackedByteArray()
	for id in _roster:
		ids.append(id)
		readies.append(1 if _roster[id] else 0)
	_sync_roster.rpc(ids, readies)

@rpc("authority", "call_local", "reliable")
func _sync_roster(ids: PackedInt32Array, readies: PackedByteArray) -> void:
	_roster.clear()
	for i in ids.size():
		_roster[ids[i]] = readies[i] == 1
	_render()

@rpc("any_peer", "call_remote", "reliable")
func _hello() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _roster.has(id):
		_roster[id] = false
	_broadcast()

@rpc("any_peer", "call_local", "reliable")
func _set_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	# A host toggling its own ready calls this locally; sender id is 0 for a
	# local call, so resolve it to the host's own id.
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	_roster[id] = value
	_broadcast()

## --- Local input ----------------------------------------------------------

func _on_ready_pressed() -> void:
	_local_ready = not _local_ready
	_ready_btn.text = "READY  ✓" if _local_ready else "READY UP"
	_set_ready.rpc_id(1, _local_ready)

func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	_begin.rpc()

@rpc("authority", "call_local", "reliable")
func _begin() -> void:
	get_tree().change_scene_to_file(Net.DINER_SCENE)

## --- Render ---------------------------------------------------------------

func _render() -> void:
	if _crew == null:
		return
	var ids := _roster.keys()
	ids.sort()
	var me := multiplayer.get_unique_id()
	var all_ready := ids.size() > 0
	var lines := PackedStringArray()
	var slot := 1
	for id in ids:
		var ready: bool = _roster[id]
		if not ready:
			all_ready = false
		var who := "YOU" if id == me else "PLAYER %d" % id
		var host_tag := "  (HOST)" if id == 1 else ""
		var status := "[color=#4ade80]READY[/color]" if ready else "[color=#6b7280]waiting…[/color]"
		lines.append("%d   %-14s %s%s" % [slot, who + host_tag, status, ""])
		slot += 1
	_crew.text = "[b]CREW (%d/%d)[/b]\n\n%s" % [ids.size(), Net.MAX_PLAYERS, "\n".join(lines)]

	if _start_btn != null:
		# Host can only start once every connected busser (itself included) is READY.
		_start_btn.disabled = not all_ready
		_hint.text = "" if all_ready else "start unlocks when the whole crew is READY"
	elif not _hint.text.begins_with("waiting"):
		_hint.text = "waiting for the host to start the shift…"
