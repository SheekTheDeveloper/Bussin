extends Node
## Autoload "GameState" - shift clock + score. The shift is now a survival
## run: serve covers, avoid walkouts. Hit the walkout limit -> 86'D.
## Covers/walkouts are server-authoritative and pushed to clients via RPC
## (autoloads share a path on every peer, so RPCs just work).

signal tick(seconds_left: float)
signal shift_ended(success: bool)
signal stats_changed

const SHIFT_LENGTH := 300.0
const BASE_WALKOUT_LIMIT := 5

## How many walkouts end the shift. Crew-scaled: a solo busser gets extra grace
## (fewer hands to turn tables), a full crew runs on the tight original 5. Set
## server-side from live crew size and synced to clients (see set_walkout_limit).
var walkout_limit := BASE_WALKOUT_LIMIT

# Shift economy. Money is DERIVED, never stored: tips come from the synced cover
# count and fees from the conserved dish pool's BROKEN tally, so every peer
# computes the same dollars locally with no extra replication.
const TIP_PER_COVER := 8.50
const BREAKAGE_FEE := 6.00

var time_left := SHIFT_LENGTH
var running := false
var covers := 0
var walkouts := 0

func tips_earned() -> float:
	return covers * TIP_PER_COVER

func breakage_fees() -> float:
	return DishLedger.count(Dish.State.BROKEN) * BREAKAGE_FEE

func net_earnings() -> float:
	return tips_earned() - breakage_fees()

func start_shift() -> void:
	time_left = SHIFT_LENGTH
	covers = 0
	walkouts = 0
	running = true
	stats_changed.emit()

func stop_shift() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	time_left = maxf(time_left - delta, 0.0)
	tick.emit(time_left)
	if walkouts >= walkout_limit:
		_end(false)
	elif time_left <= 0.0:
		_end(true)

func add_cover(party_size: int) -> void:
	if not multiplayer.is_server():
		return
	covers += party_size
	stats_changed.emit()
	_sync_stats.rpc(covers, walkouts)

func add_walkout() -> void:
	if not multiplayer.is_server():
		return
	walkouts += 1
	stats_changed.emit()
	_sync_stats.rpc(covers, walkouts)

@rpc("authority", "call_remote", "reliable")
func _sync_stats(c: int, w: int) -> void:
	covers = c
	walkouts = w
	stats_changed.emit()

## Server pushes the crew-scaled walkout limit to every peer so the fail check
## and the HUD star meter agree. call_local so the host applies it too.
@rpc("authority", "call_local", "reliable")
func set_walkout_limit(n: int) -> void:
	walkout_limit = n
	stats_changed.emit()

func _end(success: bool) -> void:
	running = false
	shift_ended.emit(success)
