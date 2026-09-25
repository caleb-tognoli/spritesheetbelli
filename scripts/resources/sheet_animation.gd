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


## Reads frame numbers such as "0-3, 5, 9-7": single numbers and ranges, which count
## down when the first number is bigger. Returns [code]{"numbers": Array[int]}[/code], or
## [code]{"error": String}[/code] naming the part that couldn't be read.
static func parse_numbers(text: String) -> Dictionary:
	var numbers: Array[int] = []
	for part in text.replace(",", " ").split(" ", false):
		var ends := part.split("-", false)
		var valid := ends.size() in [1, 2] and ends[0].is_valid_int()
		valid = valid and (ends.size() == 1 or ends[1].is_valid_int())
		valid = valid and part.count("-") == ends.size() - 1
		if not valid:
			return {"error": part}
		var first := int(ends[0])
		var last := int(ends[-1])
		var step := 1 if last >= first else -1
		for number in range(first, last + step, step):
			numbers.append(number)
	return {"numbers": numbers}


## Writes [param numbers] the way [method parse_numbers] reads them, with runs as ranges
static func format_numbers(numbers: Array[int]) -> String:
	var parts: PackedStringArray = []
	var i := 0
	while i < numbers.size():
		var end := i
		var step := 0
		if i + 1 < numbers.size() and absi(numbers[i + 1] - numbers[i]) == 1:
			step = numbers[i + 1] - numbers[i]
			while end + 1 < numbers.size() and numbers[end + 1] - numbers[end] == step:
				end += 1
		if end - i >= 2:
			parts.append("%d-%d" % [numbers[i], numbers[end]])
		else:
			for j in range(i, end + 1):
				parts.append(str(numbers[j]))
		i = end + 1
	return ", ".join(parts)
