extends CanvasLayer
## Per-client HUD, styled to the Busser design system (see ui/theme/). Readouts:
## SHIFT CREW (live connected peers) + STATIONS dish-flow panel (top-left), the
## SHIFT TRACKER card (top-right: clock + net earnings + covers + walkout stars),
## the PLATES CARRIED / WOBBLE group that rises while you haul a bus tub
## (bottom-center), and the STATUS ALARM when the pass runs dry (bottom-right).
## Shift end swaps in the torn-receipt report with the full earnings math.

@onready var crew_list := %CrewList as Label
@onready var counts_label := %CountsLabel as Label
@onready var time_label := %TimeLabel as Label
@onready var time_bar := %TimeBar as ProgressBar
@onready var money_label := %MoneyLabel as Label
@onready var covers_label := %CoversLabel as Label
@onready var stars_label := %StarsLabel as Label

@onready var carry_group := %CarryGroup as HBoxContainer
@onready var wobble_bar := %WobbleBar as ProgressBar
@onready var plates_num := %PlatesNum as Label
@onready var heavy_label := %HeavyLabel as Label
@onready var alarm := %Alarm as Control
@onready var prompt := %Prompt as Label
@onready var charge_bar := %ChargeBar as ProgressBar

@onready var end_overlay := %EndOverlay as ColorRect
@onready var report_stars := %Stars as Label
@onready var good_col := %GoodCol as Label
@onready var chaos_col := %ChaosCol as Label
@onready var verdict := %Verdict as Label
@onready var earnings := %Earnings as RichTextLabel

const _GREEN := Color(0.29, 0.8706, 0.502)
const _RED := Color(0.8627, 0.149, 0.149)
const _YELLOW := Color(0.9804, 0.8, 0.0824)
## Wobble fraction past which the meter turns red and HEAVY shows. Below this
## you are stable enough to keep walking; above it you are about to lose a plate.
const _WOBBLE_WARN := 0.6

func _ready() -> void:
	GameState.tick.connect(_on_tick)
	GameState.shift_ended.connect(_on_shift_ended)
	GameState.stats_changed.connect(_refresh_counts)
	DishLedger.changed.connect(_refresh_counts)
	multiplayer.peer_connected.connect(_on_peer_change)
	multiplayer.peer_disconnected.connect(_on_peer_change)
	(%ClockInNext as Button).pressed.connect(_on_clock_in_next)
	(%ReturnMenu as Button).pressed.connect(Net.back_to_menu)
	end_overlay.visible = false
	carry_group.visible = false
	alarm.visible = false
	prompt.text = ""
	charge_bar.visible = false
	_refresh_crew()
	_refresh_counts()
	_on_tick(GameState.time_left)

## The carry group climbs into view as the tub fills, and the wobble meter shifts
## green -> red as it gets top-heavy. Reads this peer's own busser each frame.
func _process(_delta: float) -> void:
	var me := Busser.local
	if me == null or not is_instance_valid(me):
		carry_group.visible = false
		prompt.text = ""
		return
	_show_prompt(me)
	_show_throw_charge(me)
	# A tub takes priority (you can't hand-stack while hauling one); otherwise
	# show the hand-stack of plates on its way to the pass.
	if me.carry_load >= 0:
		# A tub cannot spill, so its meter stays a fill gauge.
		_show_carry(me.carry_load, BusTub.CAPACITY,
			float(me.carry_load) / float(BusTub.CAPACITY),
			me.carry_load >= BusTub.CAPACITY - 1)
	elif me.stack_load > 0:
		# A hand-stack CAN spill, so the meter shows real instability, not fill:
		# it climbs as you move fast or whip the camera and falls when you settle.
		_show_carry(me.stack_load, Busser.STACK_MAX, me.wobble, me.wobble >= _WOBBLE_WARN)
	else:
		carry_group.visible = false

## Contextual verb under the crosshair, so it is always clear what you are
## aiming at and what the button will do. Reads the local busser's own focus,
## which it computes from replicated state.
func _show_prompt(me: Busser) -> void:
	prompt.text = me.focus_prompt
	prompt.self_modulate = _RED if me.focus_prompt == "STACK FULL" else _YELLOW

## Winding up a throw. Turns red once the plate is travelling fast enough to
## break on impact, so the player can see the moment a pass becomes a yeet.
func _show_throw_charge(me: Busser) -> void:
	if me.throw_charge <= 0.0 or me.stack_load <= 0:
		charge_bar.visible = false
		return
	charge_bar.visible = true
	charge_bar.value = me.throw_charge * 100.0
	var speed := lerpf(Busser.THROW_SPEED_MIN, Busser.THROW_SPEED_MAX, me.throw_charge)
	charge_bar.self_modulate = _RED if speed >= Dish.BREAK_SPEED else _YELLOW

func _show_carry(count: int, cap: int, meter: float, hot: bool) -> void:
	carry_group.visible = true
	plates_num.text = "%d / %d" % [count, cap]
	heavy_label.visible = hot
	wobble_bar.value = 15.0 + clampf(meter, 0.0, 1.0) * 85.0
	wobble_bar.self_modulate = _RED if hot else _GREEN

func _on_tick(seconds_left: float) -> void:
	time_label.text = "%d:%02d" % [floori(seconds_left / 60.0), int(seconds_left) % 60]
	time_bar.value = (1.0 - seconds_left / GameState.SHIFT_LENGTH) * 100.0

func _on_peer_change(_id: int) -> void:
	_refresh_crew()

## Live roster of connected bussers - the local peer plus everyone else on the
## ENet session. Offline (solo) resolves to a single "YOU" row.
func _refresh_crew() -> void:
	var me := multiplayer.get_unique_id()
	var ids := [me]
	ids.append_array(multiplayer.get_peers())
	ids.sort()
	var lines := PackedStringArray()
	var slot := 1
	for id in ids:
		var who: String = "YOU" if id == me else "PLAYER %d" % id
		lines.append("%d  %-12s ON SHIFT" % [slot, who])
		slot += 1
	crew_list.text = "\n".join(lines)

func _refresh_counts() -> void:
	var dirty := DishLedger.count(Dish.State.DIRTY) + DishLedger.count(Dish.State.HELD)
	var pit := DishLedger.count(Dish.State.AT_PIT) + DishLedger.count(Dish.State.WASHING)
	var clean := DishLedger.count(Dish.State.CLEAN)
	var in_kitchen := DishLedger.count(Dish.State.AT_PASS) + DishLedger.count(Dish.State.COOKING)
	var served := DishLedger.count(Dish.State.SERVED)
	var broken := DishLedger.count(Dish.State.BROKEN)
	counts_label.text = "DIRTY %d   PIT %d\nCLEAN %d   PASS %d\nSERVED %d   BROKEN %d" % [
		dirty, pit, clean, in_kitchen, served, broken]
	money_label.text = "$%0.2f" % GameState.net_earnings()
	covers_label.text = "COVERS %d" % GameState.covers
	# Stars burn down as walkouts pile up - one lost per walkout. Total tracks
	# the crew-scaled walkout limit (more grace solo).
	var lives := maxi(GameState.walkout_limit - GameState.walkouts, 0)
	stars_label.text = "★".repeat(lives) + "☆".repeat(GameState.walkout_limit - lives)
	# The pass is dry: no clean plates staged for the chef anywhere downstream.
	alarm.visible = clean == 0 and in_kitchen == 0

func _on_clock_in_next() -> void:
	# Solo/host restart the run in place; a joined client bails to the breakroom.
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		get_tree().reload_current_scene()
	else:
		Net.back_to_menu()

func _on_shift_ended(success: bool) -> void:
	var broken := DishLedger.count(Dish.State.BROKEN)
	var tips := GameState.tips_earned()
	var fees := GameState.breakage_fees()
	good_col.text = "✓ THE GOOD\n\nCovers Seated   %d\nTips Earned     $%0.2f\nClean Plates    %d" % [
		GameState.covers, tips, DishLedger.count(Dish.State.CLEAN)]
	chaos_col.text = "✗ THE CHAOS\n\nDishes Smashed  %d\nReplace Fee    -$%0.2f\nGuest Walkouts  %d" % [
		broken, fees, GameState.walkouts]
	# Mono font keeps these columns aligned; fee is red, net is bold.
	earnings.text = "GROSS TIPS             $%0.2f\n" % tips \
		+ "[color=#dc2626]DISH REPLACEMENT FEE  -$%0.2f[/color]\n" % fees \
		+ "[b]NET SHIFT EARNINGS     $%0.2f[/b]" % GameState.net_earnings()
	var lives := maxi(GameState.walkout_limit - GameState.walkouts, 0)
	report_stars.text = "★".repeat(lives) + "☆".repeat(GameState.walkout_limit - lives)
	if not success:
		verdict.text = "86'D"
	elif lives >= 4 and broken <= 1:
		verdict.text = "CLEAN SHIFT"
	elif lives >= 2:
		verdict.text = "PASSABLE SHIFT"
	else:
		verdict.text = "ROUGH SHIFT"
	end_overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	(%ClockInNext as Button).grab_focus()
