class_name DinerDecor
extends Node3D
## Procedural set-dressing for the diner graybox. Pure cosmetics: shared
## materials + primitive meshes + a few shadowless lights, no colliders and no
## gameplay state, so it is safe to drop in, cheap on low-end machines, and fast
## to iterate. Hero props (a real espresso machine, booths, signage) can replace
## these primitives one at a time later - likely authored in Blender.
##
## Everything is built in _ready from the palette below; tweak the constants or
## the _build_* calls to reskin. Matches the Busser design system: slate #1F2937,
## hazard-yellow #FACC15, slate-700 #374151, near-white, radius-0 industrial.

# --- Palette (from DesignSystem-Busser.md) -----------------------------------
const SLATE_900 := Color(0.067, 0.094, 0.153)   # #111827 panels
const SLATE_800 := Color(0.122, 0.161, 0.216)   # #1F2937 backdrop
const SLATE_700 := Color(0.216, 0.255, 0.318)   # #374151 secondary
const YELLOW    := Color(0.980, 0.800, 0.082)   # #FACC15 hazard/accent
const NEAR_WHITE := Color(0.976, 0.980, 0.984)  # #F9FAFB
const PLANT_GREEN := Color(0.29, 0.52, 0.28)
const POT_CLAY := Color(0.55, 0.32, 0.22)
const WARM_LAMP := Color(1.0, 0.86, 0.66)

# Room extents (from diner.tscn): floor 20 x 14, walls span y 0..3.
const CEILING_Y := 3.0
const TABLE_SPOTS: Array[Vector3] = [
	Vector3(-6.0, 0.0, -3.5), Vector3(-2.0, 0.0, -3.5), Vector3(2.0, 0.0, -3.5),
	Vector3(-6.0, 0.0, 1.5), Vector3(-2.0, 0.0, 1.5), Vector3(2.0, 0.0, 1.5),
]

var _mat_cache: Dictionary = {}

func _ready() -> void:
	_build_ceiling()
	_build_hazard_skirting()
	_build_pendant_lights()
	_build_menu_board()
	_build_wall_clock()
	_build_open_sign()
	_build_plants()

# --- Builders ----------------------------------------------------------------

## A dark ceiling closes the box so the warm pendants read and the slate mood
## lands. Single unlit-ish slab, one draw call.
func _build_ceiling() -> void:
	var m := _flat(SLATE_900, 0.0, 0.95)
	var ceil := _box_node(Vector3(20.0, 0.2, 14.0), Vector3(0.0, CEILING_Y + 0.1, 0.0), m)
	ceil.name = "Ceiling"
	# Don't occlude the shadow-casting Sun, or the whole interior drops to ambient
	# only (and the pendant-free station side goes dark). The slab reads as a
	# ceiling but lets the existing fill light through.
	ceil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ceil)

## Hazard-yellow kick strip around the base of the walls - instant diner-punk.
func _build_hazard_skirting() -> void:
	var m := _flat(YELLOW, 0.0, 0.5)
	var h := 0.18
	var y := h * 0.5
	# N/S walls run along X at z = +-7.0; E/W walls along Z at x = +-10.0.
	_box("SkirtN", Vector3(20.0, h, 0.06), Vector3(0.0, y, -6.9), m)
	_box("SkirtS", Vector3(20.0, h, 0.06), Vector3(0.0, y, 6.9), m)
	_box("SkirtE", Vector3(0.06, h, 14.0), Vector3(9.9, y, 0.0), m)
	_box("SkirtW", Vector3(0.06, h, 14.0), Vector3(-9.9, y, 0.0), m)

## Warm pendant over each table. Rod + cylindrical shade + a short-range,
## shadowless OmniLight (shadows off keeps a full crew's 6 lamps cheap).
func _build_pendant_lights() -> void:
	var shade_mat := _flat(SLATE_700, 0.2, 0.6)
	var rod_mat := _flat(SLATE_900, 0.4, 0.4)
	var glow_mat := _emissive(WARM_LAMP, 1.4)
	for i in TABLE_SPOTS.size():
		var base := TABLE_SPOTS[i]
		var group := Node3D.new()
		group.name = "Pendant%d" % (i + 1)
		add_child(group)
		group.position = Vector3(base.x, 0.0, base.z)
		# Rod from ceiling down to the shade.
		var rod := _cyl(0.02, 0.02, 0.7, rod_mat)
		rod.position = Vector3(0.0, CEILING_Y - 0.35, 0.0)
		group.add_child(rod)
		# Cone-ish shade (wide bottom, narrow top).
		var shade := _cyl(0.08, 0.22, 0.22, shade_mat)
		shade.position = Vector3(0.0, CEILING_Y - 0.8, 0.0)
		group.add_child(shade)
		# Glowing bulb disc under the shade.
		var bulb := _cyl(0.09, 0.09, 0.03, glow_mat)
		bulb.position = Vector3(0.0, CEILING_Y - 0.92, 0.0)
		group.add_child(bulb)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.0, CEILING_Y - 1.0, 0.0)
		lamp.light_color = WARM_LAMP
		lamp.light_energy = 1.6
		lamp.omni_range = 4.5
		lamp.shadow_enabled = false
		group.add_child(lamp)

## Slate menu board high on the north wall with a yellow header bar and three
## faux "special" rows blocked in with white/yellow bars.
func _build_menu_board() -> void:
	var board := Node3D.new()
	board.name = "MenuBoard"
	add_child(board)
	board.position = Vector3(-3.2, 2.15, -6.86)
	var panel := _flat(SLATE_900, 0.0, 0.85)
	board.add_child(_box_node(Vector3(2.6, 1.3, 0.06), Vector3.ZERO, panel))
	var header := _emissive(YELLOW, 0.35)
	board.add_child(_box_node(Vector3(2.6, 0.26, 0.08), Vector3(0.0, 0.52, 0.02), header))
	# Faux menu lines: a bright "price" tick + a longer dim "item" bar per row.
	var item_mat := _flat(NEAR_WHITE.darkened(0.25), 0.0, 0.9)
	var price_mat := _emissive(YELLOW, 0.3)
	for r in 3:
		var y := 0.15 - r * 0.3
		board.add_child(_box_node(Vector3(1.6, 0.07, 0.08), Vector3(-0.35, y, 0.02), item_mat))
		board.add_child(_box_node(Vector3(0.28, 0.07, 0.08), Vector3(0.95, y, 0.02), price_mat))

## Minimal wall clock on the north wall: dark disc, yellow rim, two hands.
func _build_wall_clock() -> void:
	var clock := Node3D.new()
	clock.name = "WallClock"
	add_child(clock)
	clock.position = Vector3(4.5, 2.25, -6.86)
	clock.add_child(_cyl_node(0.34, 0.34, 0.05, _flat(YELLOW, 0.1, 0.5),
			Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0)))
	clock.add_child(_cyl_node(0.3, 0.3, 0.06, _flat(SLATE_900, 0.0, 0.8),
			Vector3(0.0, 0.0, 0.01), Vector3(PI * 0.5, 0.0, 0.0)))
	var hand := _flat(NEAR_WHITE, 0.0, 0.6)
	# Hour hand (short, up) + minute hand (long, aimed ~4 o'clock).
	clock.add_child(_box_node(Vector3(0.03, 0.16, 0.02), Vector3(0.0, 0.07, 0.05), hand))
	var minute := _box_node(Vector3(0.025, 0.24, 0.02), Vector3(0.06, -0.04, 0.05), hand)
	minute.rotation = Vector3(0.0, 0.0, -1.1)
	clock.add_child(minute)

## Emissive "OPEN" sign by the entry (south wall, near the door at x -8.5).
func _build_open_sign() -> void:
	var sign := Node3D.new()
	sign.name = "OpenSign"
	add_child(sign)
	sign.position = Vector3(-8.5, 2.3, 6.86)
	sign.add_child(_box_node(Vector3(1.5, 0.5, 0.05), Vector3.ZERO, _flat(SLATE_900, 0.0, 0.7)))
	# Four glowing bars standing in for the letters.
	var neon := _emissive(YELLOW, 2.2)
	for i in 4:
		sign.add_child(_box_node(Vector3(0.22, 0.32, 0.03),
				Vector3(-0.5 + i * 0.34, 0.0, -0.03), neon))
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.0, 0.0, -0.6)
	glow.light_color = YELLOW
	glow.light_energy = 0.8
	glow.omni_range = 3.0
	glow.shadow_enabled = false
	sign.add_child(glow)

## Potted plants in the two guest-side corners to soften the box.
func _build_plants() -> void:
	for pos in [Vector3(-9.2, 0.0, -6.2), Vector3(-9.2, 0.0, 6.2)]:
		var plant := Node3D.new()
		plant.name = "Plant"
		add_child(plant)
		plant.position = pos
		plant.add_child(_cyl_node(0.22, 0.28, 0.5, _flat(POT_CLAY, 0.0, 0.9),
				Vector3(0.0, 0.25, 0.0)))
		var leaf := _flat(PLANT_GREEN, 0.0, 0.8)
		plant.add_child(_cyl_node(0.02, 0.35, 0.9, leaf, Vector3(0.0, 0.95, 0.0)))
		plant.add_child(_cyl_node(0.02, 0.22, 0.6, leaf, Vector3(0.12, 1.05, 0.08)))
		plant.add_child(_cyl_node(0.02, 0.22, 0.6, leaf, Vector3(-0.1, 1.0, -0.1)))

# --- Primitive helpers -------------------------------------------------------

func _box(node_name: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var n := _box_node(size, pos, mat)
	n.name = node_name
	add_child(n)

func _box_node(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

func _cyl(top_r: float, bottom_r: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	return _cyl_node(top_r, bottom_r, height, mat, Vector3.ZERO)

func _cyl_node(top_r: float, bottom_r: float, height: float, mat: StandardMaterial3D,
		pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	return mi

## Cached opaque material so repeated colours share one resource.
func _flat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [color.to_html(), metallic, roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	_mat_cache[key] = m
	return m

## Cached emissive material for glowing bits (bulbs, neon, header).
func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var key := "e|%s|%.2f" % [color.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mat_cache[key] = m
	return m
