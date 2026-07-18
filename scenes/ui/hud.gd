extends CanvasLayer
## Per-client HUD: shift clock, dish counts, controls hint, and the
## end-of-shift overlay (SHIFT COMPLETE / 86'D).

@onready var time_label := $Root/TopLeft/TimeLabel as Label
@onready var counts_label := $Root/TopLeft/CountsLabel as Label
@onready var end_overlay := $Root/EndOverlay as ColorRect
@onready var end_label := $Root/EndOverlay/Center/VBox/EndLabel as Label
@onready var sub_label := $Root/EndOverlay/Center/VBox/SubLabel as Label

func _ready() -> void:
	GameState.tick.connect(_on_tick)
	GameState.shift_ended.connect(_on_shift_ended)
	DishLedger.changed.connect(_refresh_counts)
	($Root/EndOverlay/Center/VBox/MenuButton as Button).pressed.connect(Net.back_to_menu)
	end_overlay.visible = false
	_refresh_counts()
	_on_tick(GameState.time_left)

func _on_tick(seconds_left: float) -> void:
	time_label.text = "%d:%02d" % [floori(seconds_left / 60.0), int(seconds_left) % 60]

func _refresh_counts() -> void:
	var dirty := DishLedger.count(Dish.State.DIRTY) + DishLedger.count(Dish.State.HELD)
	counts_label.text = "Dirty %d   At pit %d   Washing %d   Clean %d/%d   Broken %d" % [
		dirty,
		DishLedger.count(Dish.State.AT_PIT),
		DishLedger.count(Dish.State.WASHING),
		DishLedger.count(Dish.State.CLEAN),
		DishLedger.total(),
		DishLedger.count(Dish.State.BROKEN),
	]

func _on_shift_ended(success: bool) -> void:
	end_overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	($Root/EndOverlay/Center/VBox/MenuButton as Button).grab_focus()
	if success:
		end_label.text = "SHIFT COMPLETE"
		end_label.modulate = Color(0.5, 1.0, 0.6)
		sub_label.text = "Every plate accounted for. The kitchen nods respectfully."
	else:
		end_label.text = "86'D"
		end_label.modulate = Color(1.0, 0.25, 0.2)
		sub_label.text = "Time's up with dishes still dirty. Broken this shift: %d" % DishLedger.count(Dish.State.BROKEN)
