extends "res://tests/test_case.gd"
## The data files for Unity, Defold, Cocos2d-x and CSS: that they parse, and
## that engines reading them find each frame where it is, trimmed or turned

const Golden := preload("res://tests/unit/test_golden_formats.gd")

var dir := temp_path("engines")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


## Packs [param sheet] and writes it with [param format], each frame with its own size
func export_atlas(sheet: Spritesheet, format: String) -> Dictionary:
	var options := ExportOptions.new()
	options.atlas_data = format
	options.atlas_frame_size = ExportOptions.FrameSize.FRAME
	options.sprite_name_pattern = "{name}"
	var result := AtlasPacker.write(sheet, options, dir.path_join(format + ".png"))
	assert_eq(result.error, OK, "%s: %s" % [format, result.message])
	return result


## Writes the image and data file of a grid sheet with [param format]. Returns the data
## file's text.
func export_grid(sheet: Spritesheet, format: String, options := ExportOptions.new()) -> String:
	options.target = ExportOptions.Target.DATA
	options.grid_data = format
	options.sprite_name_pattern = "{name}"
	var image := dir.path_join(format + ".png")
	SpritesheetExporter.build_image(sheet, options).save_png(image)
	assert_eq(Metadata.write_for_image(sheet, options, image), OK)
	return FileAccess.get_file_as_string(Metadata.get_path_for_image(image, options))


## The frame of [param sheet] named [param frame_name]
static func coord_named(sheet: Spritesheet, frame_name: String) -> Vector2i:
	for coord in sheet.frames:
		if sheet.frames[coord].resource_name == frame_name:
			return coord
	return -Vector2i.ONE


## The pixels of a packed frame without its transparent borders
static func trimmed_pixels(sheet: Spritesheet, coord: Vector2i) -> Image:
	return sheet.frames[coord].get_region(sheet.placements[coord].src)


## The sprites of a .tpsheet by name: [code][x, y, w, h, pivot_x, pivot_y][/code], and
## its ":key=value" lines under "header"
static func parse_tpsheet(text: String) -> Dictionary:
	var result := {"header": {}}
	for line in text.split("\n", false):
		if line.begins_with("#"):
			continue
		if line.begins_with(":"):
			result.header[line.get_slice("=", 0)] = line.get_slice("=", 1)
			continue
		var parts := line.split(";")
		var numbers := Array(parts.slice(1, 7)).map(func(part: String) -> float: return float(part))
		result[parts[0]] = numbers
	return result


func test_unity_tpsheet() -> void:
	var sheet := Golden.atlas_sheet({"max_size": 256})
	var result := export_atlas(sheet, "unity")
	var page := Image.load_from_file(result.path)
	var data := parse_tpsheet(FileAccess.get_file_as_string(result.json_path))
	assert_eq(data.header[":format"], "40300")
	assert_eq(data.header[":texture"], "unity.png")
	assert_eq(data.header[":size"], "%dx%d" % [page.get_width(), page.get_height()])
	assert_eq(data.size(), 1 + sheet.frames.size(), "every frame")
	for coord: Vector2i in sheet.frames:
		var frame_name: String = sheet.frames[coord].resource_name
		var sprite: Array = Array(data[frame_name]).map(
			func(number: float) -> int: return int(number)
		)
		# Unity measures y up from the bottom of the page
		var rect := Rect2i(
			sprite[0], page.get_height() - sprite[1] - sprite[3], sprite[2], sprite[3]
		)
		var pixels := trimmed_pixels(sheet, coord).get_data()
		assert_eq(page.get_region(rect).get_data(), pixels, frame_name)
	# A trimmed frame's pivot is across its packed pixels, from their bottom left: the
	# pivot at (4, 3) of the 12×9 frame is 1 px right of the 5×6 pixels' left edge, which
	# start 3 px in, and 4 px above their bottom edge, 2 px up from the frame's
	var trimmed: Array = data["a&b"]
	assert_eq(trimmed.slice(2, 4), [5.0, 6.0])
	assert_true(is_equal_approx(trimmed[4], 0.2), str(trimmed))
	assert_true(is_equal_approx(trimmed[5], 0.666667), str(trimmed))
	assert_eq(data["plank0"].slice(4), [0.5, 0.5], "the default pivot, in the middle")


func test_unity_names_and_turned_frames() -> void:
	var sheet := Spritesheet.new()
	var img := make_image(Color.RED, Vector2i(8, 4))
	img.resource_name = "#1;a"
	sheet.add_frames([img] as Array[Image])
	var text := export_grid(sheet, "unity")
	# A name starting with # would be a comment, and ; ends a value
	assert_true("\n%231%3Ba;0;0;8;4; 0.5;0.5; 0;0;0;0\n" in text, text)
	# Unity sprites can't be stored turned
	var turned := Golden.atlas_sheet({"max_size": 64, "allow_rotation": true})
	var options := ExportOptions.new()
	options.atlas_data = "unity"
	var result := AtlasPacker.write(turned, options, dir.path_join("turned.png"))
	assert_eq(result.error, ERR_UNAVAILABLE)


## A property list as dictionaries, arrays, texts, numbers and booleans
static func parse_plist(text: String) -> Variant:
	var parser := XMLParser.new()
	parser.open_buffer(text.to_utf8_buffer())
	var tag := _next_tag(parser)
	while tag and tag != "plist":
		tag = _next_tag(parser)
	return _plist_value(parser, _next_tag(parser))


static func _next_tag(parser: XMLParser) -> String:
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			return parser.get_node_name()
		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			return "/" + parser.get_node_name()
	return ""


static func _plist_value(parser: XMLParser, tag: String) -> Variant:
	if tag in ["true", "false"]:
		return tag == "true"
	if tag == "array" or tag == "dict":
		var items := []
		var next := "" if parser.is_empty() else _next_tag(parser)
		while next and not next.begins_with("/"):
			items.append(_plist_value(parser, next))
			next = _next_tag(parser)
		if tag == "array":
			return items
		var dict := {}
		for i in range(0, items.size(), 2):
			dict[items[i]] = items[i + 1]
		return dict
	var text := ""
	while not parser.is_empty() and parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			break
		if parser.get_node_type() == XMLParser.NODE_TEXT:
			text += parser.get_node_data()
	if tag == "integer":
		return int(text)
	return text.xml_unescape()


## The numbers in "{{x,y},{w,h}}"
static func plist_numbers(text: String) -> Array:
	return floats(Array(text.replace("{", "").replace("}", "").split(",")))


## [param values] as decimal numbers, to compare with numbers read from text
static func floats(values: Array) -> Array:
	return values.map(func(value: Variant) -> float: return float(value))


func test_cocos2d_plist() -> void:
	var sheet := Golden.atlas_sheet(
		{"max_size": 64, "allow_rotation": true, "default_pivot": Vector2(0.5, 1)}
	)
	var result := export_atlas(sheet, "cocos2d")
	var plists := Array(result.paths).filter(
		func(path: String) -> bool: return path.ends_with(".plist")
	)
	assert_eq(plists.size(), result.pages, "a file for each page")
	var turned := 0
	for path: String in plists:
		var plist: Dictionary = parse_plist(FileAccess.get_file_as_string(path))
		var page := Image.load_from_file(path.get_basename() + ".png")
		var metadata: Dictionary = plist.metadata
		assert_eq(metadata.format, 3)
		assert_eq(metadata.textureFileName, path.get_basename().get_file() + ".png")
		assert_eq(plist_numbers(metadata.size), floats([page.get_width(), page.get_height()]))
		for file_name: String in plist.frames:
			var frame: Dictionary = plist.frames[file_name]
			var coord := coord_named(sheet, file_name.get_basename())
			var src: Rect2i = sheet.placements[coord].src
			var source_size: Vector2i = sheet.frames[coord].get_size()
			var rect := plist_numbers(frame.textureRect)
			var size := plist_numbers(frame.spriteSize)
			assert_eq(rect.slice(2), size, "the size before turning")
			assert_eq(size, floats([src.size.x, src.size.y]))
			assert_eq(plist_numbers(frame.spriteSourceSize), floats([source_size.x, source_size.y]))
			# Cocos2d turns frames stored turned clockwise back counter-clockwise
			var stored_size := (
				Vector2i(size[1], size[0]) if frame.textureRotated else Vector2i(size[0], size[1])
			)
			var stored := page.get_region(Rect2i(Vector2i(rect[0], rect[1]), stored_size))
			if frame.textureRotated:
				stored.rotate_90(COUNTERCLOCKWISE)
				turned += 1
			assert_eq(stored.get_data(), trimmed_pixels(sheet, coord).get_data(), file_name)
			# How far the packed pixels' middle is from the frame's, right and up
			var middle := Vector2(src.position) + Vector2(src.size) / 2 - Vector2(source_size) / 2
			assert_eq(plist_numbers(frame.spriteOffset), [middle.x, -middle.y], file_name)
			assert_eq(frame.aliases, [])
			var pivot := plist_numbers(frame.anchor)
			if file_name == "a&b.png":
				assert_true(pivot[0] == 0.333333 and pivot[1] == 0.666667, str(pivot))
			else:
				assert_eq(pivot, [0.5, 0.0], "the middle of the bottom, measured up")
	assert_true(turned > 0, "some are turned")


func test_cocos2d_trimmed_offsets() -> void:
	var sheet := Golden.atlas_sheet({"max_size": 256})
	var plist: Dictionary = parse_plist(
		FileAccess.get_file_as_string(export_atlas(sheet, "cocos2d").json_path)
	)
	# 3 px transparent on the left, 4 on the right, 1 at the top and 2 at the bottom
	assert_eq(plist.frames["a&b.png"].spriteOffset, "{-0.5,0.5}")
	assert_eq(plist.frames["post0.png"].spriteOffset, "{0,0}")


## The top-level "key: value" lines of a Defold file, and its "animations { }" blocks
static func parse_defold(text: String) -> Dictionary:
	var result := {"animations": []}
	var block: Variant = null
	for line in text.split("\n", false):
		line = line.strip_edges()
		if line == "animations {":
			block = {}
		elif line == "}":
			result.animations.append(block)
			block = null
		else:
			var value := line.get_slice(": ", 1)
			value = value.trim_prefix('"').trim_suffix('"') if value.begins_with('"') else value
			(block if block != null else result)[line.get_slice(": ", 0)] = value
	return result


## Where Defold finds tile [param index] (from 0), as TileSetUtil does
static func defold_tile(data: Dictionary, image_size: Vector2i, index: int) -> Rect2i:
	var size := Vector2i(int(data.tile_width), int(data.tile_height))
	var margin := int(data.tile_margin)
	var spacing := int(data.tile_spacing)
	var per_row := (image_size.x + spacing) / (2 * margin + spacing + size.x)
	var cell := Vector2i(index % per_row, index / per_row)
	return Rect2i(
		Vector2i.ONE * margin + cell * (Vector2i.ONE * (2 * margin + spacing) + size), size
	)


func test_defold_tile_source() -> void:
	var sheet := Golden.grid_sheet(true)
	for spacing: Vector3i in [Vector3i(0, 0, 0), Vector3i(1, 2, 1), Vector3i(2, 4, 0)]:
		var options := ExportOptions.new()
		options.padding = spacing.x
		options.spacing = spacing.y
		options.extrude = spacing.z
		var data := parse_defold(export_grid(sheet, "defold", options))
		var image_size := SpritesheetExporter.get_image_size(sheet, options)
		assert_eq(data.image, "defold.png")
		var spacing_x := int(data.tile_spacing)
		var step := 2 * int(data.tile_margin) + spacing_x + int(data.tile_width)
		assert_eq((image_size.x + spacing_x) / step, sheet.grid_size.x, "columns, %s" % spacing)
		# Tiles are numbered in reading order, empty cells too
		for coord: Vector2i in sheet.frames:
			var index := coord.y * sheet.grid_size.x + coord.x
			var expected := SpritesheetExporter.get_cell_rect(sheet, coord, options)
			assert_eq(defold_tile(data, image_size, index), expected, "%s %s" % [coord, spacing])
	var animations: Array = parse_defold(export_grid(sheet, "defold")).animations
	assert_eq(animations.size(), 3)
	var walk: Dictionary = animations[0]
	assert_eq([walk.id, walk.start_tile, walk.end_tile], ["walk", "1", "3"])
	assert_eq([walk.playback, walk.fps], ["PLAYBACK_LOOP_FORWARD", "12"])
	# Its last frame comes first, and the frame between is played too
	var jump: Dictionary = animations[1]
	assert_eq([jump.id, jump.start_tile, jump.end_tile], ['jump & \\"fall\\"', "2", "4"])
	assert_eq([jump.playback, jump.fps], ["PLAYBACK_ONCE_BACKWARD", "8"])
	# Up to the frame after the empty cell, tile 6
	var bob: Dictionary = animations[2]
	assert_eq([bob.start_tile, bob.end_tile, bob.playback], ["1", "6", "PLAYBACK_LOOP_PINGPONG"])
	assert_eq(parse_defold(export_grid(Golden.grid_sheet(false), "defold")).animations, [])


## The rules of a CSS file by selector: the text between the braces
static func css_rules(text: String) -> Dictionary:
	var rules := {}
	var regex := RegEx.create_from_string("(?s)([^{}]+)\\{([^{}]*)\\}")
	for found in regex.search_all(text.get_slice("*/", 1)):
		rules[found.get_string(1).strip_edges()] = found.get_string(2).strip_edges()
	return rules


func test_css_sprites() -> void:
	var sheet := Golden.atlas_sheet({"max_size": 64})
	var result := export_atlas(sheet, "css")
	assert_eq(result.pages, 3)
	var rules := css_rules(FileAccess.get_file_as_string(result.json_path))
	assert_true('background-image: url("css_0.png");' in rules[".sprite"], rules[".sprite"])
	var trimmed: String = rules[".sprite-a\\&b"]
	var coord := coord_named(sheet, "a&b")
	var position := PackedLayout.get_rect(sheet, coord).position
	assert_true("width: 5px;\n\theight: 6px;" in trimmed, trimmed)
	assert_true("background-position: %dpx %dpx;" % [-position.x, -position.y] in trimmed, trimmed)
	# Margins give it the room of the whole frame: top, right, bottom, left
	assert_true("margin: 1px 4px 2px 3px;" in trimmed, trimmed)
	# Frames on the other pages get their own page's image
	for page in range(1, result.pages):
		var names := []
		for other in sheet.frames:
			if sheet.placements[other].page == page:
				names.append(".sprite-" + sheet.frames[other].resource_name.replace("&", "\\&"))
		var selector := ",\n".join(names)
		assert_true(rules.has(selector), "%s in %s" % [selector, rules.keys()])
		assert_eq(rules[selector], 'background-image: url("css_%d.png");' % page)
	assert_false("@media" in FileAccess.get_file_as_string(result.json_path), "no @2x yet")
	# CSS can't show turned frames
	var options := ExportOptions.new()
	options.atlas_data = "css"
	var turned := Golden.atlas_sheet({"max_size": 64, "allow_rotation": true})
	assert_eq(AtlasPacker.write(turned, options, dir.path_join("t.png")).error, ERR_UNAVAILABLE)


func test_css_sprites_of_a_grid() -> void:
	var rules := css_rules(export_grid(Golden.grid_sheet(false), "css"))
	assert_eq(
		rules[".sprite-it\\'s"], "width: 10px;\n\theight: 12px;\n\tbackground-position: -20px 0px;"
	)
	assert_eq(rules.size(), 6, "the shared class and one for every frame")


func test_scss_sprites() -> void:
	var sheet := Golden.atlas_sheet({"max_size": 256})
	var text := FileAccess.get_file_as_string(export_atlas(sheet, "scss").json_path)
	var entry := (
		'\t"a&b": (\n\t\timage: "scss.png",\n\t\tx: 80px,\n\t\ty: 0px,\n\t\twidth: 5px,\n'
		+ "\t\theight: 6px,\n\t\tmargin: 1px 4px 2px 3px,\n\t),\n"
	)
	assert_true(entry in text, text)
	assert_true('\t"scss.png": (\n\t\tsize: 85px 80px,\n\t),\n' in text, text)
	assert_true('\t.sprite-a\\&b {\n\t\t@include sprite("a&b");\n\t}\n' in text, text)
	assert_eq(text.count("{"), text.count("}"), "balanced")
