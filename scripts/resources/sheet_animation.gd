class_name SheetAnimation
extends RefCounted
## A named animation: cells of the sheet played in order at a speed.
## Stored in [Spritesheet] as a plain dictionary so snapshots stay cheap.

enum Mode { LOOP, PING_PONG, ONCE }

const MODE_NAMES := {Mode.ONCE: "Once", Mode.LOOP: "Loop", Mode.PING_PONG: "Ping-pong"}

var name := "animation"
## Cells in playing order. Cells without a frame are skipped.
var cells: Array[Vector2i] = []
## How long each of [member cells] is shown, in frames at [member fps]: 2 shows it twice
## as long. Missing entries are 1.
var durations: Array[float] = []
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
	for duration: Variant in data.get("durations", []):
		if duration is float or duration is int:
			animation.durations.append(clampf(float(duration), 0.01, 1000.0))
	animation.fps = clampf(float(data.get("fps", 12.0)), 0.1, 120.0)
	var saved_mode := int(data.get("mode", Mode.LOOP))
	animation.mode = saved_mode as Mode if saved_mode in Mode.values() else Mode.LOOP
	return animation


func to_dictionary() -> Dictionary:
	var data := {"name": name, "cells": cells.duplicate(), "fps": fps, "mode": mode}
	if durations.any(func(duration: float) -> bool: return duration != 1.0):
		data.durations = durations.slice(0, cells.size())
	return data


## How long the cell at [param index] of [member cells] is shown, in frames
func get_duration(index: int) -> float:
	return durations[index] if index < durations.size() else 1.0


## The cells that have a frame in [param sheet]
func get_frame_cells(sheet: Spritesheet) -> Array[Vector2i]:
	return cells.filter(sheet.has_frame)


## The durations of [method get_frame_cells]
func get_frame_durations(sheet: Spritesheet) -> Array[float]:
	var result: Array[float] = []
	for i in cells.size():
		if sheet.has_frame(cells[i]):
			result.append(get_duration(i))
	return result


## The cells in the order they're shown over one cycle: ping-pong plays back again,
## without repeating the ends
func get_playback_cells(sheet: Spritesheet) -> Array[Vector2i]:
	var played := get_frame_cells(sheet)
	if mode == Mode.PING_PONG:
		played.assign(ping_pong(played))
	return played


## The durations of [method get_playback_cells]
func get_playback_durations(sheet: Spritesheet) -> Array[float]:
	var played := get_frame_durations(sheet)
	if mode == Mode.PING_PONG:
		played.assign(ping_pong(played))
	return played


## [param items] followed by the way back, without repeating the ends
static func ping_pong(items: Array) -> Array:
	var result := items.duplicate()
	if items.size() > 2:
		var back := items.slice(1, items.size() - 1)
		back.reverse()
		result.append_array(back)
	return result


## Seconds one cycle of the animation takes in [param sheet]
func get_length(sheet: Spritesheet) -> float:
	var total := 0.0
	for duration in get_playback_durations(sheet):
		total += duration
	return total / fps


## Reads frame numbers such as "0-3, 5*2, 9-7": single numbers and ranges, which count
## down when the first number is bigger, each optionally followed by how many frames it's
## shown for. Returns [code]{"numbers": Array[int], "durations": Array[float]}[/code], or
## [code]{"error": String}[/code] naming the part that couldn't be read.
static func parse_numbers(text: String) -> Dictionary:
	var numbers: Array[int] = []
	var durations: Array[float] = []
	for part in text.replace(",", " ").replace(" *", "*").replace("* ", "*").split(" ", false):
		var duration := 1.0
		var range_text := part
		if part.count("*") == 1:
			var length := part.get_slice("*", 1)
			if not length.is_valid_float() or float(length) <= 0:
				return {"error": part}
			duration = float(length)
			range_text = part.get_slice("*", 0)
		var ends := range_text.split("-", false)
		var valid := ends.size() in [1, 2] and ends[0].is_valid_int()
		valid = valid and (ends.size() == 1 or ends[1].is_valid_int())
		valid = valid and range_text.count("-") == ends.size() - 1
		if not valid:
			return {"error": part}
		var first := int(ends[0])
		var last := int(ends[-1])
		var step := 1 if last >= first else -1
		for number in range(first, last + step, step):
			numbers.append(number)
			durations.append(duration)
	return {"numbers": numbers, "durations": durations}


## Writes [param numbers] the way [method parse_numbers] reads them, with runs as ranges.
## [param durations] are added to the numbers they're not 1 for.
static func format_numbers(numbers: Array[int], durations: Array[float] = []) -> String:
	var duration_of := func(index: int) -> float:
		return durations[index] if index < durations.size() else 1.0
	var parts: PackedStringArray = []
	var i := 0
	while i < numbers.size():
		var duration: float = duration_of.call(i)
		# A run of three or more numbers counting up or down by one, shown equally long
		var end := i
		if i + 1 < numbers.size() and absi(numbers[i + 1] - numbers[i]) == 1:
			var step := numbers[i + 1] - numbers[i]
			while (
				end + 1 < numbers.size()
				and numbers[end + 1] - numbers[end] == step
				and duration_of.call(end + 1) == duration
			):
				end += 1
		if end - i >= 2:
			parts.append("%d-%d%s" % [numbers[i], numbers[end], _format_duration(duration)])
			i = end + 1
		else:
			parts.append(str(numbers[i]) + _format_duration(duration))
			i += 1
	return ", ".join(parts)


static func _format_duration(duration: float) -> String:
	if is_equal_approx(duration, 1.0):
		return ""
	if is_equal_approx(duration, roundf(duration)):
		return "*%d" % roundi(duration)
	return "*" + String.num(duration, 2)
