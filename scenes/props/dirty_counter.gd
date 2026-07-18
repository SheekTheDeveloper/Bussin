class_name DirtyCounter
extends StaticBody3D
## The dirty-dish landing table. Any DIRTY dish that ends up in its DropZone
## (thrown, dropped, or placed) gets flagged AT_PIT for the machine to pull.
## Standalone prop: swap the scene for skins/upgrades without touching logic.

@onready var zone := $DropZone as Area3D

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body in zone.get_overlapping_bodies():
		if body is Dish and body.state == Dish.State.DIRTY and body.holder == null:
			body.land_at_pit()
