class_name ExportController
extends Node
## Writes exports: the project's export targets (see [ExportTarget]) or a one-off export,
## then says where the files went and what went wrong.

## Whether exports are downloaded, as in a browser, where targets have no paths
static var in_browser := WebFiles.is_web()

## Opens the Export dialog, for exporting again when no target has a place to write to
var open_dialog := func() -> void: pass
## Returns the selected frames, for exporting only those
var get_selected_coords := func() -> Array[Vector2i]: return []
var warned_about_jpg_transparency := false


## Exports every target of the project, or opens the Export dialog when there's none that
## knows where to write
func export_again() -> bool:
	var targets := ExportTarget.list(Global.spritesheet)
	if not targets.any(has_place):
		open_dialog.call()
		return false
	return await export_targets(targets)


## Writes [param targets] one after the other, then says where their files went in one
## message and what went wrong in another. Returns whether every one was written.
func export_targets(targets: Array[ExportTarget]) -> bool:
	var results: Array[Dictionary] = []
	for target in targets:
		if has_place(target):
			results.append(await _export(get_output_path(target), target.options))
		else:
			results.append({"error": tr("Pick where to export %s.") % target.get_format_name()})
	return _report(results)


## Exports what [param options] say, or else the sheet's export settings, to [param path],
## with the extension of the file written unless it's typed with it (see
## [method SpritesheetExporter.with_extension])
func export_to(path: String, options: ExportOptions = null) -> bool:
	if options == null:
		options = ExportOptions.from_sheet(Global.spritesheet)
	return _report([await _export(path, options)])


## Whether [param target] can be exported without asking where: it has a path, or it's
## downloaded
static func has_place(target: ExportTarget) -> bool:
	return target.path != "" or in_browser


## Where [param target] writes: its path, fitted to what it writes (see
## [method ExportTarget.fit_path]), or in a browser a file to download, named as suggested
static func get_output_path(target: ExportTarget) -> String:
	if not in_browser:
		return ExportTarget.fit_path(target.path, target.options)
	var suggested := suggested_path(target.options).get_file()
	if target.options.target == ExportOptions.Target.SPRITES:
		return WebFiles.output_path(suggested + "_sprites")
	return WebFiles.output_path(suggested)


## Where to suggest exporting: next to the last export, else the file the document is
## named after (see [method Document.get_name_path]), with its name and the export's
## extension (see [method SpritesheetExporter.with_extension])
static func suggested_path(options: ExportOptions) -> String:
	var document := Global.document
	var base := document.export_path if document.export_path else document.get_name_path()
	var folder := base.get_base_dir()
	var base_name := FileController.suggested_name(base)
	if options.target == ExportOptions.Target.ATLAS and not base_name.ends_with("_atlas"):
		base_name += "_atlas"
	if options.target == ExportOptions.Target.STRIPS:
		base_name += "_strips"
	elif options.target == ExportOptions.Target.GIF and options.gif_every_animation:
		base_name += "_gifs"
	elif options.target == ExportOptions.Target.GIF and options.gif_animation:
		base_name += "_" + options.gif_animation.validate_filename()
	var path := folder.path_join(base_name)
	var extension := options.get_file_extension()
	if not extension:
		return path
	# The same file, spelled as it was ("HERO.PNG")
	if path == base.get_basename() and SpritesheetExporter.has_extension(base, extension):
		return base
	return SpritesheetExporter.with_extension(path, extension)


## Writes one export. Returns [code]{"message": String}[/code] saying what was written,
## or [code]{"error": String}[/code].
func _export(path: String, options: ExportOptions) -> Dictionary:
	if options.get_file_extension():
		path = SpritesheetExporter.with_extension(path, options.get_file_extension())
	# The template may have changed since it was picked
	if options.get_error():
		return {"error": options.get_error()}
	# Every scale's strips go in the one folder, written at once, see [StripExporter]
	if options.target == ExportOptions.Target.STRIPS:
		return await _export_at_scale(path, options)
	var messages := PackedStringArray()
	for scale in options.get_scales():
		var result := await _export_at_scale(
			options.scaled_path(path, scale), options.for_scale(scale)
		)
		if result.has("error"):
			return result
		messages.append(result.message)
	return {"message": "\n".join(messages)}


## Writes one scale of an export, see [member ExportOptions.scale]
func _export_at_scale(path: String, options: ExportOptions) -> Dictionary:
	var slow := FileController.is_big_sheet()
	match options.target:
		_ when options.packs(Global.spritesheet):
			return await Notify.run_busy(
				"Packing the atlas", _export_atlas.bind(path, options), slow
			)
		ExportOptions.Target.GIF:
			return await _export_gif(path, options)
		ExportOptions.Target.SPRITES:
			return await Notify.run_busy(
				"Exporting sprites", _save_sprites.bind(path, options), slow
			)
		ExportOptions.Target.STRIPS:
			return await Notify.run_busy("Exporting strips", _save_strips.bind(path, options), slow)
	return await Notify.run_busy("Exporting", _export_image.bind(path, options), slow)


## Says what [param results] of [method _export] wrote, and what went wrong. Returns
## whether nothing did.
static func _report(results: Array[Dictionary]) -> bool:
	var written := PackedStringArray()
	var errors := PackedStringArray()
	for result in results:
		if result.has("error"):
			errors.append(result.error)
		elif result.get("message"):
			written.append(result.message)
	if not written.is_empty():
		var text := "\n".join(written)
		Notify.toast(text, 7.0 if "\n" in text else 3.0)
	if not errors.is_empty():
		Notify.error("\n\n".join(errors))
	return errors.is_empty()


func _save_sprites(folder: String, options: ExportOptions) -> Dictionary:
	var errors: PackedStringArray = []
	var coords: Array[Vector2i] = []
	if options.only_selected:
		coords = get_selected_coords.call()
		if coords.is_empty():
			return {
				"error":
				tr(
					(
						'No frames are selected. Select frames or turn off "Only selected frames" '
						+ "when exporting."
					)
				)
			}
	_empty_download_folder(folder)
	var written := SpritesheetExporter.export_sprites(
		Global.spritesheet, folder, errors, Settings.get_value(&"index_start"), options, coords
	)
	unlink_overwritten(written)
	if not errors.is_empty():
		return {"error": tr("Could not save: %s.") % ", ".join(errors)}
	WebFiles.download_folder(folder, folder.get_file() + ".zip")
	return {"message": tr("Saved %d images to %s.") % [written.size(), folder.get_file()]}


## Writes a GameMaker strip of each animation into [param folder]
func _save_strips(folder: String, options: ExportOptions) -> Dictionary:
	_empty_download_folder(folder)
	var result := StripExporter.write(Global.spritesheet, options, folder)
	if result.error == ERR_DOES_NOT_EXIST:
		return {"error": tr("The spritesheet is empty.")}
	if result.error == ERR_OUT_OF_MEMORY:
		return {"error": result.message}
	if result.error != OK:
		return {
			"error": tr("Could not export to %s (%s).") % [result.path, error_string(result.error)]
		}
	unlink_overwritten(result.paths)
	WebFiles.download_folder(folder, folder.get_file() + ".zip")
	return {"message": tr("Saved %d strips to %s.") % [result.paths.size(), folder.get_file()]}


## Writes the animation chosen in [param options] as an animated GIF, or a GIF of each
## animation into the folder at [param path]
func _export_gif(path: String, options: ExportOptions) -> Dictionary:
	if options.gif_every_animation:
		return await _export_gifs(path, options)
	var result := await GifEncoder.write(
		Global.spritesheet,
		options,
		path,
		func(done: int, total: int) -> void: Notify.progress("Making the GIF", done, total)
	)
	Notify.hide_progress()
	if result.error == ERR_DOES_NOT_EXIST:
		return {"error": tr("The animation has no frames.")}
	if result.error != OK:
		return {
			"error": tr("Could not export to %s (%s).") % [result.path, error_string(result.error)]
		}
	unlink_overwritten([result.path])
	WebFiles.download(result.path)
	return {"message": tr("Exported %s (%d frames).") % [result.path.get_file(), result.frames]}


## Writes a GIF of each animation into [param folder]
func _export_gifs(folder: String, options: ExportOptions) -> Dictionary:
	_empty_download_folder(folder)
	var result := await GifEncoder.write_every(
		Global.spritesheet,
		options,
		folder,
		func(done: int, total: int) -> void: Notify.progress("Making the GIFs", done, total)
	)
	Notify.hide_progress()
	if result.error == ERR_DOES_NOT_EXIST:
		return {"error": tr("No animation has frames.")}
	if result.error != OK:
		return {
			"error": tr("Could not export to %s (%s).") % [result.path, error_string(result.error)]
		}
	unlink_overwritten(result.paths)
	WebFiles.download_folder(folder, folder.get_file() + ".zip")
	return {"message": tr("Saved %d GIFs to %s.") % [result.paths.size(), folder.get_file()]}


## A browser downloads the folder an export writes, which only has this export
static func _empty_download_folder(folder: String) -> void:
	if in_browser:
		DirAccess.make_dir_recursive_absolute(folder)
		for file in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file))


func _export_image(path: String, options: ExportOptions) -> Dictionary:
	var sheet := Global.spritesheet
	if sheet.is_empty():
		return {"error": tr("The spritesheet is empty.")}
	if sheet.layout == Spritesheet.Layout.PACKED:
		return _export_pages(path, options)
	var problem := ImageUtils.size_problem(
		SpritesheetExporter.get_image_size(sheet, options), path.get_extension()
	)
	if problem:
		return {"error": problem + "\n" + tr("Make the sprites smaller or use fewer cells.")}
	var spritesheet_image := sheet.get_image(options)
	var error := SpritesheetExporter.save_image(spritesheet_image, path, options)
	if error != OK:
		return {"error": tr("Could not export to %s (%s).") % [path, error_string(error)]}
	unlink_overwritten([path])

	var message := tr("Exported %s in %s.") % [path.get_file(), path.get_base_dir().get_file()]
	var metadata_error := Metadata.write_for_image(
		sheet, options, path, Settings.get_value(&"index_start")
	)
	if metadata_error != OK:
		return {"error": tr("Could not write the metadata (%s).") % error_string(metadata_error)}
	WebFiles.download(path)
	if options.get_image_data():
		var data_path := Metadata.get_path_for_image(path, options)
		unlink_overwritten([data_path])
		message += tr("\nAlso wrote %s.") % data_path.get_file()
		WebFiles.download(data_path)
	if (
		not SpritesheetExporter.supports_transparency(path)
		and ImageUtils.has_transparency(spritesheet_image)
		and not warned_about_jpg_transparency
	):
		warned_about_jpg_transparency = true
		message += (
			tr("\nJPG doesn't support transparency, so transparent areas were filled with %s.")
			% (
				tr("white")
				if options.opaque_background == Color.WHITE
				else tr("the background colour")
			)
		)
	if options.scale == 1:
		Global.document.export_path = path
	return {"message": message}


## Writes each page of the packed sheet as an image, numbered when there are more
func _export_pages(path: String, options: ExportOptions) -> Dictionary:
	var pages := SpritesheetExporter.build_pages(Global.spritesheet, options)
	var paths := SpritesheetExporter.get_page_paths(
		path, pages.size(), options.get_scale_suffix(options.scale)
	)
	for i in pages.size():
		var problem := ImageUtils.size_problem(pages[i].get_size(), path.get_extension())
		if problem:
			return {"error": problem}
		var error := SpritesheetExporter.save_image(pages[i], paths[i], options)
		if error != OK:
			return {"error": tr("Could not export to %s (%s).") % [paths[i], error_string(error)]}
		WebFiles.download(paths[i])
	unlink_overwritten(paths)
	if options.scale == 1:
		Global.document.export_path = path
	if paths.size() == 1:
		return {
			"message": tr("Exported %s in %s.") % [path.get_file(), path.get_base_dir().get_file()]
		}
	return {"message": tr("Exported %d pages, from %s.") % [paths.size(), paths[0].get_file()]}


## Packs trimmed frames tightly and writes the atlas's pages with a data file
func _export_atlas(path: String, options: ExportOptions) -> Dictionary:
	var result := AtlasPacker.write(
		Global.spritesheet, options, path, Settings.get_value(&"index_start")
	)
	if result.error == ERR_OUT_OF_MEMORY:
		return {"error": tr("The frames don't fit in a %d px atlas.") % AtlasPacker.MAX_SIZE}
	if result.error == ERR_UNAVAILABLE:
		return {"error": tr(result.message)}
	if result.error != OK:
		return {"error": tr("Could not export the atlas (%s).") % error_string(result.error)}
	unlink_overwritten(result.paths)
	for written: String in result.paths:
		WebFiles.download(written)
	var size: Vector2i = result.size
	if result.pages > 1:
		return {
			"message":
			(
				tr("Packed %d frames on %d pages, from %s, and %s.")
				% [result.frames, result.pages, result.path.get_file(), result.json_path.get_file()]
			)
		}
	return {
		"message":
		(
			tr("Packed %d frames into %s (%d×%d px) and %s.")
			% [result.frames, result.path.get_file(), size.x, size.y, result.json_path.get_file()]
		)
	}


## Frames linked to files that were just written over would be cut from what
## spritesheetbelli made, with their edits made twice, so they're unlinked instead
func unlink_overwritten(paths: PackedStringArray) -> void:
	var document := Global.document
	var unlinked: PackedStringArray = []
	for path in paths:
		if path not in document.unwatched_paths:
			document.unwatched_paths.append(path)
		document.source_hashes.erase(path)
		if FrameSource.unlink(Global.spritesheet, path) > 0:
			unlinked.append(path.get_file())
	if not unlinked.is_empty():
		Notify.toast(
			(
				tr("Frames from %s are no longer linked to it, since the export wrote over it.")
				% ", ".join(unlinked)
			),
			6.0
		)
