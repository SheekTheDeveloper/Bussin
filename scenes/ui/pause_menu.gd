extends CanvasLayer
## In-shift pause overlay ("ON BREAK"). Client-local only: co-op is
## server-authoritative, so this never stops the sim - it just frees the cursor
## and offers Resume / Settings / bail-out. Toggled by the `pause` action
## (Esc / gamepad Start). Lives in diner.tscn above the HUD.

const _MUTED := Color(0.42, 0.4471, 0.502)

var _open := false
var _settings: SettingsPanel = null
var _root: Control = null
var _first_button: Button = null

func _ready() -> void:
	layer = 10  # above the HUD (layer 1)
	_build()
	_root.visible = false

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = preload("res://ui/theme/busser_theme.tres")
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.043, 0.055, 0.09, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := Label.new()
	title.text = "ON BREAK"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.98, 0.8, 0.0824))
	col.add_child(title)

	var sub := Label.new()
	sub.text = "the floor doesn't stop for the crew"
	sub.add_theme_color_override("font_color", _MUTED)
	col.add_child(sub)

	var rule := ColorRect.new()
	rule.color = Color(0.976, 0.98, 0.984, 0.12)
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)

	_first_button = _add_button(col, "▶  BACK TO THE FLOOR", _resume)
	_add_button(col, "SHIFT SETTINGS", _open_settings)
	_add_button(col, "RETURN TO BREAKROOM", Net.back_to_menu)
	_add_button(col, "CLOCK OUT", func(): get_tree().quit())

func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	# No mid-report pausing - once the shift is over the report card owns input.
	if not _open and not GameState.running:
		return
	# If settings is up, Esc backs out of it first, one layer at a time.
	if _settings != null:
		return
	get_viewport().set_input_as_handled()
	if _open:
		_resume()
	else:
		_pause()

func _pause() -> void:
	_open = true
	_root.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_first_button.grab_focus()

func _resume() -> void:
	_open = false
	_root.visible = false
	# Only recapture for a live first-person busser on this client.
	if Busser.local != null and is_instance_valid(Busser.local):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsPanel.new()
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)

func _on_settings_closed() -> void:
	_settings = null
	# Return focus to the pause list.
	if _open:
		_first_button.grab_focus()
