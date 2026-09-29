class_name SpritesheetExporter
## Builds images and files from a [Spritesheet].

## File extensions that can be exported, lowercase
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "webp", "jpg", "jpeg", "jpe"]
## The tokens of sprite name patterns, see [method format_sprite_name], with what they give
const SPRITE_NAME_TOKENS := {
	"index": "The frame's number, as in the preview",
	"row": "Its row, from 0",
	"column": "Its column, from 0",
	"frame": "Its place in its row",
	"animation": 'The first animation it\'s in, or "frame"',
	"animation_frame": "Its place in that animation, or else its number",
	"name": "The name of the file it came from",
}


## Size of the exported image. Everything is [member ExportOptions.scale] times bigger,
## the padding, spacing and extrusion too, so that each scale is the same image bigger.
static func get_image_size(sheet: Spritesheet, options: ExportOptions) -> Vector2i:
	if sheet.grid_size == Vector2i.ZERO or sheet.sprite_size == Vector2i.ZERO:
		return Vector2i.ZERO
	var cell := sheet.sprite_size + Vector2i.ONE * options.extrude * 2
	return (
		(
			Vector2i.ONE * options.padding * 2
			+ cell * sheet.grid_size
			+ Vector2i.ONE * options.spacing * (sheet.grid_size - Vector2i.ONE)
		)
		* options.scale
	)


## Where the cell at [param coord] ends up in the exported image, without extrusion
static func get_cell_rect(sheet: Spritesheet, coord: Vector2i, options: ExportOptions) -> Rect2i:
	var step := sheet.sprite_size + Vector2i.ONE * (options.extrude * 2 + options.spacing)
	var position := Vector2i.ONE * (options.padding + options.extrude) + coord * step
	return Rect2i(position * options.scale, sheet.sprite_size * options.scale)


## Where the frame itself (centred in its cell) ends up in the exported image
static func get_frame_rect(sheet: Spritesheet, coord: Vector2i, options: ExportOptions) -> Rect2i:
	var in_cell := sheet.get_frame_rect_in_cell(coord)
	return Rect2i(
		get_cell_rect(sheet, coord, options).position + in_cell.position * options.scale,
		in_cell.size * options.scale
	)


static func build_image(sheet: Spritesheet, options: ExportOptions) -> Image:
	var size := get_image_size(sheet, options)
	if size.x <= 0 or size.y <= 0:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	if options.background.a > 0:
		img.fill(options.background)
	for coord in sheet.frames:
		var frame := get_scaled_frame(sheet, coord, options.scale)
		var rect := get_frame_rect(sheet, coord, options)
		if options.background.a > 0:
			img.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), rect.position)
		else:
			img.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), rect.position)
		if options.extrude > 0:
			extrude_edges(img, rect, options.extrude * options.scale)
	return img


## The frame at [param coord] as the sheet shows it, [param scale] times bigger: resized
## from the original image with the sheet's filter, not from the sheet's scaled frame
static func get_scaled_frame(sheet: Spritesheet, coord: Vector2i, scale: int) -> Image:
	if scale == 1:
		return sheet.get_frame_image(coord)
	var original: Image = sheet.frames[coord]
	var size := sheet.scaled_frames.scaled_size(original.get_size()) * scale
	var img := original.duplicate() as Image
	img.resize(size.x, size.y, sheet.scale_filter)
	return img


## The pages of a packed sheet as images, on the export's background, at the export's
## scale
static func build_pages(sheet: Spritesheet, options: ExportOptions) -> Array[Image]:
	var pages := PackedLayout.render_pages(sheet, false, options.scale)
	if options.background.a > 0:
		for i in pages.size():
			var page := Image.create_empty(
				pages[i].get_width(), pages[i].get_height(), false, Image.FORMAT_RGBA8
			)
			page.fill(options.background)
			page.blend_rect(pages[i], Rect2i(Vector2i.ZERO, page.get_size()), Vector2i.ZERO)
			pages[i] = page
	return pages


## Where each of [param count] pages goes: [param path], or numbered from 0 when there
## are more, see [method get_page_path]
static func get_page_paths(path: String, count: int, suffix := "") -> PackedStringArray:
	if count <= 1:
		return PackedStringArray([path])
	var paths := PackedStringArray()
	for page in count:
		paths.append(get_page_path(path, page, suffix))
	return paths


## [param path] numbered as page [param page]. A path of a scale (see
## [method ExportOptions.scaled_path]) ends with [param suffix], the scale's suffix, which
## stays last, as iOS and Cocos name pages: "hero@2x.png" gives "hero_0@2x.png".
static func get_page_path(path: String, page: int, suffix := "") -> String:
	var extension := path.get_extension()
	var base := path.get_basename() if extension else path
	var last := suffix if suffix and base.ends_with(suffix) else ""
	var numbered := "%s_%d%s" % [base.left(base.length() - last.length()), page, last]
	return "%s.%s" % [numbered, extension] if extension else numbered


## Repeats the edge pixels of [param rect] outward by [param amount] pixels
static func extrude_edges(img: Image, rect: Rect2i, amount: int) -> void:
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


## Whether [param path] ends with [param extension], in any case. JPG's is also
## spelled "jpeg" and "jpe".
static func has_extension(path: String, extension: String) -> bool:
	var typed := path.get_extension().to_lower()
	if extension.to_lower() == "jpg":
		return typed in ["jpg", "jpeg", "jpe"]
	return typed == extension.to_lower()


## [param path] as a file with [param extension]: kept as typed when it has it ("HERO.PNG"
## and "hero.jpeg" stay), else with it added. Other extensions are part of the name, so
## the file typed is the file written: "hero.png" with "jpg" gives "hero.png.jpg".
static func with_extension(path: String, extension: String) -> String:
	return path if has_extension(path, extension) else path + "." + extension


## [param path] without [param extension], when it ends with it (see
## [method has_extension]): the name the files an export writes next to it are named
## from ("hero.png" and "png" give "hero", "hero.json" stays).
static func without_extension(path: String, extension: String) -> String:
	return path.get_basename() if has_extension(path, extension) else path


## The image format of [constant ExportOptions.IMAGE_FORMATS] the extension of
## [param path] names, or else "png"
static func get_image_format(path: String) -> String:
	match path.get_extension().to_lower():
		"jpg", "jpeg", "jpe":
			return "jpg"
		"webp":
			return "webp"
	return "png"


## [param path] as an image in the format its extension names, or else as a PNG (see
## [method with_extension]): "hero.JPEG" stays and "hero.json" gives "hero.json.png". For
## the command line, where the name picks the format.
static func with_image_extension(path: String) -> String:
	return with_extension(path, get_image_format(path))


## Saves [param img] in the format given by the extension of [param path]
static func save_image(img: Image, path: String, options := ExportOptions.new()) -> Error:
	match path.get_extension().to_lower():
		"jpg", "jpeg", "jpe":
			var flat := ImageUtils.flatten(img, options.opaque_background)
			return flat.save_jpg(path, options.jpg_quality)
		"webp":
			return img.save_webp(path)
	return img.save_png(path)


## Fills a sprite file name pattern with what [method get_sprite_name_values] gives for
## the frame at [param coord]: {index} (as numbered in the preview), {row}, {column},
## {frame} (position in its row), {animation} (the first animation showing it, or
## "frame"), {animation_frame} (position in that animation, or else its index) and
## {name} (original file name). A width pads numbers with zeros: {index:3} gives 007.
## Other tokens are kept as they are (see [method get_unknown_tokens]).
static func format_sprite_name(
	pattern: String, sheet: Spritesheet, coord: Vector2i, index_start := 0
) -> String:
	# Only looked up when asked for, as it goes through every animation
	var values := get_sprite_name_values(sheet, coord, index_start, "{animation" in pattern)
	# The extension is added when saving: "{index}.png" names "0.png", not "0.png.png"
	return fill_tokens(without_extension(pattern, "png"), values, str(values.index))


## [param pattern] with its tokens filled in from [param values], by token name, as a file
## name, or [param fallback] when that's empty. A width pads numbers with zeros: {index:3}
## gives 007. Other tokens are kept as they are.
static func fill_tokens(pattern: String, values: Dictionary, fallback: String) -> String:
	var result := pattern
	for found in _token_regex().search_all(pattern):
		var key := found.get_string(1)
		if not values.has(key):
			continue
		var value: Variant = values[key]
		var text := str(value)
		if value is int and found.get_string(2):
			text = text.pad_zeros(int(found.get_string(2)))
		result = result.replace(found.get_string(), text)
	# Keep the name usable as a file name
	return result.validate_filename() if result.strip_edges() else fallback


## What each token of [constant SPRITE_NAME_TOKENS] gives for the frame at [param coord].
## Without [param with_animation], {animation} is "frame" and {animation_frame} its index,
## as for a frame in no animation.
static func get_sprite_name_values(
	sheet: Spritesheet, coord: Vector2i, index_start := 0, with_animation := true
) -> Dictionary:
	var frame_in_row := 0
	for c in sheet.frames:
		if c.y == coord.y and c.x < coord.x:
			frame_in_row += 1
	var values := {
		"index": sheet.index_of(coord) + index_start,
		"row": coord.y,
		"column": coord.x,
		"frame": frame_in_row + index_start,
		"animation": "frame",
		"animation_frame": sheet.index_of(coord) + index_start,
		"name": sheet.frames[coord].resource_name.get_basename(),
	}
	if with_animation:
		for animation in sheet.animations:
			var position := animation.get_frame_cells(sheet).find(coord)
			if position >= 0:
				values.animation = animation.name
				values.animation_frame = position + index_start
				break
	return values


## The tokens of [param pattern] that aren't in [param known] (by default
## [constant SPRITE_NAME_TOKENS]) or are written wrong, like {anim} or {index:}, each once.
## Names keep them as they are.
static func get_unknown_tokens(pattern: String, known := SPRITE_NAME_TOKENS) -> PackedStringArray:
	var unknown := PackedStringArray()
	for found in RegEx.create_from_string("\\{[^{}]*\\}").search_all(pattern):
		var text := found.get_string()
		var token := _token_regex().search(text)
		var is_known := (
			token != null and token.get_string() == text and known.has(token.get_string(1))
		)
		if not is_known and text not in unknown:
			unknown.append(text)
	return unknown


## Frames whose names show what a pattern gives: the first ones, those in an animation
## first
static func get_example_coords(sheet: Spritesheet, count := 3) -> Array[Vector2i]:
	var animated := {}
	for animation in sheet.animations:
		for coord in animation.get_frame_cells(sheet):
			animated[coord] = true
	var coords := sheet.get_sorted_coords()
	var examples: Array[Vector2i] = coords.filter(func(c: Vector2i) -> bool: return c in animated)
	examples.append_array(coords.filter(func(c: Vector2i) -> bool: return c not in animated))
	return examples.slice(0, count)


## Saves frames as their own PNGs, named with the options' pattern, where
## [method get_sprite_paths] says. Returns the paths written; problems are added to
## [param errors].
static func export_sprites(
	sheet: Spritesheet,
	folder: String,
	errors: PackedStringArray = [],
	index_start := 0,
	options := ExportOptions.new(),
	coords: Array[Vector2i] = [],
) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(folder)
	var written: PackedStringArray = []
	for sprite in get_sprite_paths(sheet, folder, options, coords, index_start):
		var path: String = sprite.path
		var error := sheet.get_cell_image(sprite.coord).save_png(path)
		if error != OK:
			errors.append("%s (%s)" % [path.get_file(), error_string(error)])
		else:
			written.append(path)
	return written


## Where [method export_sprites] saves the frames of [param coords] (every frame when
## empty) in [param folder], in order, as [code]{"coord": Vector2i, "path": String}[/code].
## A name that's taken, by a file in the folder or a frame before, is numbered, skipped or
## written over as the options say. Without [param on_disk] the folder is taken as empty.
static func get_sprite_paths(
	sheet: Spritesheet,
	folder: String,
	options: ExportOptions,
	coords: Array[Vector2i] = [],
	index_start := 0,
	on_disk := true,
) -> Array[Dictionary]:
	if coords.is_empty():
		coords = sheet.get_sorted_coords()
	var sprites: Array[Dictionary] = []
	# Lowercase, as Windows and macOS see "Walk.png" and "walk.png" as one file
	var used := {}
	var taken := func(path: String) -> bool:
		return used.has(path.to_lower()) or on_disk and FileAccess.file_exists(path)
	for coord in coords:
		var base := folder.path_join(
			format_sprite_name(options.sprite_name_pattern, sheet, coord, index_start)
		)
		var path := base + ".png"
		if taken.call(path):
			match options.existing_files:
				ExportOptions.Existing.SKIP:
					continue
				ExportOptions.Existing.ADD_NUMBER:
					path = unique_path(base, ".png", taken)
		used[path.to_lower()] = true
		sprites.append({"coord": coord, "path": path})
	return sprites


## Adds (1), (2)... before the extension while the path is [param taken]
static func unique_path(base: String, extension: String, taken: Callable) -> String:
	if not taken.call(base + extension):
		return base + extension
	var i := 1
	while taken.call("%s(%d)%s" % [base, i, extension]):
		i += 1
	return "%s(%d)%s" % [base, i, extension]


## A token: its name, and a width after a colon
static func _token_regex() -> RegEx:
	return RegEx.create_from_string("\\{(\\w+)(?::(\\d+))?\\}")
