class_name StripExporter
## Writes GameMaker strips: an image of each animation with its frames side by side, left
## to right, each as big as a cell and with nothing between them, named "_strip" and how
## many frames it has ([code]walk_strip8.png[/code]). GameMaker's importer cuts such an
## image into that many frames of equal width and takes "_strip8" off the sprite's name.
## Frames in no animation are left out; a sheet without animations is one strip of every
## frame, named "frame" as the {animation} token names frames in no animation.


## The strips [method write] writes in [param folder], in the order of the animations:
## [code]{"name": String, "cells": Array[Vector2i], "path": String}[/code], with the
## animation's name and its frames in order, as it lists them. Animations without frames
## are left out.
static func get_strips(
	sheet: Spritesheet, options: ExportOptions, folder: String
) -> Array[Dictionary]:
	var strips: Array[Dictionary] = []
	for animation in sheet.animations:
		var cells := animation.get_frame_cells(sheet)
		if not cells.is_empty():
			strips.append({"name": animation.name, "cells": cells})
	if sheet.animations.is_empty() and not sheet.is_empty():
		strips.append({"name": "frame", "cells": sheet.get_sorted_coords()})
	var entries: Array[Dictionary] = []
	for strip in strips:
		entries.append({"name": strip.name, "count": strip.cells.size()})
	var paths := AnimationFiles.get_paths(folder, options.strip_name_pattern, "png", entries)
	for i in strips.size():
		strips[i].path = paths[i]
	return strips


## The frames at [param cells] side by side, each in a cell of [param sheet], over
## [param background]
static func build_strip(
	sheet: Spritesheet, cells: Array[Vector2i], background := Color.TRANSPARENT
) -> Image:
	var cell := sheet.sprite_size
	var strip := Image.create_empty(
		maxi(cell.x * cells.size(), 1), maxi(cell.y, 1), false, Image.FORMAT_RGBA8
	)
	if background.a > 0:
		strip.fill(background)
	for i in cells.size():
		var frame := sheet.get_cell_image(cells[i])
		var at := Vector2i(cell.x * i, 0)
		if background.a > 0:
			strip.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
		else:
			strip.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
	return strip


## Writes the strips of [param sheet] into [param folder], see [method get_strips].
## Returns [code]{"error": Error, "message": String, "path": String, "paths":
## PackedStringArray}[/code] with the strips written and the last one tried; the error is
## ERR_DOES_NOT_EXIST when there's nothing to write, and ERR_OUT_OF_MEMORY when a strip
## is too big for a PNG, with a message saying why.
static func write(sheet: Spritesheet, options: ExportOptions, folder: String) -> Dictionary:
	var strips := get_strips(sheet, options, folder)
	var result := {"error": OK, "message": "", "path": folder, "paths": PackedStringArray()}
	if strips.is_empty():
		result.error = ERR_DOES_NOT_EXIST
		return result
	DirAccess.make_dir_recursive_absolute(folder)
	for strip in strips:
		result.path = strip.path
		var size := sheet.sprite_size * Vector2i(strip.cells.size(), 1)
		result.message = ImageUtils.size_problem(size)
		if result.message:
			result.error = ERR_OUT_OF_MEMORY
			return result
		result.error = build_strip(sheet, strip.cells, options.background).save_png(strip.path)
		if result.error != OK:
			return result
		result.paths.append(strip.path)
	return result
