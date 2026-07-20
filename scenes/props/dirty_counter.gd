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
		# A loaded tub set down on the table tips itself out, same as an
		# interact-dump - so "put the tub on the dirty table" just works.
		if body is BusTub and body.carrier == null and body.contents.size() > 0:
			body.dump_at(zone.global_position + Vector3.UP * 0.2)
		elif body is Dish and body.state == Dish.State.DIRTY and body.holder == null and body.in_tub == null:
			body.land_at_pit()

## Interact (E / Square) while carrying a loaded tub tips it out onto the pit.
func interact(player: Busser) -> void:
	if not multiplayer.is_server():
		return
	var tub := player.carried_tub
	if tub != null and tub.contents.size() > 0:
		tub.dump_at(zone.global_position + Vector3.UP * 0.2)
		player.server_set_carry(0)  # still holding the now-empty tub
