class_name DinerTable
extends StaticBody3D
## A diner table with 4 seats and a lifecycle:
## READY (no party, no dishes) -> occupied (party eating) -> messy (dirty
## dishes left behind) -> bussed clean -> READY again.
## Party assignment is server-side; dish presence is physical (TableZone).

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

func dish_spot_global(i: int) -> Vector3:
	# Plate lands on the table edge in front of seat i.
	var seat := seats[i % seats.size()] as Node3D
	var local := seat.position
	return global_position + Vector3(local.x * 0.85, 0.84, local.z * 0.45)
