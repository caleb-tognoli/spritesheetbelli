extends "res://tests/test_case.gd"

var window: AddSpritesheetWindow


func before_each() -> void:
	Global.document.reset()
	Settings.set_value(&"background_tolerance", SheetBackground.DEFAULT_TOLERANCE)
	window = load("res://ui/add_spritesheet/add_spritesheet_window.tscn").instantiate()
	add_child(window)


func after_each() -> void:
	window.queue_free()
	Global.document.reset()


## 24 px sprites with a 4 px border and 2 px gaps, and 2 px of spacing after the last
## column and row too, on a grey background: 134×56
func trailing_spacing_sheet() -> Image:
	var img := Image.create_empty(134, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color.GRAY)
	for row in 2:
		for column in 5:
			var cell := Rect2i(Vector2i(4, 4) + Vector2i(column, row) * 26, Vector2i(24, 24))
			img.fill_rect(cell, Color.RED)
	return img


func get_grid() -> Vector2i:
	return Vector2i(int(window.grid_columns.value), int(window.grid_rows.value))


func get_cell_size() -> Vector2i:
	return Vector2i(int(window.cell_width.value), int(window.cell_height.value))


func set_offset_and_spacing(offset: int, spacing: int) -> void:
	for field: SpinBox in [window.offset_x, window.offset_y]:
		field.value = offset
	for field: SpinBox in [window.spacing_x, window.spacing_y]:
		field.value = spacing


func test_the_cell_size_sets_the_grid() -> void:
	window.setup(trailing_spacing_sheet())
	set_offset_and_spacing(4, 2)
	window.cell_width.value = 24
	window.cell_height.value = 24
	assert_eq(get_grid(), Vector2i(5, 2))
	assert_eq(window.spritesheet.grid_size, Vector2i(5, 2))
	assert_eq(window.spritesheet.frames.size(), 10)
	for coord: Vector2i in window.spritesheet.frames:
		var frame: Image = window.spritesheet.frames[coord]
		assert_eq(frame.get_size(), Vector2i(24, 24))
		assert_color(frame, Vector2i(23, 23), Color.RED, "no background in %s" % coord)
	assert_eq(
		window.preview_area.notice_label.text,
		"2 px on the right and 2 px at the bottom not used",
		"the spacing after the last cells"
	)
	assert_eq(window.slice_info.text, "10 frames")


func test_the_grid_sets_the_cell_size() -> void:
	window.setup(trailing_spacing_sheet())
	window.grid_columns.value = 5
	window.grid_rows.value = 2
	assert_eq(get_cell_size(), Vector2i(26, 28))
	assert_eq(window.preview_area.notice_label.text, "4 px on the right not used")


func test_the_grid_leaves_background_spacing_after_the_last_cells_over() -> void:
	window.setup(trailing_spacing_sheet())
	set_offset_and_spacing(4, 2)
	window.update_grid_size(5, 2)
	assert_eq(get_cell_size(), Vector2i(24, 24), "not 24×25")
	assert_eq(window.spritesheet.frames.size(), 10)
	for coord: Vector2i in window.spritesheet.frames:
		var frame: Image = window.spritesheet.frames[coord]
		assert_eq(frame.get_size(), Vector2i(24, 24))
		assert_color(frame, Vector2i(23, 23), Color.RED, "no background in %s" % coord)
	assert_eq(
		window.preview_area.notice_label.text,
		"2 px on the right and 2 px at the bottom not used",
		"the spacing after the last cells"
	)

	# The background is still told apart when it's not made transparent
	window.background.set_key(false, Color.GRAY)
	window._cut_with_background()
	window.update_grid_size(5, 2)
	assert_eq(get_cell_size(), Vector2i(24, 24))

	var img := trailing_spacing_sheet()
	img.fill_rect(Rect2i(10, 50, 8, 6), Color.BLUE)
	window.setup(img)
	assert_true(window.background.is_on(), "grey made transparent")
	set_offset_and_spacing(4, 2)
	window.update_grid_size(5, 2)
	assert_eq(get_cell_size(), Vector2i(24, 25), "a strip with sprites in it is part of them")


func test_the_last_pair_set_is_kept() -> void:
	window.setup(trailing_spacing_sheet())
	window.update_cell_size(24, 24)
	set_offset_and_spacing(4, 2)
	assert_eq(get_cell_size(), Vector2i(24, 24), "cell size kept")
	assert_eq(get_grid(), Vector2i(5, 2))
	window.spacing_x.value = 8
	assert_eq(get_cell_size(), Vector2i(24, 24), "cell size kept")
	assert_eq(get_grid(), Vector2i(4, 2), "fewer columns fit")

	window.grid_columns.value = 2
	assert_eq(get_cell_size(), Vector2i(61, 24), "floor((134 - 4 + 8) / 2) - 8")
	window.offset_x.value = 0
	assert_eq(get_grid(), Vector2i(2, 2), "grid kept")
	assert_eq(get_cell_size(), Vector2i(63, 24))

	window.set_cut(AddSpritesheetWindow.Cut.DETECT)
	window.set_cut(AddSpritesheetWindow.Cut.GRID)
	assert_eq(get_grid(), Vector2i(2, 2), "the same grid after cutting another way")


func test_a_sprite_size_in_the_name_is_kept() -> void:
	window.setup(trailing_spacing_sheet(), "hero_24x24.png")
	assert_eq(get_cell_size(), Vector2i(24, 24))
	assert_eq(get_grid(), Vector2i(5, 2))
	set_offset_and_spacing(4, 2)
	assert_eq(get_cell_size(), Vector2i(24, 24))
	assert_eq(get_grid(), Vector2i(5, 2))
	assert_eq(window.spritesheet.frames.size(), 10)


func test_cells_stay_in_the_image() -> void:
	window.setup(trailing_spacing_sheet())
	assert_eq(window.cell_width.max_value, 134.0)
	assert_eq(window.offset_y.max_value, 55.0, "leaves a pixel")
	window.offset_x.value = 34
	window.cell_width.value = 134
	assert_eq(get_cell_size().x, 100, "what's left after the offset")
	assert_eq(get_grid().x, 1)


## 4 × 2 sprites of 12 px in 16 px cells, on transparency
func gaps_sheet() -> Image:
	var img := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	for row in 2:
		for column in 4:
			var sprite := Rect2i(Vector2i(column, row) * 16 + Vector2i(2, 2), Vector2i(12, 12))
			img.fill_rect(sprite, Color.RED)
	return img


## Where the sprites of [method gaps_sheet] are
func data_for_gaps_sheet() -> SheetData:
	var frames := {}
	for i in 8:
		var place := Vector2i(i % 4, i / 4) * 16 + Vector2i(2, 2)
		frames[str(i)] = {"frame": {"x": place.x, "y": place.y, "w": 12, "h": 12}}
	return SheetData.parse_json(JSON.stringify({"frames": frames}))


func test_the_default_cut_follows_the_layout() -> void:
	var grid := Spritesheet.Layout.GRID
	var packed := Spritesheet.Layout.PACKED
	assert_eq(AddSpritesheetWindow.get_default_cut(false, grid), AddSpritesheetWindow.Cut.GRID)
	assert_eq(AddSpritesheetWindow.get_default_cut(false, packed), AddSpritesheetWindow.Cut.DETECT)
	assert_eq(AddSpritesheetWindow.get_default_cut(true, grid), AddSpritesheetWindow.Cut.DATA)
	assert_eq(AddSpritesheetWindow.get_default_cut(true, packed), AddSpritesheetWindow.Cut.DATA)


func test_opens_in_a_grid_in_the_grid_layout() -> void:
	window.setup(gaps_sheet())
	assert_eq(window.get_cut(), AddSpritesheetWindow.Cut.GRID)
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 2), "the guessed grid")
	assert_true((window.grid_columns.get_parent().get_parent() as Control).visible)


func test_opens_finding_sprites_in_the_packed_layout() -> void:
	Global.spritesheet.set_layout(Spritesheet.Layout.PACKED)
	window.setup(gaps_sheet())
	assert_eq(window.get_cut(), AddSpritesheetWindow.Cut.DETECT)
	assert_eq(window.spritesheet.frames.size(), 8)
	assert_false((window.grid_columns.get_parent().get_parent() as Control).visible)
	window.set_cut(AddSpritesheetWindow.Cut.GRID)
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 2), "the guessed grid is ready")


func test_a_data_file_wins_over_the_layout() -> void:
	for layout: Spritesheet.Layout in [Spritesheet.Layout.GRID, Spritesheet.Layout.PACKED]:
		Global.spritesheet.set_layout(layout)
		window.setup(gaps_sheet(), "", data_for_gaps_sheet(), "sheet.json")
		assert_eq(window.get_cut(), AddSpritesheetWindow.Cut.DATA, str(layout))
		assert_eq(window.spritesheet.frames.size(), 8)


## Exported frame tags have the animations' colours, which come back as they were when
## the sheet is added with its data file, even to a sheet whose animations have the same
## colours
func test_animation_colours_come_back() -> void:
	var sheet := Spritesheet.new()
	var images: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]:
		images.append(make_image(color, Vector2i(8, 8)))
	sheet.add_frames(images)
	var coords := sheet.get_sorted_coords()
	# The first two get the palette's first colours, the third one of its own
	sheet.add_animation(SheetAnimation.create("walk", coords.slice(0, 2)))
	sheet.add_animation(SheetAnimation.create("jump", coords.slice(2, 3)))
	var hit := SheetAnimation.create("hit", coords.slice(3, 4))
	hit.color = Color("40e0c0")
	sheet.add_animation(hit)
	var colors := sheet.animations.map(
		func(animation: SheetAnimation) -> Color: return animation.color
	)
	var options := ExportOptions.new()
	var frames := Metadata.grid_frames(sheet, options)
	var json := Metadata.sheet_json(sheet, frames, "sheet.png", Vector2i(32, 8), 12)
	var tags: Array = JSON.parse_string(json).meta.frameTags
	assert_eq(
		tags.map(func(tag: Dictionary) -> String: return tag.color),
		["#" + colors[0].to_html(), "#" + colors[1].to_html(), "#40e0c0ff"]
	)
	var target := Global.spritesheet
	target.add_frames([make_image(Color.WHITE)] as Array[Image])
	target.add_animation(SheetAnimation.create("run", [Vector2i.ZERO] as Array[Vector2i]))
	target.add_animation(SheetAnimation.create("idle", [Vector2i.ZERO] as Array[Vector2i]))
	assert_eq(target.animations[1].color, colors[1], "the same colours as two of them")
	var image := SpritesheetExporter.build_image(sheet, options)
	window.setup(image, "", SheetData.parse_json(json), "sheet.json")
	assert_eq(window.get_cut(), AddSpritesheetWindow.Cut.DATA)
	window.add_spritesheet_to_global()
	var added := target.animations.slice(2).map(
		func(animation: SheetAnimation) -> Color: return animation.color
	)
	assert_eq(added, colors, "kept")
