class_name TubRack
extends StaticBody3D
## A restaurant-style metal wire rack - a home for bus tubs off the floor at
## grab height. Built from primitives in code (matching diner_decor): flat shelf
## colliders that tubs rest on, plus corner posts so it reads solid to players.
## Pure surface, no gameplay logic - swap for a modeled rack later.

const SHELF_YS: Array[float] = [0.5, 1.0, 1.5]   # shelf heights (local Y)
const WIDTH := 1.0      # X span
const DEPTH := 0.5      # Z span
const POST := 0.05      # corner-post thickness
const SHELF_H := 0.04   # shelf slab thickness

var _steel := StandardMaterial3D.new()

func _ready() -> void:
	_steel.albedo_color = Color(0.62, 0.65, 0.68)
	_steel.metallic = 0.6
	_steel.roughness = 0.35
	_build_posts()
	_build_shelves()

func _build_posts() -> void:
	var top: float = SHELF_YS[SHELF_YS.size() - 1] + 0.25
	var hx := WIDTH * 0.5 - POST * 0.5
	var hz := DEPTH * 0.5 - POST * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(Vector3(POST, top, POST), Vector3(sx * hx, top * 0.5, sz * hz))

func _build_shelves() -> void:
	for y in SHELF_YS:
		_add_box(Vector3(WIDTH, SHELF_H, DEPTH), Vector3(0.0, y, 0.0))

## One steel slab: a MeshInstance to see and a matching CollisionShape (as a
## child of this StaticBody) so tubs rest and players don't clip through.
func _add_box(size: Vector3, pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _steel
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	add_child(cs)
