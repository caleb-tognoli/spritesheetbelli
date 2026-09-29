class_name StripExporter
## Writes GameMaker strips: an image of each animation with its frames side by side, left
## to right, each as big as a cell and with nothing between them, named "_strip" and how
## many frames it has ([code]walk_strip8.png[/code]). GameMaker's importer cuts such an
## image into that many frames of equal width and takes "_strip8" off the sprite's name.
## Frames in no animation are left out; a sheet without animations is one strip of every
## frame, named "frame" as the {animation} token names frames in no animation.
## At several scales (see [member ExportOptions.scales]) every scale's strips go in the one
## folder, with the scale's suffix before "_strip" ([code]walk@2x_strip8.png[/code]), so
## that GameMaker names the sprite with it.


## The strips [method write] writes in [param folder], in the order of the animations,
## each scale's after the one before: [code]{"name": String, "cells": Array[Vector2i],
## "path": String, "scale": int}[/code], with the animation's name and its frames in
## order, as it lists them. Animations without frames are left out.
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
	var result: Array[Dictionary] = []
	for scale in options.get_scales():
		var pattern := get_name_pattern(options, scale)
		var paths := AnimationFiles.get_paths(folder, pattern, "png", entries)
		for i in strips.size():
			var strip := strips[i].duplicate()
			strip.path = paths[i]
			strip.scale = scale
			result.append(strip)
	return result


## [member ExportOptions.strip_name_pattern] for the strips of [param scale]: with the
## scale's suffix (see [method ExportOptions.get_scale_suffix]) before the "_strip{count}"
## the pattern ends with, or else at its end
static func get_name_pattern(options: ExportOptions, scale: int) -> String:
	var suffix := options.get_scale_suffix(scale)
	if suffix.is_empty():
		return options.strip_name_pattern
	var pattern := SpritesheetExporter.without_extension(options.strip_name_pattern, "png")
	var strip := RegEx.create_from_string("(?i)_strip\\{count(:\\d+)?\\}$").search(pattern)
	if strip == null:
		return pattern + suffix
	return pattern.left(strip.get_start()) + suffix + strip.get_string()


## The frames at [param cells] side by side, each in a cell of [param sheet], over
## [param background], [param scale] times bigger: resized from their original images (see
## [method SpritesheetExporter.get_scaled_frame])
static func build_strip(
	sheet: Spritesheet, cells: Array[Vector2i], background := Color.TRANSPARENT, scale := 1
) -> Image:
	var cell := sheet.sprite_size * scale
	var strip := Image.create_empty(
		maxi(cell.x * cells.size(), 1), maxi(cell.y, 1), false, Image.FORMAT_RGBA8
	)
	if background.a > 0:
		strip.fill(background)
	for i in cells.size():
		var frame := _get_cell_image(sheet, cells[i], scale)
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
		var size: Vector2i = sheet.sprite_size * Vector2i(strip.cells.size(), 1) * strip.scale
		result.message = ImageUtils.size_problem(size)
		if result.message:
			result.error = ERR_OUT_OF_MEMORY
			return result
		var image := build_strip(sheet, strip.cells, options.background, strip.scale)
		result.error = image.save_png(strip.path)
		if result.error != OK:
			return result
		result.paths.append(strip.path)
	return result


## The frame at [param coord] in its cell, [param scale] times bigger
static func _get_cell_image(sheet: Spritesheet, coord: Vector2i, scale: int) -> Image:
	if scale == 1:
		return sheet.get_cell_image(coord)
	var size := sheet.sprite_size * scale
	var cell := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var frame := SpritesheetExporter.get_scaled_frame(sheet, coord, scale)
	var at := sheet.get_frame_rect_in_cell(coord).position * scale
	cell.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
	return cell
