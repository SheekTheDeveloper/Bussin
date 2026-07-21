class_name DishVisuals
extends Node3D
## Presentation layer for a Dish: shows and hides child part meshes per state.
##
## SEPARATION: the Dish owns what a state MEANS (see Dish.STATE_PARTS); this
## node only knows how to show parts and tint them. That keeps the state machine
## free of art decisions and lets a whole visual set be swapped by replacing this
## subtree - the same rule the standalone station props follow, so skins and
## upgrades stay possible.
##
## Parts are child Node3Ds looked up BY NAME. Every one is optional: a missing
## part is skipped, so the plate still works with only the base mesh present and
## art can land one piece at a time. Conventional names:
##
##   Plate    the ceramic body, visible in nearly every state
##   Grime    leftover food and smears, on top of the plate when dirty
##   Food     a served meal sitting on the plate
##   Shards   the broken remains, replacing the plate entirely
##
## The tint is a fallback, not the goal. Pipeline states a player only ever sees
## for a moment (WASHING, COOKING) stay readable by colour instead of costing a
## bespoke mesh; states the player actually reads at a glance get real geometry.

## Squash applied to the plate when it breaks and no Shards mesh exists yet, so
## a broken plate still reads as broken before that art lands.
const FALLBACK_BROKEN_SCALE := Vector3(1.3, 0.15, 1.3)

static var _tint_cache: Dictionary = {}

var _parts: Dictionary = {}          # String -> Node3D
var _plate_meshes: Array[MeshInstance3D] = []
var _plate_base_scale := Vector3.ONE

func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			_parts[String(child.name)] = child
	var plate := _parts.get("Plate") as Node3D
	if plate != null:
		_plate_base_scale = plate.scale
		_plate_meshes.assign(plate.find_children("*", "MeshInstance3D", true, false))

func has_part(part_name: String) -> bool:
	return _parts.has(part_name)

## Show exactly these parts and hide the rest. Names that do not exist in the
## scene are ignored rather than erroring, so art can arrive incrementally.
func show_only(names: Array) -> void:
	for key in _parts:
		(_parts[key] as Node3D).visible = key in names

## Tint the plate body. `enabled` false clears the override so authored
## materials show through untouched - once real per-state art exists, the tint
## should simply stop being requested.
func tint_plate(color: Color, enabled: bool) -> void:
	var mat: StandardMaterial3D = null
	if enabled:
		if not _tint_cache.has(color):
			var m := StandardMaterial3D.new()
			m.albedo_color = color
			_tint_cache[color] = m
		mat = _tint_cache[color]
	for mi in _plate_meshes:
		mi.material_override = mat

## Called when the dish breaks. Uses real shard geometry when it exists and
## falls back to squashing the plate when it does not.
func apply_broken() -> void:
	var plate := _parts.get("Plate") as Node3D
	if plate == null:
		return
	if has_part("Shards"):
		plate.scale = _plate_base_scale
	else:
		plate.scale = _plate_base_scale * FALLBACK_BROKEN_SCALE

func clear_broken() -> void:
	var plate := _parts.get("Plate") as Node3D
	if plate != null:
		plate.scale = _plate_base_scale
