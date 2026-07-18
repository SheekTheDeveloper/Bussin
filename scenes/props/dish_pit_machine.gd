extends StaticBody3D
## Interact target for the dish machine. Busser raycasts hit this body;
## the server-side interact RPC lands here and kicks off a wash cycle.

func interact(_player: Busser) -> void:
	(get_parent() as DishPit).start_cycle()
