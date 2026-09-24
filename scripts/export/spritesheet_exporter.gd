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
