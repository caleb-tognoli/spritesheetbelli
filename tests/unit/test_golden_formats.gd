extends "res://tests/test_case.gd"
## Exports representative sheets in every data format and compares the files byte for byte
## with the ones in tests/golden. After a deliberate change to a format, run the tests with
## the environment variable UPDATE_GOLDEN=1 to write them again, and check the difference.

const GOLDEN_DIR := "res://tests/golden"
## Formats of the data file next to a grid sheet's image
const GRID_TARGETS := {"json": ExportOptions.Target.JSON, "godot": ExportOptions.Target.GODOT}

var dir := temp_path("golden")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


## A frame with a block and a corner pixel of another colour, with transparent borders
static func sprite(size: Vector2i, block: Rect2i, color: Color, sprite_name: String) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill_rect(block, color)
	img.set_pixelv(block.position, Color.WHITE)
	img.resource_name = sprite_name
	return img


## A grid sheet of five frames with a gap, frames of different sizes and names that need
## escaping, and animations of every mode with durations and speeds of their own
static func grid_sheet(with_animations: bool) -> Spritesheet:
	var sheet := Spritesheet.new()
	var images: Array[Image] = [
		sprite(Vector2i(8, 8), Rect2i(1, 1, 6, 6), Color.RED, "idle"),
		sprite(Vector2i(10, 6), Rect2i(0, 0, 10, 6), Color.GREEN, "a&b"),
		sprite(Vector2i(6, 12), Rect2i(2, 2, 3, 9), Color.BLUE, "it's"),
		sprite(Vector2i(8, 8), Rect2i(0, 0, 8, 8), Color.YELLOW, "<up>"),
		sprite(Vector2i(4, 4), Rect2i(0, 0, 4, 4), Color.CYAN, "dot"),
	]
	sheet.set_grid_size(Vector2i(3, 2))
	sheet.add_frames(images)
	sheet.move_frame(Vector2i(1, 1), Vector2i(2, 1))
	if not with_animations:
		return sheet
	var coords := sheet.get_sorted_coords()
	var walk := SheetAnimation.create("walk", [coords[0], coords[1], coords[2]], 12)
	walk.durations = [1.0, 2.5, 1.0] as Array[float]
	sheet.add_animation(walk)
	var jump := SheetAnimation.create('jump & "fall"', [coords[3], coords[1]], 8)
	jump.mode = SheetAnimation.Mode.ONCE
	sheet.add_animation(jump)
	var bob := SheetAnimation.create("bob", [coords[0], coords[3], coords[4]], 10)
	bob.durations = [1.0, 1.0, 2.0] as Array[float]
	bob.mode = SheetAnimation.Mode.PING_PONG
	sheet.add_animation(bob)
	return sheet


## A sheet of long and small frames with transparent borders, a pivot of its own and
## animations, packed with [param settings]
static func atlas_sheet(settings: Dictionary) -> Spritesheet:
	var sheet := Spritesheet.new()
	var images: Array[Image] = []
	for i in 4:
		var color := Color.from_hsv(i / 6.0, 1, 1)
		images.append(sprite(Vector2i(64, 24), Rect2i(2, 2, 60, 20), color, "plank%d" % i))
	for i in 2:
		images.append(sprite(Vector2i(24, 64), Rect2i(2, 3, 20, 58), Color.BLUE, "post%d" % i))
	images.append(sprite(Vector2i(12, 9), Rect2i(3, 1, 5, 6), Color.WHITE, "a&b"))
	sheet.add_frames(images)
	var coords := sheet.get_sorted_coords()
	sheet.set_pivots([coords[6]] as Array[Vector2i], Vector2(4, 3))
	var roll := SheetAnimation.create("roll", [coords[0], coords[4], coords[6]], 12)
	roll.durations = [2.0, 1.0, 1.5] as Array[float]
	sheet.add_animation(roll)
	var spin := SheetAnimation.create("spin", [coords[5], coords[1]], 6)
	spin.mode = SheetAnimation.Mode.PING_PONG
	sheet.add_animation(spin)
	sheet.set_atlas_settings(AtlasSettings.from_dictionary(settings))
	sheet.set_layout(Spritesheet.Layout.PACKED)
	return sheet


## Writes the data files of every grid format for [param sheet] into [param case]
func export_grid(sheet: Spritesheet, case: String) -> PackedStringArray:
	var written := PackedStringArray()
	for format: String in GRID_TARGETS:
		var options := ExportOptions.new()
		options.target = GRID_TARGETS[format]
		options.sprite_name_pattern = "{name}"
		options.padding = 1
		options.spacing = 2
		options.extrude = 1
		var image := dir.path_join(case).path_join(format + ".png")
		DirAccess.make_dir_recursive_absolute(image.get_base_dir())
		assert_eq(Metadata.write_for_image(sheet, options, image), OK, format)
		written.append(Metadata.get_path_for_image(image, options))
	return written


## Writes the data files of every atlas format but those in [param skipped] for
## [param sheet] into [param case]
func export_atlas(
	sheet: Spritesheet, case: String, frame_size: ExportOptions.FrameSize, skipped := []
) -> PackedStringArray:
	var written := PackedStringArray()
	for format: String in AtlasFormats.FORMATS:
		if format in skipped:
			continue
		var options := ExportOptions.new()
		options.atlas_data = format
		options.atlas_frame_size = frame_size
		options.sprite_name_pattern = "{name}"
		var image := dir.path_join(case).path_join(format + ".png")
		DirAccess.make_dir_recursive_absolute(image.get_base_dir())
		var result := AtlasPacker.write(sheet, options, image)
		assert_eq(result.error, OK, "%s: %s" % [format, result.message])
		for path: String in result.paths:
			if not path.ends_with(".png"):
				written.append(path)
	return written


## Compares every file in [param paths] with its golden copy, or writes the copies
func check(paths: PackedStringArray) -> void:
	assert_false(paths.is_empty(), "files written")
	var update := OS.get_environment("UPDATE_GOLDEN") != ""
	for path: String in paths:
		var relative := path.trim_prefix(dir + "/")
		var golden := GOLDEN_DIR.path_join(relative)
		var text := _without_version(FileAccess.get_file_as_string(path))
		if update:
			var target := ProjectSettings.globalize_path(golden)
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var file := FileAccess.open(target, FileAccess.WRITE)
			file.store_string(text)
			file.close()
			continue
		assert_true(FileAccess.file_exists(golden), "golden file %s" % relative)
		var expected := FileAccess.get_file_as_string(golden)
		if text != expected:
			fail(
				(
					"%s differs from its golden file:\n%s"
					% [relative, _first_difference(text, expected)]
				)
			)


func test_grid_with_animations() -> void:
	check(export_grid(grid_sheet(true), "grid_animations"))


func test_grid_without_animations() -> void:
	check(export_grid(grid_sheet(false), "grid_plain"))


func test_atlas_turned_on_several_pages() -> void:
	var sheet := atlas_sheet(
		{"max_size": 64, "allow_rotation": true, "default_pivot": Vector2(0.5, 1)}
	)
	assert_true(PackedLayout.get_page_sizes(sheet).size() > 1, "several pages")
	assert_true(
		sheet.placements.values().any(func(place: Dictionary) -> bool: return place.rotated)
	)
	check(export_atlas(sheet, "atlas_turned", ExportOptions.FrameSize.FRAME, ["godot"]))


func test_atlas_on_several_pages() -> void:
	var sheet := atlas_sheet({"max_size": 64})
	assert_true(PackedLayout.get_page_sizes(sheet).size() > 1, "several pages")
	check(export_atlas(sheet, "atlas_pages", ExportOptions.FrameSize.CELL))


func test_atlas_on_one_page() -> void:
	var sheet := atlas_sheet({"max_size": 256})
	assert_eq(PackedLayout.get_page_sizes(sheet).size(), 1, "one page")
	check(export_atlas(sheet, "atlas_page", ExportOptions.FrameSize.FRAME))


## The version is left out, so the files don't change with every release
static func _without_version(text: String) -> String:
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	return text.replace('"version": "%s"' % version, '"version": "{version}"')


static func _first_difference(actual: String, expected: String) -> String:
	var got := actual.split("\n")
	var wanted := expected.split("\n")
	for i in maxi(got.size(), wanted.size()):
		var a := got[i] if i < got.size() else "<end>"
		var b := wanted[i] if i < wanted.size() else "<end>"
		if a != b:
			return "line %d: got %s, expected %s" % [i + 1, a.c_escape(), b.c_escape()]
	return "same lines"
