class_name SettingsPanel
extends Control
## Reusable SHIFT SETTINGS overlay, built in code and shared by the breakroom
## (main menu) and the in-shift pause menu. Reads/writes the Settings autoload,
## which persists everything to user://busser_settings.cfg. Emits `closed` when
## the player backs out so the host screen can restore focus/cursor.
##
## Built programmatically (no .tscn) so it stays a single drop-in component:
##   var s := SettingsPanel.new(); add_child(s); s.closed.connect(...)

signal closed

const THEME := preload("res://ui/theme/busser_theme.tres")
const _YELLOW := Color(0.98, 0.8, 0.0824)

## The action currently being rebound (empty = not capturing).
var _awaiting := ""
var _rebind_buttons: Dictionary = {}  # action -> Button

func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing behind reacts

	var dim := ColorRect.new()
	dim.color = Color(0.043, 0.055, 0.09, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	col.add_child(_heading("SHIFT SETTINGS", 24))
	col.add_child(_rule())

	# --- Audio ---
	col.add_child(_section("AUDIO"))
	col.add_child(_slider_row("MASTER VOLUME", 0.0, 1.0, 0.05, Settings.master_volume,
		Settings.set_master_volume, func(v): return "%d%%" % roundi(v * 100.0)))

	# --- Controls ---
	col.add_child(_section("CONTROLS"))
	col.add_child(_slider_row("MOUSE SENSITIVITY", Settings.MOUSE_SENS_MIN, Settings.MOUSE_SENS_MAX,
		0.05, Settings.mouse_sensitivity, Settings.set_mouse_sensitivity, func(v): return "%.2fx" % v))
	col.add_child(_slider_row("STICK SENSITIVITY", Settings.STICK_SENS_MIN, Settings.STICK_SENS_MAX,
		0.05, Settings.stick_sensitivity, Settings.set_stick_sensitivity, func(v): return "%.2fx" % v))
	col.add_child(_toggle_row("INVERT LOOK Y", Settings.invert_y, Settings.set_invert_y))

	# --- Video ---
	col.add_child(_section("VIDEO"))
	col.add_child(_toggle_row("FULLSCREEN", Settings.fullscreen, Settings.set_fullscreen))

	# --- Keybinds ---
	col.add_child(_section("KEY BINDINGS"))
	for pair in Settings.REBINDABLE:
		col.add_child(_bind_row(pair[0], pair[1]))
	var reset := Button.new()
	reset.text = "RESET BINDINGS TO DEFAULT"
	reset.pressed.connect(_on_reset_all)
	col.add_child(reset)

	col.add_child(_rule())
	var back := Button.new()
	back.text = "◄ BACK"
	back.pressed.connect(_close)
	col.add_child(back)
	back.grab_focus()

## --- Row builders ---------------------------------------------------------

func _heading(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _YELLOW)
	l.add_theme_constant_override("line_spacing", 2)
	return l

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.976, 0.98, 0.984, 0.12)
	r.custom_minimum_size = Vector2(0, 1)
	return r

func _label_cell(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(220, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## A labelled slider whose value is committed live through `setter`, with a
## right-aligned readout formatted by `fmt`.
func _slider_row(label: String, lo: float, hi: float, step: float, value: float,
		setter: Callable, fmt: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label_cell(label))
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(56, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = fmt.call(value)
	slider.value_changed.connect(func(v):
		setter.call(v)
		readout.text = fmt.call(v))
	row.add_child(slider)
	row.add_child(readout)
	return row

func _toggle_row(label: String, on: bool, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label_cell(label))
	var check := CheckButton.new()
	check.button_pressed = on
	check.toggled.connect(func(v): setter.call(v))
	row.add_child(check)
	return row

## One rebindable action: its name, and a button showing the current key that,
## when pressed, listens for the next key/mouse press to rebind to.
func _bind_row(action: String, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label_cell(label))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(180, 0)
	btn.text = Settings.label_for(action)
	btn.pressed.connect(func(): _begin_rebind(action))
	_rebind_buttons[action] = btn
	row.add_child(btn)
	return row

## --- Rebinding ------------------------------------------------------------

func _begin_rebind(action: String) -> void:
	_awaiting = action
	var btn := _rebind_buttons[action] as Button
	btn.text = "PRESS A KEY…"
	btn.add_theme_color_override("font_color", _YELLOW)

func _end_rebind() -> void:
	var action := _awaiting
	_awaiting = ""
	if _rebind_buttons.has(action):
		var btn := _rebind_buttons[action] as Button
		btn.remove_theme_color_override("font_color")
		btn.text = Settings.label_for(action)

func _input(event: InputEvent) -> void:
	if _awaiting == "":
		return
	# Escape cancels the capture without changing the binding.
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_end_rebind()
		get_viewport().set_input_as_handled()
		return
	var captured: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		var k := InputEventKey.new()
		k.physical_keycode = (event as InputEventKey).physical_keycode
		captured = k
	elif event is InputEventMouseButton and event.pressed:
		var m := InputEventMouseButton.new()
		m.button_index = (event as InputEventMouseButton).button_index
		captured = m
	if captured != null:
		Settings.rebind(_awaiting, captured)
		_end_rebind()
		get_viewport().set_input_as_handled()

func _on_reset_all() -> void:
	Settings.reset_all_bindings()
	for action in _rebind_buttons:
		(_rebind_buttons[action] as Button).text = Settings.label_for(action)

func _close() -> void:
	if _awaiting != "":
		_end_rebind()
	closed.emit()
	queue_free()
