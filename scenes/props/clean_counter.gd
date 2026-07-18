class_name CleanCounter
extends StaticBody3D
## The clean-dish output table. The machine asks it where to put each washed
## dish; it hands out countertop grid spots left-to-right, stacking rows.

var _count := 0

@onready var base := $ShelfBase as Node3D

func next_spot() -> Vector3:
	var col := _count % 4
	var row := floori(_count / 4.0)
	_count += 1
	var local_offset := Vector3(-0.35 + (row % 3) * 0.35, 0.03 + floori(row / 3.0) * 0.05, -0.9 + col * 0.6)
	return base.global_position + base.global_transform.basis * local_offset
