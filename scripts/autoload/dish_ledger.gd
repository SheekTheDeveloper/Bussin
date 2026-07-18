extends Node
## Autoload "DishLedger" - the conserved dish pool.
## Dishes register themselves on _ready; counts are derived from replicated
## dish state, so every peer computes the same numbers locally.

signal changed

var dishes: Array[Dish] = []

func register(dish: Dish) -> void:
	if dish in dishes:
		return
	dishes.append(dish)
	dish.tree_exiting.connect(func() -> void: dishes.erase(dish))
	changed.emit()

func notify_changed() -> void:
	changed.emit()

func count(state: int) -> int:
	var n := 0
	for d in dishes:
		if d.state == state:
			n += 1
	return n

func total() -> int:
	return dishes.size()

func all_done() -> bool:
	if dishes.is_empty():
		return false
	var any_clean := false
	for d in dishes:
		match d.state:
			Dish.State.CLEAN:
				any_clean = true
			Dish.State.BROKEN:
				pass
			_:
				return false
	return any_clean
