class_name FrameSource
## Where a frame came from, so it can be cut again when its file changes, and the edits
## made to it since, so they can be made again on the new pixels.
##
## A source is a plain dictionary, never changed once made (like frame images), so
## spritesheet snapshots can share it:
## [codeblock]
## {
##     "path": String,         # the image file
##     "rect": [x, y, w, h],   # where the frame is in a spritesheet (optional)
##     "keyed": true,          # the sheet's background colour was removed (optional)
##     "gif_frame": int,       # which frame of a GIF (optional)
##     "data": String,         # the data file that says where the frame is (optional)
##     "name": String,         # the frame's name in that data file
##     "origin": [x, y],       # where the frame was placed when added (optional)
##     "ops": Array,           # edits made since, see FrameEdits
## }
## [/codeblock]


## The whole image at [param path]
static func for_file(path: String) -> Dictionary:
	return {"path": path}


## The part of the image at [param path] inside [param rect]. With [param keyed], the
## image's background colour is removed first, see [method SpriteDetector.without_background].
static func for_region(path: String, rect: Rect2i, keyed := false) -> Dictionary:
	var source := {
		"path": path, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	}
	if keyed:
		source.keyed = true
	return source


## Frame [param index] of the GIF at [param path]
static func for_gif(path: String, index: int) -> Dictionary:
	return {"path": path, "gif_frame": index}


## The frame named [param frame_name] in the data file at [param data_path], cut from
## the image at [param path]
static func for_data(path: String, data_path: String, frame_name: String) -> Dictionary:
	return {"path": path, "data": data_path, "name": frame_name}


## [param source] placed at [param origin] when added (null when centred)
static func with_origin(source: Dictionary, origin: Variant) -> Dictionary:
	var result := source.duplicate(true)
	result.erase("origin")
	if origin is Vector2i:
		result.origin = [origin.x, origin.y]
	return result


## [param source] with [param op] made after its other edits
static func with_op(source: Dictionary, op: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var ops: Array = result.get("ops", [])
	ops.append(op.duplicate(true))
	result.ops = ops
	return result


## [param source] without the edits made since the frame was added
static func without_edits(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.erase("ops")
	return result


static func has_edits(source: Dictionary) -> bool:
	return not source.get("ops", []).is_empty()


## The files the frame is cut from: the image, and the data file when there is one
static func get_paths(source: Dictionary) -> PackedStringArray:
	var paths: PackedStringArray = []
	if source.get("path"):
		paths.append(source.path)
	if source.get("data"):
		paths.append(source.data)
	return paths


## Where the frame at [param coord] is placed in its cell, or null when it's centred.
## See [method Spritesheet.get_frame_origin].
static func get_origin(sheet: Spritesheet, coord: Vector2i) -> Variant:
	if sheet.has_frame_origin(coord):
		return sheet.get_frame_origin(coord)
	return null


## Every file linked frames of [param sheet] came from
static func get_sheet_paths(sheet: Spritesheet) -> PackedStringArray:
	var paths: PackedStringArray = []
	for source: Dictionary in sheet.frame_sources.values():
		for path in get_paths(source):
			if path not in paths:
				paths.append(path)
	return paths


## The frames of [param sheet] linked to [param path], in reading order
static func get_linked(sheet: Spritesheet, path: String) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in sheet.get_sorted_coords():
		if sheet.frame_sources.has(coord) and path in get_paths(sheet.frame_sources[coord]):
			coords.append(coord)
	return coords


## Forgets that frames of [param sheet] came from [param path]. Returns how many there were.
static func unlink(sheet: Spritesheet, path: String) -> int:
	var coords := get_linked(sheet, path)
	sheet.batch(
		func() -> void:
			for coord in coords:
				sheet.set_frame(coord, sheet.frames[coord], {}, get_origin(sheet, coord))
	)
	return coords.size()


#region Cutting


## What has to be read from disk to cut the frame. Frames that share a key share the
## loaded file, see [method load_key].
static func get_load_key(source: Dictionary) -> String:
	if source.has("data"):
		return "data:%s|%s" % [source.data, source.path]
	if source.has("gif_frame"):
		return "gif:" + str(source.path)
	if source.get("keyed"):
		return "keyed:" + str(source.path)
	return "image:" + str(source.path)


## Reads the files behind a key from [method get_load_key]: an image, the frames of a
## GIF, or a data file with its image. Null when they can't be read.
static func load_key(key: String) -> Variant:
	var kind := key.get_slice(":", 0)
	var path := key.trim_prefix(kind + ":")
	match kind:
		"gif":
			var gif := GifDecoder.load_file(path)
			return null if gif.has("error") else gif.frames
		"data":
			var data := SheetData.load_file(path.get_slice("|", 0))
			var img := Image.load_from_file(path.get_slice("|", 1))
			if data.error or img == null:
				return null
			return {"data": data, "image": img}
		"keyed":
			var img := Image.load_from_file(path)
			return SpriteDetector.without_background(img) if img else null
		_:
			return Image.load_from_file(path)


## Cuts the frame again from files read with [method load_key], by key in [param loaded].
## Null when the frame isn't there anymore, e.g. its rectangle is outside a smaller image.
static func cut(source: Dictionary, loaded: Dictionary) -> Image:
	var file: Variant = loaded.get(get_load_key(source))
	if file == null:
		return null
	var img: Image = null
	if source.has("data"):
		img = (file.data as SheetData).cut_named(file.image, str(source.name))
	elif source.has("gif_frame"):
		var index := int(source.gif_frame)
		img = file[index].duplicate() if index < file.size() else null
	elif source.has("rect"):
		var r: Array = source.rect
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var image: Image = file
		if Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect):
			img = image.get_region(rect)
	else:
		img = (file as Image).duplicate()
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## The frame made from freshly cut [param pixels]: placed where it was when added and,
## with [param keep_edits], with the edits in [param source] made again, the same way they
## were made the first time. Returns [code]{"image": Image, "origin": Vector2i or null}[/code].
static func rebuild(source: Dictionary, pixels: Image, keep_edits: bool) -> Dictionary:
	var sheet := Spritesheet.new()
	var cell := [Vector2i.ZERO] as Array[Vector2i]
	var origin: Variant = source.get("origin")
	if origin is Array and origin.size() >= 2:
		origin = Vector2i(int(origin[0]), int(origin[1]))
	sheet.set_frame(Vector2i.ZERO, pixels, {}, origin if origin is Vector2i else null)
	if keep_edits:
		for op: Variant in source.get("ops", []):
			if op is Dictionary:
				FrameEdits.apply(sheet, cell, op)
	return {"image": sheet.frames[Vector2i.ZERO], "origin": get_origin(sheet, Vector2i.ZERO)}


#endregion

#region Saving


## [param source] for a project saved in [param folder]: paths are also stored relative
## to it, so a project moved with its images still finds them
static func to_json(source: Dictionary, folder: String) -> Dictionary:
	var result := source.duplicate(true)
	for key: String in ["path", "data"]:
		if result.has(key):
			result[key + "_relative"] = relative_path(result[key], folder)
	return result


## A source read from a project saved in [param folder], or an empty dictionary
static func from_json(value: Variant, folder: String) -> Dictionary:
	if not value is Dictionary or not value.get("path") is String:
		return {}
	var result: Dictionary = value.duplicate(true)
	for key: String in ["path", "data"]:
		var relative: Variant = result.get(key + "_relative")
		result.erase(key + "_relative")
		result[key] = resolve_path(str(result.get(key, "")), relative, folder)
		if not result[key]:
			result.erase(key)
	if result.has("gif_frame"):
		result.gif_frame = int(result.gif_frame)
	if not result.get("ops") is Array:
		result.erase("ops")
	return result


## The file at [param relative] from [param folder] when it's there, else [param path]
static func resolve_path(path: String, relative: Variant, folder: String) -> String:
	if relative is String and relative and folder:
		var moved := folder.path_join(relative).simplify_path()
		if FileAccess.file_exists(moved):
			return moved
	return path


## [param path] relative to [param folder], like [code]../art/walk.png[/code]
static func relative_path(path: String, folder: String) -> String:
	if folder.is_empty():
		return path
	var parts := path.simplify_path().split("/")
	var base := folder.simplify_path().split("/")
	var same := 0
	while same < mini(parts.size() - 1, base.size()) and parts[same] == base[same]:
		same += 1
	# On another drive
	if same == 0:
		return path
	var result: PackedStringArray = []
	for i in base.size() - same:
		result.append("..")
	result.append_array(parts.slice(same))
	return "/".join(result)

#endregion
