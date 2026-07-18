extends Node
## Autoload "GameState" - shift clock + win/fail check.
## Runs locally on every peer; dish states are replicated, so all peers
## reach the same verdict within a tick of each other. Good enough for MVP.

signal tick(seconds_left: float)
signal shift_ended(success: bool)

const SHIFT_LENGTH := 240.0

var time_left := SHIFT_LENGTH
var running := false

func start_shift() -> void:
	time_left = SHIFT_LENGTH
	running = true

func stop_shift() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	time_left = maxf(time_left - delta, 0.0)
	tick.emit(time_left)
	if DishLedger.all_done():
		_end(true)
	elif time_left <= 0.0:
		_end(false)

func _end(success: bool) -> void:
	running = false
	shift_ended.emit(success)
