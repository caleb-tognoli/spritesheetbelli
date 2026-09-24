class_name ProjectFile
## Saves and loads .sbelli projects: a zip holding project.json and frames.png, where every
## frame is stored at its original size, so a spritesheet can be reopened exactly as it was.
## (One image instead of one file per frame keeps large projects fast to open.)

const EXTENSION := "sbelli"
const FORMAT := "spritesheetbelli"
const VERSION := 1
const JSON_FILE := "project.json"
const FRAMES_FILE := "frames.png"


static func is_project_path(path: String) -> bool:
	return path.get_extension().to_lower() == EXTENSION


static func with_extension(path: String) -> String:
	return path if is_project_path(path) else path.get_basename() + "." + EXTENSION


## Saves [param sheet] and any [param extra] data (such as export settings) to [param path]
static func save(sheet: Spritesheet, path: String, extra := {}) -> Error:
	var zip := ZIPPacker.new()
	var error := zip.open(path)
	if error != OK:
		return error

	var coords := sheet.get_sorted_coords()
	var sizes: Array[Vector2i] = []
	for coord in coords:
		sizes.append(sheet.frames[coord].get_size())
	var layout := _shelf_layout(sizes)
	var frames: Array[Dictionary] = []
	if not coords.is_empty():
		var atlas := Image.create_empty(layout.size.x, layout.size.y, false, Image.FORMAT_RGBA8)
		for i in coords.size():
			var img: Image = sheet.frames[coords[i]]
			var position: Vector2i = layout.positions[i]
			atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), position)
			(
				frames
				. append(
					{
						"cell": [coords[i].x, coords[i].y],
						"rect": [position.x, position.y, img.get_width(), img.get_height()],
						"name": img.resource_name,
					}
				)
			)
		error = _write(zip, FRAMES_FILE, atlas.save_png_to_buffer())
		if error != OK:
			zip.close()
			return error

	var row_names := {}
	for row in sheet.row_names:
		row_names[str(row)] = sheet.row_names[row]
	var locked: Array[Array] = []
	for coord in sheet.locked_coordinates:
		locked.append([coord.x, coord.y])
	var animations: Array[Dictionary] = []
	for animation in sheet.animations:
		var saved := animation.to_dictionary()
		saved.cells = animation.cells.map(func(cell: Vector2i) -> Array: return [cell.x, cell.y])
		animations.append(saved)

	var data := {
		"format": FORMAT,
		"version": VERSION,
		"grid_size": [sheet.grid_size.x, sheet.grid_size.y],
		"frame_scale": [sheet.frame_scale.x, sheet.frame_scale.y],
		"scale_filter": sheet.scale_filter,
		"locked": locked,
		"row_names": row_names,
		"animations": animations,
		"export": JSON.from_native(sheet.export_settings),
		"frames": frames,
		"extra": extra,
	}
	error = _write(zip, JSON_FILE, JSON.stringify(data, "\t").to_utf8_buffer())
	zip.close()
	return error


## Loads a project. Returns [code]{"state": Dictionary, "extra": Dictionary}[/code] for
## [method Spritesheet.set_state], or [code]{"error": String}[/code].
static func load(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {"error": TranslationServer.translate("Could not open %s.") % path.get_file()}
	var result := _read(zip)
	zip.close()
	return result


static func _read(zip: ZIPReader) -> Dictionary:
	if not zip.file_exists(JSON_FILE):
		return {"error": "Not a spritesheetbelli project."}
	var data: Variant = JSON.parse_string(zip.read_file(JSON_FILE).get_string_from_utf8())
	if not data is Dictionary or data.get("format") != FORMAT:
		return {"error": "Not a spritesheetbelli project."}
	if int(data.get("version", 0)) > VERSION:
		return {"error": "This project was made with a newer version of spritesheetbelli."}

	var atlas := Image.new()
	if zip.file_exists(FRAMES_FILE):
		if atlas.load_png_from_buffer(zip.read_file(FRAMES_FILE)) != OK:
			return {"error": TranslationServer.translate("The frames image is damaged.")}
		atlas.convert(Image.FORMAT_RGBA8)
	var frames: Dictionary[Vector2i, Image] = {}
	for frame: Dictionary in data.get("frames", []):
		var img := _read_frame(zip, atlas, frame)
		if img == null:
			return {
				"error":
				(
					TranslationServer.translate("A frame image is missing or damaged (%s).")
					% frame.get("file")
				)
			}
		img.resource_name = frame.get("name", "")
		frames[_to_vector2i(frame.get("cell"))] = img

	var locked: Array[Vector2i] = []
	for coord: Array in data.get("locked", []):
		locked.append(_to_vector2i(coord))
	var row_names: Dictionary[int, String] = {}
	for row: String in data.get("row_names", {}):
		row_names[int(row)] = data.row_names[row]
	var frame_scale: Array = data.get("frame_scale", [1, 1])
	var animations: Array[Dictionary] = []
	for animation: Variant in data.get("animations", []):
		if animation is Dictionary:
			animations.append(SheetAnimation.from_dictionary(animation).to_dictionary())

	var state := {
		"grid_size": _to_vector2i(data.get("grid_size", [0, 0])),
		"frames": frames,
		"locked": locked,
		"scale": Vector2(frame_scale[0], frame_scale[1]),
		"scale_filter": int(data.get("scale_filter", Image.INTERPOLATE_NEAREST)),
		"row_names": row_names,
		"animations": animations,
		"export": _read_export_settings(data.get("export", {})),
	}
	return {"state": state, "extra": data.get("extra", {})}


## A frame from its rectangle in frames.png, or from its own PNG in older projects
static func _read_frame(zip: ZIPReader, atlas: Image, frame: Dictionary) -> Image:
	var rect: Variant = frame.get("rect")
	if rect is Array and rect.size() == 4 and not atlas.is_empty():
		var region := Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
		if Rect2i(Vector2i.ZERO, atlas.get_size()).encloses(region) and region.has_area():
			return atlas.get_region(region)
		return null
	var file: String = frame.get("file", "")
	var img := Image.new()
	if file.is_empty() or img.load_png_from_buffer(zip.read_file(file)) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## Places frames in rows of a roughly square image. Returns
## [code]{"size": Vector2i, "positions": Array[Vector2i]}[/code].
static func _shelf_layout(sizes: Array[Vector2i]) -> Dictionary:
	var area := 0
	var widest := 1
	for size in sizes:
		area += size.x * size.y
		widest = maxi(widest, size.x)
	var width := maxi(widest, ceili(sqrt(area)))
	var positions: Array[Vector2i] = []
	var cursor := Vector2i.ZERO
	var row_height := 0
	var used := Vector2i.ONE
	for size in sizes:
		if cursor.x + size.x > width:
			cursor = Vector2i(0, cursor.y + row_height)
			row_height = 0
		positions.append(cursor)
		used = used.max(cursor + size)
		cursor.x += size.x
		row_height = maxi(row_height, size.y)
	return {"size": used, "positions": positions}


static func _read_export_settings(value: Variant) -> Dictionary:
	var settings: Variant = JSON.to_native(value)
	return settings if settings is Dictionary else {}


static func _write(zip: ZIPPacker, file: String, bytes: PackedByteArray) -> Error:
	var error := zip.start_file(file)
	if error == OK:
		error = zip.write_file(bytes)
		zip.close_file()
	return error


static func _to_vector2i(value: Variant) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
