extends "res://tests/test_case.gd"
## Every animation's colour: picked far from the others' when it's added, saved with the
## project, undone, changed in the details or from its name on the grid, shown in the list
## and on labels that overlap

const GRID := Vector2i(6, 2)
const PANEL_SETTINGS: Array[StringName] = [&"animation_panel", &"animation_panel_height"]

var main: Control
var sheet: Spritesheet


func after_each() -> void:
	if main:
		main.queue_free()
		main = null
	Global.document.reset()
	for key in PANEL_SETTINGS:
		Settings.set_value(key, Settings.DEFAULTS[key])


## A sheet of [constant GRID] filled with frames
static func filled_sheet() -> Spritesheet:
	var filled := Spritesheet.new()
	filled.set_grid_size(GRID)
	for y in GRID.y:
		for x in GRID.x:
			filled.set_frame(Vector2i(x, y), make_image(Color.RED))
	return filled


static func row(y: int, from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(from, to + 1):
		cells.append(Vector2i(x, y))
	return cells


static func colors_of(of_sheet: Spritesheet) -> Array[Color]:
	var colors: Array[Color] = []
	for animation in of_sheet.animations:
		colors.append(animation.color)
	return colors


## How far apart two hues are, from 0 to 0.5
static func hue_distance(a: Color, b: Color) -> float:
	var apart := absf(a.ok_hsl_h - b.ok_hsl_h)
	return minf(apart, 1.0 - apart)


func open_main() -> void:
	Settings.set_value(&"animation_panel", "open")
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	sheet = Global.spritesheet
	Global.document.perform("Add", func() -> void: sheet.set_state(filled_sheet().get_state()))


func test_new_animations_get_colours_far_apart() -> void:
	var colored := filled_sheet()
	for i in 6:
		colored.add_animation(SheetAnimation.create("a%d" % i, row(0, i, i)))
	var colors := colors_of(colored)
	assert_eq(colors[0], SheetAnimation.get_palette_color(0), "the first is blue")
	assert_true(hue_distance(colors[0], colors[1]) > 0.45, "the second across the wheel")
	for i in colors.size():
		assert_eq(colors[i].a, 1.0, "opaque")
		for j in i:
			assert_true(hue_distance(colors[i], colors[j]) > 0.08, "%d and %d apart" % [i, j])
	# Past the palette, each colour is used again evenly
	var taken: Array[Color] = []
	for i in SheetAnimation.HUES * 2:
		taken.append(SheetAnimation.pick_color(taken))
	for i in SheetAnimation.HUES:
		assert_eq(taken.count(SheetAnimation.get_palette_color(i)), 2, "colour %d twice" % i)
	# An animation that has a colour keeps it
	var chosen := SheetAnimation.create("chosen", row(1, 0, 1))
	chosen.color = Color.WHITE
	colored.add_animation(chosen)
	assert_eq(colored.animations[-1].color, Color.WHITE)


func test_deleting_an_animation_keeps_the_others_colours() -> void:
	var colored := filled_sheet()
	for i in 3:
		colored.add_animation(SheetAnimation.create("a%d" % i, row(0, i, i)))
	var colors := colors_of(colored)
	colored.remove_animation(0)
	assert_eq(colors_of(colored), colors.slice(1))
	colored.add_animation(SheetAnimation.create("again", row(1, 0, 0)))
	assert_false(colored.animations[-1].color in colors.slice(1), "far from those left")


func test_colours_are_saved_with_the_project() -> void:
	var saved := filled_sheet()
	saved.add_animation(SheetAnimation.create("walk", row(0, 0, 2)))
	var chosen := SheetAnimation.create("run", row(0, 3, 5))
	chosen.color = Color("d05a9e")
	saved.add_animation(chosen)
	var path := temp_path("colors.sbelli")
	assert_eq(ProjectFile.save(saved, path), OK)
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	assert_eq(colors_of(loaded), colors_of(saved))
	assert_eq(loaded.animations[1].color, Color("d05a9e"))


func test_projects_without_colours_get_them_when_opened() -> void:
	var saved := filled_sheet()
	for i in 3:
		saved.add_animation(SheetAnimation.create("a%d" % i, row(0, i, i)))
	var path := temp_path("old.sbelli")
	assert_eq(ProjectFile.save(saved, path), OK)
	# Rewritten the way projects were saved before animations had colours
	var reader := ZIPReader.new()
	reader.open(path)
	var data: Dictionary = JSON.parse_string(
		reader.read_file(ProjectFile.JSON_FILE).get_string_from_utf8()
	)
	var frames := reader.read_file(ProjectFile.FRAMES_FILE)
	reader.close()
	for animation: Dictionary in data.animations:
		animation.erase("color")
	data.animations[1].color = "#ffffff"
	var writer := ZIPPacker.new()
	writer.open(path)
	ProjectFile._write(writer, ProjectFile.JSON_FILE, JSON.stringify(data).to_utf8_buffer())
	ProjectFile._write(writer, ProjectFile.FRAMES_FILE, frames)
	writer.close()
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	var colors := colors_of(loaded)
	assert_eq(colors[1], Color.WHITE, "a saved colour stays")
	assert_eq(colors[0], SheetAnimation.get_palette_color(0), "the others picked in order")
	assert_ne(colors[2], colors[0])
	loaded.set_state(ProjectFile.load(path).state)
	assert_eq(colors_of(loaded), colors, "the same every time")


func test_mirrored_copies_get_a_colour_of_their_own() -> void:
	var mirrored := filled_sheet()
	mirrored.add_animation(SheetAnimation.create("walk_right", row(0, 0, 2)))
	mirrored.add_animation(SheetAnimation.create("idle", row(0, 3, 5)))
	var copy := SheetAnimation.mirror(mirrored, 0)
	var colors := colors_of(mirrored)
	assert_eq(mirrored.animations[copy].name, "walk_left")
	assert_false(colors[copy] in colors.slice(0, copy), "not the colour of another")


func test_animations_from_imports_get_colours_apart_from_the_sheets() -> void:
	var target := filled_sheet()
	target.add_animation(SheetAnimation.create("walk", row(0, 0, 2)))
	var gif := {"delays": [0.1, 0.1] as Array[float], "loop": true}
	GifDecoder.add_animation(target, gif, row(1, 0, 1), "spin")
	# A sheet added below, whose animation has its own sheet's first colour
	var added := filled_sheet()
	added.add_animation(SheetAnimation.create("jump", row(0, 0, 2)))
	AddSpritesheetWindow.add_sheet(target, added, false)
	var colors := colors_of(target)
	assert_eq(colors.size(), 3)
	assert_ne(colors[1], colors[0], "the GIF's")
	assert_false(colors[2] in colors.slice(0, 2), "the added sheet's")


func test_colour_in_the_details_and_the_list() -> void:
	await open_main()
	var panel: AnimationPanel = main.animation_panel
	var detail := panel.detail
	main.preview.set_selected_coords(row(0, 0, 2))
	panel.new_button.pressed.emit()
	var first := sheet.animations[0].color
	assert_eq(first, SheetAnimation.get_palette_color(0), "picked when made with New")
	assert_eq(detail.color_button.color, first, "shown in the details")
	assert_eq(panel.list.get_item_icon(1), AppTheme.swatch(first), "and in the list")
	var steps := Global.document.undo_redo.get_history_count()
	detail.color_button.color = Color("e0c040")
	detail.color_button.popup_closed.emit()
	assert_eq(sheet.animations[0].color, Color("e0c040"))
	assert_eq(Global.document.undo_redo.get_history_count(), steps + 1, "one step")
	assert_eq(Global.document.get_history()[-1], "Recolour animation")
	assert_eq(panel.list.get_item_icon(1), AppTheme.swatch(Color("e0c040")))
	Global.document.undo()
	assert_eq(sheet.animations[0].color, first, "undone")
	assert_eq(detail.color_button.color, first)
	Global.document.redo()
	assert_eq(sheet.animations[0].color, Color("e0c040"), "redone")
	# Closing the picker without changing it isn't a step
	detail.color_button.popup_closed.emit()
	assert_eq(Global.document.undo_redo.get_history_count(), steps + 1)
	# Other edits keep it
	detail.name_edit.text = "walk"
	detail.name_edit.text_submitted.emit("walk")
	assert_eq(sheet.animations[0].color, Color("e0c040"))


func test_overlapping_labels_use_the_animation_colour() -> void:
	await open_main()
	var preview: SpritesheetPreview = main.preview
	var controls: AnimationLabelControls = main.preview_area.label_controls
	var labels := preview.animation_labels
	Global.document.perform(
		"Animations",
		func() -> void:
			sheet.add_animation(SheetAnimation.create("walk", row(0, 0, 5)))
			sheet.add_animation(SheetAnimation.create("run", row(0, 0, 2)))
			sheet.add_animation(SheetAnimation.create("idle", row(1, 0, 5)))
	)
	var colors := colors_of(sheet)
	assert_eq(
		labels.labels.map(func(label: Dictionary) -> bool: return label.colored),
		[true, true, false]
	)
	assert_eq(labels._get_color(labels.labels[0]), colors[0])
	assert_eq(labels._get_color(labels.labels[1]), colors[1])
	assert_ne(labels._get_color(labels.labels[2]), colors[2], "alone, in the interface's colour")
	# Colour… in its name's menu
	controls.open_menu(1, Vector2.ZERO)
	controls.menu.id_pressed.emit(AnimationLabelControls.Item.COLOR)
	controls.menu.hide()
	assert_true(controls.color_popup.visible, "the picker")
	assert_eq(controls.color_picker.color, colors[1])
	controls.color_picker.color = Color("40c0a0")
	controls.color_popup.hide()
	assert_eq(sheet.animations[1].color, Color("40c0a0"))
	assert_eq(Global.document.get_history()[-1], "Recolour animation")
	assert_eq(labels._get_color(labels.labels[1]), Color("40c0a0"))
	# Deleting one doesn't change the colours of the others
	Global.document.perform("Delete", sheet.remove_animation.bind(0))
	assert_eq(labels.labels.size(), 2)
	assert_eq(labels.labels[0].color, Color("40c0a0"))
	assert_eq(labels.labels[1].color, colors[2])
