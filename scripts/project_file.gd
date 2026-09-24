class_name ProjectFile
## Saves and loads .sbelli projects: a zip holding project.json and one PNG per frame,
## so a spritesheet can be reopened exactly as it was.

const EXTENSION := "sbelli"
const FORMAT := "spritesheetbelli"
const VERSION := 1
const JSON_FILE := "project.json"


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

	var frames: Array[Dictionary] = []
	for coord in sheet.get_sorted_coords():
		var file := "frames/%d_%d.png" % [coord.x, coord.y]
		frames.append(
			{"cell": [coord.x, coord.y], "file": file, "name": sheet.frames[coord].resource_name}
		)
		error = _write(zip, file, sheet.frames[coord].save_png_to_buffer())
		if error != OK:
			zip.close()
			return error

	var row_names := {}
	for row in sheet.row_names:
		row_names[str(row)] = sheet.row_names[row]
	var locked: Array[Array] = []
	for coord in sheet.locked_coordinates:
		locked.append([coord.x, coord.y])

	var data := {
		"format": FORMAT,
		"version": VERSION,
		"grid_size": [sheet.grid_size.x, sheet.grid_size.y],
		"frame_scale": [sheet.frame_scale.x, sheet.frame_scale.y],
		"scale_filter": sheet.scale_filter,
		"locked": locked,
		"row_names": row_names,
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

	var frames: Dictionary[Vector2i, Image] = {}
	for frame: Dictionary in data.get("frames", []):
		var img := Image.new()
		if img.load_png_from_buffer(zip.read_file(frame.get("file", ""))) != OK:
			return {
				"error":
				(
					TranslationServer.translate("A frame image is missing or damaged (%s).")
					% frame.get("file")
				)
			}
		img.convert(Image.FORMAT_RGBA8)
		img.resource_name = frame.get("name", "")
		frames[_to_vector2i(frame.get("cell"))] = img

	var locked: Array[Vector2i] = []
	for coord: Array in data.get("locked", []):
		locked.append(_to_vector2i(coord))
	var row_names: Dictionary[int, String] = {}
	for row: String in data.get("row_names", {}):
		row_names[int(row)] = data.row_names[row]
	var frame_scale: Array = data.get("frame_scale", [1, 1])

	var state := {
		"grid_size": _to_vector2i(data.get("grid_size", [0, 0])),
		"frames": frames,
		"locked": locked,
		"scale": Vector2(frame_scale[0], frame_scale[1]),
		"scale_filter": int(data.get("scale_filter", Image.INTERPOLATE_NEAREST)),
		"row_names": row_names,
		"export": _read_export_settings(data.get("export", {})),
	}
	return {"state": state, "extra": data.get("extra", {})}


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
