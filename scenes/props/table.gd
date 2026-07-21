class_name DinerTable
extends StaticBody3D
## A diner table with 4 seats and a lifecycle:
## READY (no party, no dishes) -> occupied (party eating) -> messy (dirty
## dishes left behind) -> bussed clean -> READY again.
## Party assignment is server-side; dish presence is physical (TableZone).

## Height of the tabletop above the table's origin.
const TABLETOP_Y := 0.8225

var party: Array = []  # of Guest, server-side only

@onready var zone := $TableZone as Area3D
@onready var seats: Array[Node] = $Seats.get_children()

func is_ready_for_party() -> bool:
	return party.is_empty() and dish_count() == 0

func dish_count() -> int:
	var n := 0
	for body in zone.get_overlapping_bodies():
		if body is Dish:
			n += 1
	return n

func seat_global(i: int) -> Vector3:
	return (seats[i % seats.size()] as Node3D).global_position

## The TABLETOP point in front of seat i. Returns the surface, not a dish
## position: each Dish lifts itself by its own base_offset, so a mug and a plate
## both sit on the table rather than one of them sinking into it.
func dish_spot_global(i: int) -> Vector3:
	var seat := seats[i % seats.size()] as Node3D
	var local := seat.position
	return global_position + Vector3(local.x * 0.85, TABLETOP_Y, local.z * 0.45)
