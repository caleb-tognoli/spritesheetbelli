extends "res://tests/test_case.gd"
## Lines between pixels when zoomed in, and the pixel under the mouse in the status bar

var document: Document
var sheet: Spritesheet
var canvas: SpritesheetPreview
## The main scene, for the tests that need it, see [method open_main]
var main: Control


func before_each() -> void:
	document = Document.new()
	sheet = document.spritesheet
	canvas = SpritesheetPreview.new()
	canvas.spritesheet = sheet


func after_each() -> void:
	canvas.free()
	if main:
		main.queue_free()
		Global.document.reset()


## A frame whose every pixel has a colour of its own
static func gradient(size: Vector2i) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			img.set_pixel(x, y, Color8(x * 20, y * 20, 90, 255 - x - y))
	return img


## A frame of [param size] with a gradient in [param block] and transparency around
static func sprite(size: Vector2i, block: Rect2i) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.blit_rect(gradient(block.size), Rect2i(Vector2i.ZERO, block.size), block.position)
	return img


## Every pixel of every frame reads as the exported image there, at the pixel of the
## export it's on, and with Nearest, the frame's own pixel read has that colour too
func assert_matches_export() -> void:
	var images: Array[Image] = []
	var origins: Array[Vector2] = [Vector2.ZERO]
	if sheet.layout == Spritesheet.Layout.PACKED:
		images = PackedLayout.render_pages(sheet)
		origins = canvas.packed_view.page_origins
	else:
		images.append(sheet.get_image(ExportOptions.from_sheet(sheet)))
	for coord in sheet.frames:
		var rect: Rect2i = PixelGrid.get_frame_view(canvas, coord).rect
		for y in rect.size.y:
			for x in rect.size.x:
				var pixel := rect.position + Vector2i(x, y)
				var info := PixelGrid.probe(canvas, coord, pixel)
				var page: int = maxi(info.page, 0)
				var at := "frame %s at %s" % [coord, pixel]
				var expected := images[page].get_pixelv(pixel - Vector2i(origins[page]))
				if info.sheet != pixel - Vector2i(origins[page]) or info.color != expected:
					fail("%s: %s, expected %s" % [at, info, expected])
					return
				var own := sheet.frames[coord].get_pixelv(info.frame)
				if sheet.scale_filter == Image.INTERPOLATE_NEAREST and own != expected:
					fail("%s: the frame's pixel %s is %s" % [at, info.frame, own])
					return


func test_the_pixel_grid_shows_from_600_percent() -> void:
	assert_false(PixelGrid.is_shown(true, 5.5))
	assert_true(PixelGrid.is_shown(true, 6))
	assert_true(PixelGrid.is_shown(true, 32))
	assert_false(PixelGrid.is_shown(false, 32), "turned off")


func test_plain_frames_map_to_their_pixels() -> void:
	sheet.add_frames([gradient(Vector2i(6, 4)), gradient(Vector2i(4, 2))] as Array[Image])
	sheet.set_export_settings({"padding": 3, "spacing": 2})
	# Cells are 6×4 after 3 pixels of padding, 2 apart: the second frame is centred in
	# the cell at 11, 3
	var info := PixelGrid.probe(canvas, Vector2i(1, 0), Vector2i(14, 5))
	assert_eq(info.sheet, Vector2i(14, 5))
	assert_eq(info.frame, Vector2i(2, 1))
	assert_eq(info.color, gradient(Vector2i(4, 2)).get_pixel(2, 1))
	assert_eq(info.page, -1)
	info = PixelGrid.probe(canvas, Vector2i(1, 0), Vector2i(11, 3))
	assert_false(info.has("frame"), "beside the frame, in its cell")
	assert_eq(info.sheet, Vector2i(11, 3))
	assert_matches_export()


func test_scaled_frames_map_to_their_own_pixels() -> void:
	sheet.add_frames([gradient(Vector2i(4, 3)), gradient(Vector2i(2, 2))] as Array[Image])
	sheet.set_frame_scale(Vector2(2, 2))
	var info := PixelGrid.probe(canvas, Vector2i(0, 0), Vector2i(5, 3))
	assert_eq(info.frame, Vector2i(2, 1), "each pixel of the frame is 2×2 on the sheet")
	assert_matches_export()
	sheet.set_frame_scale(Vector2(1.5, 1.5))
	assert_matches_export()
	sheet.set_frame_scale(Vector2(0.5, 0.75))
	assert_matches_export()


func test_flipped_frames_map_to_their_pixels() -> void:
	var img := gradient(Vector2i(5, 3))
	sheet.add_frames([img] as Array[Image])
	FrameEdits.flip(sheet, [Vector2i(0, 0)] as Array[Vector2i], true)
	var info := PixelGrid.probe(canvas, Vector2i(0, 0), Vector2i(4, 1))
	assert_eq(info.frame, Vector2i(4, 1), "the pixels of the frame as it is now")
	assert_eq(info.color, img.get_pixel(0, 1), "the left column is on the right")
	assert_matches_export()


func test_trimmed_frames_map_to_their_pixels() -> void:
	var images: Array[Image] = [
		sprite(Vector2i(8, 8), Rect2i(2, 3, 4, 4)), gradient(Vector2i(8, 8))
	]
	sheet.add_frames(images)
	FrameEdits.trim(sheet, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(sheet.frames[Vector2i(0, 0)].get_size(), Vector2i(4, 4))
	# Trimming leaves the pixels where they were in the cell
	var info := PixelGrid.probe(canvas, Vector2i(0, 0), Vector2i(3, 4))
	assert_eq(info.frame, Vector2i(1, 1))
	assert_matches_export()

	# Packing trims too, but the frame keeps its pixels
	sheet.clear()
	sheet.add_frames(images)
	sheet.set_layout(Spritesheet.Layout.PACKED)
	var place: Dictionary = sheet.placements[Vector2i(0, 0)]
	assert_eq(place.src, Rect2i(2, 3, 4, 4), "packed without the transparent border")
	var page := Vector2i(canvas.packed_view.page_origins[place.page])
	info = PixelGrid.probe(canvas, Vector2i(0, 0), page + Vector2i(place.position) + Vector2i.ONE)
	assert_eq(info.frame, Vector2i(3, 4), "in the untrimmed frame")
	assert_eq(info.sheet, Vector2i(place.position) + Vector2i.ONE)
	assert_matches_export()


## Stores the first frame turned, [param src] of it right of the other frame, 1 pixel
## down. Returns where it is in the preview.
func turn_first_frame(src: Rect2i) -> Vector2i:
	var position := Vector2i(PackedLayout.get_rect(sheet, Vector2i(1, 0)).end.x + 1, 1)
	var place := PackedLayout.new_place(0, position, src, true)
	sheet.set_placements({Vector2i(0, 0): place})
	return Vector2i(canvas.packed_view.page_origins[0]) + position


func test_turned_packed_frames_map_to_their_pixels() -> void:
	sheet.add_frames([gradient(Vector2i(5, 3)), gradient(Vector2i(4, 4))] as Array[Image])
	sheet.set_layout(Spritesheet.Layout.PACKED)
	# Stored turned clockwise: the frame's left column is the top row, bottom up
	var at := turn_first_frame(Rect2i(0, 0, 5, 3))
	var info := PixelGrid.probe(canvas, Vector2i(0, 0), at)
	assert_eq(info.frame, Vector2i(0, 2), "the top-left is the frame's bottom-left")
	assert_eq(info.sheet, at - Vector2i(canvas.packed_view.page_origins[0]))
	info = PixelGrid.probe(canvas, Vector2i(0, 0), at + Vector2i(2, 4))
	assert_eq(info.frame, Vector2i(4, 0), "the bottom-right is its top-right")
	assert_matches_export()

	sheet.set_frame_scale(Vector2(2, 2))
	at = turn_first_frame(Rect2i(0, 0, 10, 6))
	info = PixelGrid.probe(canvas, Vector2i(0, 0), at + Vector2i(1, 1))
	assert_eq(info.frame, Vector2i(0, 2), "2×2 pixels of the page per pixel of the frame")
	assert_matches_export()


func test_the_colour_and_where_it_is_are_described() -> void:
	var img := make_image(Color8(255, 0, 0, 128), Vector2i(4, 4))
	img.set_pixel(1, 2, Color("3a7bd5"))
	sheet.add_frames([img, make_image(Color.WHITE, Vector2i(6, 6))] as Array[Image])
	# The first frame is centred in its 6×6 cell
	var info := PixelGrid.probe(canvas, Vector2i(0, 0), Vector2i(2, 3))
	assert_eq(
		PixelGrid.describe(info), "1, 2 in the frame (2, 3 on the sheet) · #3a7bd5, alpha 255"
	)
	info = PixelGrid.probe(canvas, Vector2i(0, 0), Vector2i(1, 1))
	assert_eq(
		PixelGrid.describe(info), "0, 0 in the frame (1, 1 on the sheet) · #ff0000, alpha 128"
	)
	info = PixelGrid.probe(canvas, Vector2i(0, 0), Vector2i(0, 5))
	assert_eq(PixelGrid.describe(info), "0, 5 on the sheet", "in the cell, beside the frame")
	assert_eq(PixelGrid.describe(PixelGrid.probe(canvas, Vector2i(3, 0), Vector2i.ZERO)), "")

	sheet.set_layout(Spritesheet.Layout.PACKED)
	var place := PackedLayout.new_place(0, Vector2i(20, 1), Rect2i(0, 0, 6, 6))
	sheet.set_placements({Vector2i(1, 0): place})
	var at := Vector2i(canvas.packed_view.page_origins[0])
	var text := PixelGrid.describe(PixelGrid.probe(canvas, Vector2i(1, 0), at + Vector2i(23, 3)))
	assert_eq(text, "3, 2 in the frame (23, 3 on the sheet) · #ffffff, alpha 255", "one page")
	place = PackedLayout.new_place(1, Vector2i(2, 1), Rect2i(0, 0, 6, 6))
	sheet.set_placements({Vector2i(1, 0): place})
	at = Vector2i(canvas.packed_view.page_origins[1])
	text = PixelGrid.describe(PixelGrid.probe(canvas, Vector2i(1, 0), at + Vector2i(5, 3)))
	assert_eq(text, "3, 2 in the frame (5, 3 on page 2) · #ffffff, alpha 255")


## Lines between the pixels of the frame, at [param axis] (0 for vertical ones) in the
## frame at [param coord]
func line_positions(coord: Vector2i, axis: int) -> Array[float]:
	var rect := Rect2(PixelGrid.get_frame_view(canvas, coord).rect)
	var points := PixelGrid.get_lines(canvas, [coord] as Array[Vector2i], rect.grow(100))
	var positions: Array[float] = []
	for i in range(0, points.size(), 2):
		if points[i][axis] == points[i + 1][axis]:
			positions.append(points[i][axis] - rect.position[axis])
	return positions


func test_lines_follow_the_pixels_of_scaled_frames() -> void:
	sheet.add_frames([gradient(Vector2i(4, 2))] as Array[Image])
	assert_eq(line_positions(Vector2i(0, 0), 0), [0.0, 1.0, 2.0, 3.0, 4.0] as Array[float])
	sheet.set_frame_scale(Vector2(2, 1))
	assert_eq(line_positions(Vector2i(0, 0), 0), [0.0, 2.0, 4.0, 6.0, 8.0] as Array[float])
	assert_eq(line_positions(Vector2i(0, 0), 1), [0.0, 1.0, 2.0] as Array[float])
	# 4 pixels over 6: where Nearest shows the next pixel of the frame, which is the
	# second and the fourth twice
	sheet.set_frame_scale(Vector2(1.5, 1))
	assert_eq(line_positions(Vector2i(0, 0), 0), [0.0, 1.0, 3.0, 4.0, 6.0] as Array[float])
	var scaled := sheet.get_frame_image(Vector2i(0, 0))
	assert_ne(scaled.get_pixel(1, 0), scaled.get_pixel(0, 0))
	assert_eq(scaled.get_pixel(2, 0), scaled.get_pixel(1, 0), "one pixel of the frame")
	assert_eq(scaled.get_pixel(5, 0), scaled.get_pixel(4, 0), "another")

	# Turned frames have the frame's columns down the page
	sheet.set_frame_scale(Vector2(2, 1))
	sheet.set_layout(Spritesheet.Layout.PACKED)
	var src := Rect2i(0, 0, 8, 2)
	sheet.set_placements({Vector2i(0, 0): PackedLayout.new_place(0, Vector2i(0, 0), src, true)})
	assert_eq(line_positions(Vector2i(0, 0), 0), [0.0, 1.0, 2.0] as Array[float])
	assert_eq(line_positions(Vector2i(0, 0), 1), [0.0, 2.0, 4.0, 6.0, 8.0] as Array[float])


func test_only_visible_pixels_get_lines() -> void:
	sheet.set_grid_size(Vector2i(20, 20))
	var images: Array[Image] = []
	for i in 400:
		images.append(gradient(Vector2i(16, 16)))
	sheet.add_frames(images)
	var coords: Array[Vector2i] = []
	coords.assign(sheet.frames.keys())
	# 40×30 pixels of a 320×320 sheet, across 4 columns and 3 rows of frames: in each row
	# 7, 17, 17 and 3 lines down (with both edges of frames), in each column 7, 17 and 9
	# across
	var visible := Rect2(10, 10, 40, 30)
	var points := PixelGrid.get_lines(canvas, coords, visible)
	assert_eq(points.size(), (44 * 3 + 33 * 4) * 2)
	for point in points:
		assert_true(visible.grow(0.001).has_point(point), str(point))


## Opens the main scene, freed after the test
func open_main() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame


func test_the_setting_turns_the_pixel_grid_on_and_off() -> void:
	await open_main()
	assert_true(main.preview.show_pixel_grid, "on by default")
	assert_true(Actions.is_checked(&"toggle_pixel_grid"))
	Actions.run(&"toggle_pixel_grid")
	assert_false(Settings.get_value(&"show_pixel_grid"))
	assert_false(main.preview.show_pixel_grid)
	assert_eq(Actions.get_shortcut_text(&"toggle_pixel_grid"), "Shift+G")
	Settings.set_value(&"show_pixel_grid", true)


func test_the_status_bar_shows_the_pixel_under_the_mouse() -> void:
	await open_main()
	var img := make_image(Color.RED, Vector2i(8, 8))
	img.set_pixel(3, 2, Color.BLUE)
	var images: Array[Image] = [make_image(Color.WHITE, Vector2i(8, 8)), img]
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(images))
	var preview: SpritesheetPreview = main.preview
	preview.camera.position = Vector2.ZERO
	preview.set_zoom(10)
	var event := InputEventMouseMotion.new()
	event.position = Vector2(8 + 3.5, 2.5) * 10
	preview._unhandled_input(event)
	var text: String = main.cell_info.text
	assert_true(text.begins_with("Cell 1 (column 1, row 0) · 3, 2 in the frame "), text)
	assert_true("(11, 2 on the sheet) · #0000ff, alpha 255 · 8×8 px" in text, text)
	event.position = Vector2(8 + 4.5, 2.5) * 10
	preview._unhandled_input(event)
	assert_true("4, 2 in the frame (12, 2 on the sheet) · #ff0000" in main.cell_info.text)
	main.preview_area.container.mouse_exited.emit()
	assert_eq(main.cell_info.text, "")
