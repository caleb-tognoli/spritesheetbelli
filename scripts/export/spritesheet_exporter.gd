class_name SpritesheetExporter
## Builds images and files from a [Spritesheet].

## File extensions that can be exported, lowercase
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "webp", "jpg", "jpeg", "jpe"]


## Size of the exported image
static func get_image_size(sheet: Spritesheet, options: ExportOptions) -> Vector2i:
	if sheet.grid_size == Vector2i.ZERO or sheet.sprite_size == Vector2i.ZERO:
		return Vector2i.ZERO
	var cell := sheet.sprite_size + Vector2i.ONE * options.extrude * 2
	return (
		Vector2i.ONE * options.padding * 2
		+ cell * sheet.grid_size
		+ Vector2i.ONE * options.spacing * (sheet.grid_size - Vector2i.ONE)
	)


## Where the cell at [param coord] ends up in the exported image, without extrusion
static func get_cell_rect(sheet: Spritesheet, coord: Vector2i, options: ExportOptions) -> Rect2i:
	var step := sheet.sprite_size + Vector2i.ONE * (options.extrude * 2 + options.spacing)
	var position := Vector2i.ONE * (options.padding + options.extrude) + coord * step
	return Rect2i(position, sheet.sprite_size)


## Where the frame itself (centred in its cell) ends up in the exported image
static func get_frame_rect(sheet: Spritesheet, coord: Vector2i, options: ExportOptions) -> Rect2i:
	var in_cell := sheet.get_frame_rect_in_cell(coord)
	return Rect2i(get_cell_rect(sheet, coord, options).position + in_cell.position, in_cell.size)


static func build_image(sheet: Spritesheet, options: ExportOptions) -> Image:
	var size := get_image_size(sheet, options)
	if size.x <= 0 or size.y <= 0:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	if options.background.a > 0:
		img.fill(options.background)
	for coord in sheet.frames:
		var frame := sheet.get_frame_image(coord)
		var rect := get_frame_rect(sheet, coord, options)
		if options.background.a > 0:
			img.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), rect.position)
		else:
			img.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), rect.position)
		if options.extrude > 0:
			_extrude(img, rect, options.extrude)
	return img


## Repeats the edge pixels of [param rect] outward by [param amount] pixels
static func _extrude(img: Image, rect: Rect2i, amount: int) -> void:
	var left := Rect2i(rect.position.x, rect.position.y, 1, rect.size.y)
	var right := Rect2i(rect.end.x - 1, rect.position.y, 1, rect.size.y)
	for i in range(1, amount + 1):
		img.blit_rect(img, left, Vector2i(rect.position.x - i, rect.position.y))
		img.blit_rect(img, right, Vector2i(rect.end.x - 1 + i, rect.position.y))
	# Rows include the extruded columns, which also fills the corners
	var wide := rect.grow_individual(amount, 0, amount, 0)
	var top := Rect2i(wide.position.x, rect.position.y, wide.size.x, 1)
	var bottom := Rect2i(wide.position.x, rect.end.y - 1, wide.size.x, 1)
	for i in range(1, amount + 1):
		img.blit_rect(img, top, Vector2i(wide.position.x, rect.position.y - i))
		img.blit_rect(img, bottom, Vector2i(wide.position.x, rect.end.y - 1 + i))


static func supports_transparency(path: String) -> bool:
	return path.get_extension().to_lower() not in ["jpg", "jpeg", "jpe"]


## Adds .png when [param path] has no known image extension
static func with_image_extension(path: String) -> String:
	if path.get_extension().to_lower() in IMAGE_EXTENSIONS:
		return path
	return path + ".png"


## Saves [param img] in the format given by the extension of [param path]
static func save_image(img: Image, path: String, options := ExportOptions.new()) -> Error:
	match path.get_extension().to_lower():
		"jpg", "jpeg", "jpe":
			var flat := ImageUtils.flatten(img, options.opaque_background)
			return flat.save_jpg(path, options.jpg_quality)
		"webp":
			return img.save_webp(path)
	return img.save_png(path)


## Fills a sprite file name pattern. Tokens: {index} (as numbered in the preview),
## {row}, {column}, {row_name}, {frame} (position in its row) and {name} (original
## file name). A width pads numbers with zeros: {index:3} gives 007.
static func format_sprite_name(
	pattern: String, sheet: Spritesheet, coord: Vector2i, index_start := 0
) -> String:
	var frame_in_row := 0
	for c in sheet.frames:
		if c.y == coord.y and c.x < coord.x:
			frame_in_row += 1
	var values := {
		"index": sheet.index_of(coord) + index_start,
		"row": coord.y,
		"column": coord.x,
		"frame": frame_in_row + index_start,
		"row_name": sheet.row_names.get(coord.y, "row%d" % coord.y),
		"name": sheet.frames[coord].resource_name.get_basename(),
	}
	var regex := RegEx.create_from_string("\\{(\\w+)(?::(\\d+))?\\}")
	var result := pattern
	for found in regex.search_all(pattern):
		var key := found.get_string(1)
		if not values.has(key):
			continue
		var value: Variant = values[key]
		var text := str(value)
		if value is int and found.get_string(2):
			text = text.pad_zeros(int(found.get_string(2)))
		result = result.replace(found.get_string(), text)
	# Keep the name usable as a file name
	return result.validate_filename() if result.strip_edges() else str(values.index)


## Saves frames as their own PNGs, named with the options' pattern.
## Returns the paths written; problems are added to [param errors].
static func export_sprites(
	sheet: Spritesheet,
	folder: String,
	errors: PackedStringArray = [],
	index_start := 0,
	options := ExportOptions.new(),
	coords: Array[Vector2i] = [],
) -> PackedStringArray:
	if coords.is_empty():
		coords = sheet.get_sorted_coords()
	var written: PackedStringArray = []
	for coord in coords:
		var base := folder.path_join(
			format_sprite_name(options.sprite_name_pattern, sheet, coord, index_start)
		)
		var path := base + ".png"
		if FileAccess.file_exists(path):
			match options.existing_files:
				ExportOptions.Existing.SKIP:
					continue
				ExportOptions.Existing.ADD_NUMBER:
					path = _unique_path(base, ".png")
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
