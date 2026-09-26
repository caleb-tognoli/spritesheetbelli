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


## An animation of [param anim_cells] shown for [param seconds] each: the shortest frame
## sets the speed, and longer ones are held for more frames. Without timing (missing or
## zero seconds), it plays at 12 fps.
static func create_timed(
	anim_name: String, anim_cells: Array[Vector2i], seconds: Array[float]
) -> SheetAnimation:
	var animation := create(anim_name, anim_cells)
	if seconds.size() < anim_cells.size() or seconds.any(func(s: float) -> bool: return s <= 0):
		return animation
	var shortest: float = seconds.min()
	animation.fps = clampf(1.0 / shortest, 0.1, 120.0)
	var held: Array[float] = []
	for i in anim_cells.size():
		held.append(snappedf(seconds[i] / shortest, 0.01))
	if held.any(func(duration: float) -> bool: return duration != 1.0):
		animation.durations = held
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


## Adds a copy of the animation at [param index] of [param sheet] with its frames flipped
## horizontally in a new row below every frame, e.g. walk_left from walk_right. Returns the new
## animation's index, or -1 when it has no frames.
static func mirror(sheet: Spritesheet, index: int) -> int:
	var animations := sheet.animations
	if index < 0 or index >= animations.size():
		return -1
	var source := animations[index]
	var row := sheet.get_first_free_row()
	var copies := {}  # Source cell to its mirrored copy
	for cell in source.get_frame_cells(sheet):
		if not copies.has(cell):
			copies[cell] = Vector2i(copies.size(), row)
	if copies.is_empty():
		return -1
	var mirrored := SheetAnimation.from_dictionary(source.to_dictionary())
	mirrored.name = sheet.get_unique_animation_name(mirrored_name(source.name))
	mirrored.cells.clear()
	mirrored.durations.clear()
	for i in source.cells.size():
		if copies.has(source.cells[i]):
			mirrored.cells.append(copies[source.cells[i]])
			mirrored.durations.append(source.get_duration(i))
	sheet.begin_batch()
	for cell: Vector2i in copies:
		var data := sheet.get_cell_data(cell)
		data.erase("placement")
		sheet.set_cell(copies[cell], data)
	var targets: Array[Vector2i] = []
	targets.assign(copies.values())
	FrameEdits.flip(sheet, targets, true)
	sheet.set_row_name(row, mirrored.name)
	var new_index := sheet.add_animation(mirrored)
	sheet.end_batch()
	return new_index


## The name of a mirrored copy: left and right swapped, or else "_flipped" added
static func mirrored_name(animation_name: String) -> String:
	for pair: Array in [["right", "left"], ["Right", "Left"], ["RIGHT", "LEFT"]]:
		if pair[0] in animation_name:
			return animation_name.replace(pair[0], pair[1])
		if pair[1] in animation_name:
			return animation_name.replace(pair[1], pair[0])
	return animation_name + "_flipped"


## Reads frame numbers such as "0-3, 5*2, 9-7": single numbers and ranges, which count
## down when the first number is bigger, each optionally followed by how many frames it's
## shown for. Returns [code]{"numbers": Array[int], "durations": Array[float]}[/code], or
## [code]{"error": String}[/code] naming the part that couldn't be read.
## Frames can also be given by name, with the number each name stands for in
## [param names]: [code]idle, walk_0-walk_3, "jump up"*2[/code]. Names with spaces or
## commas go in quotes.
static func parse_numbers(text: String, names := {}) -> Dictionary:
	var numbers: Array[int] = []
	var held: Array[float] = []
	for part in _split_frames(text):
		var duration := 1.0
		var range_text := part
		var star := part.rfind("*")
		if star >= 0 and not part.ends_with('"'):
			var length := part.substr(star + 1)
			if not length.is_valid_float() or float(length) <= 0:
				return {"error": part}
			duration = float(length)
			range_text = part.substr(0, star)
		var ends := _range_ends(range_text, names)
		if ends.is_empty():
			return {"error": part}
		var step := 1 if ends[1] >= ends[0] else -1
		for number in range(ends[0], ends[1] + step, step):
			numbers.append(number)
			held.append(duration)
	return {"numbers": numbers, "durations": held}


## The parts of the frames text, split at commas and spaces outside quotes
static func _split_frames(text: String) -> PackedStringArray:
	var parts: PackedStringArray = []
	var current := ""
	var quoted := false
	# "3 * 2" is one part
	text = text.replace(" *", "*").replace("* ", "*")
	for character in text:
		if character == '"':
			quoted = not quoted
			current += character
		elif not quoted and character in [",", " ", "\t"]:
			if current:
				parts.append(current)
			current = ""
		else:
			current += character
	if current:
		parts.append(current)
	return parts


## The first and last number of a part: a number, a name, or a range of them joined with
## "-". Empty when it isn't one.
static func _range_ends(text: String, names: Dictionary) -> Array[int]:
	var single: Variant = _frame_number(text, names)
	if single != null:
		return [single, single] as Array[int]
	# Names can have dashes too, so every dash is tried
	var dash := text.find("-", 1)
	while dash > 0:
		var first: Variant = _frame_number(text.substr(0, dash), names)
		var last: Variant = _frame_number(text.substr(dash + 1), names)
		if first != null and last != null:
			return [first, last] as Array[int]
		dash = text.find("-", dash + 1)
	return [] as Array[int]


## The number [param text] stands for: a number, or a name in [param names], quoted or
## not. Null when it's neither.
static func _frame_number(text: String, names: Dictionary) -> Variant:
	if text.length() >= 2 and text.begins_with('"') and text.ends_with('"'):
		return names.get(text.substr(1, text.length() - 2))
	if text.is_valid_int():
		return int(text)
	return names.get(text)


## Writes [param numbers] the way [method parse_numbers] reads them, with runs as ranges.
## [param held] durations are added to the numbers they're not 1 for. Numbers with a
## name in [param labels] are written as that name.
static func format_numbers(numbers: Array[int], held: Array[float] = [], labels := {}) -> String:
	var duration_of := func(index: int) -> float: return held[index] if index < held.size() else 1.0
	var parts: PackedStringArray = []
	var i := 0
	while i < numbers.size():
		var duration: float = duration_of.call(i)
		if labels.has(numbers[i]):
			parts.append(_quoted(labels[numbers[i]]) + _format_duration(duration))
			i += 1
			continue
		# A run of three or more numbers counting up or down by one, shown equally long
		var end := i
		if i + 1 < numbers.size() and absi(numbers[i + 1] - numbers[i]) == 1:
			var step := numbers[i + 1] - numbers[i]
			while (
				end + 1 < numbers.size()
				and numbers[end + 1] - numbers[end] == step
				and duration_of.call(end + 1) == duration
				and not labels.has(numbers[end + 1])
			):
				end += 1
		if end - i >= 2:
			parts.append("%d-%d%s" % [numbers[i], numbers[end], _format_duration(duration)])
			i = end + 1
		else:
			parts.append(str(numbers[i]) + _format_duration(duration))
			i += 1
	return ", ".join(parts)


## A frame name as typed in the frames field: in quotes when it could be read otherwise
static func _quoted(label: String) -> String:
	for character: String in [" ", ",", "-", "*", '"', "\t"]:
		if character in label:
			return '"%s"' % label.replace('"', "")
	return '"%s"' % label if label.is_valid_float() else label


static func _format_duration(duration: float) -> String:
	if is_equal_approx(duration, 1.0):
		return ""
	if is_equal_approx(duration, roundf(duration)):
		return "*%d" % roundi(duration)
	return "*" + String.num(duration, 2)
