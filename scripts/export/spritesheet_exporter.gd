class_name SpritesheetExporter
## Builds images and files from a [Spritesheet].


static func build_image(sheet: Spritesheet, options: ExportOptions) -> Image:
	var size := sheet.sprite_size * sheet.grid_size
	if size.x <= 0 or size.y <= 0:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	if options.background.a > 0:
		img.fill(options.background)
	for coord in sheet.frames:
		var frame := sheet.get_frame_image(coord)
		var position := coord * sheet.sprite_size + sheet.get_frame_rect_in_cell(coord).position
		if options.background.a > 0:
			img.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), position)
		else:
			img.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), position)
	return img


## Saves every frame as its own PNG named after its index on the grid.
## Returns the paths written, or an empty array and the error through [param errors].
static func export_sprites(
	sheet: Spritesheet, folder: String, errors: PackedStringArray = []
) -> PackedStringArray:
	var written: PackedStringArray = []
	for coord in sheet.get_sorted_coords():
		var path := _unique_path(folder.path_join(str(sheet.index_of(coord))), ".png")
		var error := sheet.get_cell_image(coord).save_png(path)
		if error != OK:
			errors.append("%s (%s)" % [path.get_file(), error_string(error)])
		else:
			written.append(path)
	return written


## Adds (1), (2)... before the extension when a file already exists
static func _unique_path(base: String, extension: String) -> String:
	if not FileAccess.file_exists(base + extension):
		return base + extension
	var i := 1
	while FileAccess.file_exists("%s(%d)%s" % [base, i, extension]):
		i += 1
	return "%s(%d)%s" % [base, i, extension]
