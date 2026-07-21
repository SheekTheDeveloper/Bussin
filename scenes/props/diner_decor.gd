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
	_build_floor_zones()
	_build_ceiling()
	_build_hazard_skirting()
	_build_pendant_lights()
	_build_windows()
	_build_pit_splashback()
	_build_ceiling_vents()
	_build_menu_board()
	_build_wall_clock()
	_build_open_sign()
	_build_plants()

# --- Builders ----------------------------------------------------------------

## Floor zoning: checkerboard vinyl out front, industrial plate behind the line.
## This is set dressing that does legibility work (GDD pillar 3) - the two halves
## of the loop become readable at a glance, so a new player can see where the
## guest floor ends and the wet, breakable pit side begins without being told.
##
## Built as ONE MultiMesh rather than hundreds of MeshInstance3Ds: a few hundred
## tiles on one draw call keeps the optimization principle intact on low-end
## machines. Cosmetic only - the real floor collider is the level's Floor node.
func _build_floor_zones() -> void:
	const TILE := 1.0
	const PIT_LINE := 6.6      # world x where the guest floor gives way to the pit
	const Y := 0.005           # a hair above the floor slab, to avoid z-fighting
	var light := _flat(NEAR_WHITE.darkened(0.08), 0.0, 0.55)
	var dark := _flat(SLATE_700.lightened(0.05), 0.0, 0.6)
	var plate := _flat(SLATE_800.lightened(0.10), 0.25, 0.45)

	var groups := {light: [], dark: [], plate: []}
	var half_x := 10.0
	var half_z := 7.0
	var nx := int(half_x * 2.0 / TILE)
	var nz := int(half_z * 2.0 / TILE)
	for ix in nx:
		for iz in nz:
			var x := -half_x + (ix + 0.5) * TILE
			var z := -half_z + (iz + 0.5) * TILE
			var mat: StandardMaterial3D = plate if x > PIT_LINE else (light if (ix + iz) % 2 == 0 else dark)
			(groups[mat] as Array).append(Transform3D(Basis.IDENTITY, Vector3(x, Y, z)))

	for mat in groups:
		var xforms: Array = groups[mat]
		if xforms.is_empty():
			continue
		var quad := BoxMesh.new()
		quad.size = Vector3(TILE * 0.98, 0.01, TILE * 0.98)  # hairline grout gap
		quad.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "FloorTiles%d" % groups.keys().find(mat)
		add_child(mmi)

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

## Windows down the south wall with a night-street backdrop behind them. The
## backdrop is a dark slab with emissive blocks standing in for lit windows
## across the street and a couple of streetlights: it costs three materials and
## no textures, but it stops the room reading as a sealed box and gives the
## diner a time of day.
##
## The door sits at x -8.5, so the glazing starts clear of it.
func _build_windows() -> void:
	const SOUTH_Z := 6.88
	const SILL_Y := 0.95
	const GLASS_H := 1.35
	var frame_mat := _flat(SLATE_900, 0.1, 0.7)
	var glass_mat := _flat(Color(0.62, 0.74, 0.82), 0.0, 0.15)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color.a = 0.22

	var street := Node3D.new()
	street.name = "StreetBackdrop"
	add_child(street)
	# Backdrop slab sits just outside the wall.
	street.add_child(_box_node(Vector3(15.0, 4.0, 0.1), Vector3(0.5, 1.6, SOUTH_Z + 0.55),
			_flat(Color(0.05, 0.06, 0.09), 0.0, 1.0)))
	# Distant lit windows: a scatter of small warm/cool emissive blocks.
	var warm := _emissive(Color(1.0, 0.82, 0.55), 1.1)
	var cool := _emissive(Color(0.55, 0.72, 0.95), 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260720
	for i in 34:
		var wx := rng.randf_range(-6.0, 7.0)
		var wy := rng.randf_range(1.1, 3.2)
		street.add_child(_box_node(Vector3(rng.randf_range(0.14, 0.28), rng.randf_range(0.16, 0.3), 0.04),
				Vector3(wx, wy, SOUTH_Z + 0.48), warm if i % 3 else cool))
	# Two streetlamp glows at ground level for depth.
	for lx in [-3.0, 4.5]:
		street.add_child(_box_node(Vector3(0.12, 0.9, 0.06), Vector3(lx, 0.75, SOUTH_Z + 0.42),
				_emissive(WARM_LAMP, 1.6)))

	# Three bays of glazing with mullions between them.
	var bays := [Vector3(-4.6, 0.0, 0.0), Vector3(0.4, 0.0, 0.0), Vector3(5.4, 0.0, 0.0)]
	for i in bays.size():
		var bay := Node3D.new()
		bay.name = "Window%d" % (i + 1)
		add_child(bay)
		bay.position = Vector3(bays[i].x, 0.0, 0.0)
		bay.add_child(_box_node(Vector3(4.0, GLASS_H, 0.03),
				Vector3(0.0, SILL_Y + GLASS_H * 0.5, SOUTH_Z), glass_mat))
		# Frame: sill, head, and a centre mullion.
		bay.add_child(_box_node(Vector3(4.15, 0.12, 0.16), Vector3(0.0, SILL_Y - 0.06, SOUTH_Z - 0.02), frame_mat))
		bay.add_child(_box_node(Vector3(4.15, 0.12, 0.16), Vector3(0.0, SILL_Y + GLASS_H + 0.06, SOUTH_Z - 0.02), frame_mat))
		bay.add_child(_box_node(Vector3(0.10, GLASS_H, 0.14), Vector3(0.0, SILL_Y + GLASS_H * 0.5, SOUTH_Z - 0.02), frame_mat))
		for edge in [-2.05, 2.05]:
			bay.add_child(_box_node(Vector3(0.12, GLASS_H + 0.24, 0.16),
					Vector3(edge, SILL_Y + GLASS_H * 0.5, SOUTH_Z - 0.02), frame_mat))

## White tile splashback behind the dish pit. Reinforces the floor zoning: the
## pit side is the wipe-clean, industrial half of the room. One MultiMesh, so
## a wall of tiles is a single draw call.
func _build_pit_splashback() -> void:
	const TILE_W := 0.4
	const TILE_H := 0.28
	const X := 9.86
	var rows := 7
	var cols := 22
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, TILE_H * 0.94, TILE_W * 0.94)
	mesh.material = _flat(NEAR_WHITE.darkened(0.06), 0.05, 0.35)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = rows * cols
	var i := 0
	for r in rows:
		for c in cols:
			# Offset every other row by half a tile: reads as brickwork, not a grid.
			var z := -4.4 + c * TILE_W + (TILE_W * 0.5 if r % 2 else 0.0)
			var y := 0.45 + r * TILE_H
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(X, y, z)))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PitSplashback"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Extract hoods over the pit and vents down the ceiling: cheap industrial
## punctuation so the ceiling is not a blank slab.
func _build_ceiling_vents() -> void:
	var duct_mat := _flat(SLATE_700.darkened(0.1), 0.4, 0.5)
	var slat_mat := _flat(SLATE_900, 0.3, 0.6)
	for spot in [Vector3(9.0, 0.0, 0.0), Vector3(-1.0, 0.0, -6.2)]:
		var duct := Node3D.new()
		duct.name = "Duct"
		add_child(duct)
		duct.position = Vector3(spot.x, CEILING_Y - 0.28, spot.z)
		duct.add_child(_box_node(Vector3(1.1, 0.42, 5.2), Vector3.ZERO, duct_mat))
		for k in 5:
			duct.add_child(_box_node(Vector3(1.16, 0.06, 0.08),
					Vector3(0.0, -0.16, -2.0 + k * 1.0), slat_mat))
	for v in [Vector3(-6.0, 0.0, 3.0), Vector3(2.0, 0.0, 3.0), Vector3(-4.0, 0.0, -1.0)]:
		var vent := _box_node(Vector3(0.6, 0.05, 0.6), Vector3(v.x, CEILING_Y - 0.05, v.z), slat_mat)
		vent.name = "Vent"
		add_child(vent)

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
