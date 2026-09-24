class_name SheetAnimation
extends RefCounted
## A named animation: cells of the sheet played in order at a speed.
## Stored in [Spritesheet] as a plain dictionary so snapshots stay cheap.

enum Mode { LOOP, PING_PONG, ONCE }

const MODE_NAMES := {Mode.ONCE: "Once", Mode.LOOP: "Loop", Mode.PING_PONG: "Ping-pong"}

var name := "animation"
## Cells in playing order. Cells without a frame are skipped.
var cells: Array[Vector2i] = []
var fps := 12.0
var mode := Mode.LOOP


static func create(
	anim_name: String, anim_cells: Array[Vector2i], anim_fps := 12.0
) -> SheetAnimation:
	var animation := SheetAnimation.new()
	animation.name = anim_name
	animation.cells = anim_cells.duplicate()
	animation.fps = anim_fps
	return animation


static func from_dictionary(data: Dictionary) -> SheetAnimation:
	var animation := SheetAnimation.new()
	animation.name = str(data.get("name", "animation"))
	for cell: Variant in data.get("cells", []):
		if cell is Vector2i:
			animation.cells.append(cell)
		elif cell is Array and cell.size() >= 2:
			animation.cells.append(Vector2i(int(cell[0]), int(cell[1])))
	animation.fps = clampf(float(data.get("fps", 12.0)), 0.1, 120.0)
	var saved_mode := int(data.get("mode", Mode.LOOP))
	animation.mode = saved_mode as Mode if saved_mode in Mode.values() else Mode.LOOP
	return animation


func to_dictionary() -> Dictionary:
	return {"name": name, "cells": cells.duplicate(), "fps": fps, "mode": mode}


## The cells that have a frame in [param sheet]
func get_frame_cells(sheet: Spritesheet) -> Array[Vector2i]:
	return cells.filter(sheet.has_frame)


## The cells in the order they're shown over one cycle: ping-pong plays back again,
## without repeating the ends
func get_playback_cells(sheet: Spritesheet) -> Array[Vector2i]:
	var played := get_frame_cells(sheet)
	if mode == Mode.PING_PONG and played.size() > 2:
		var back := played.slice(1, played.size() - 1)
		back.reverse()
		played.append_array(back)
	return played
