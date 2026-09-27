extends "res://tests/test_case.gd"

var doc: Document
var sheet: Spritesheet


func before_each() -> void:
	doc = Document.new()
	sheet = doc.spritesheet


func add(color: Color) -> void:
	doc.perform("Add", sheet.add_frames.bind([make_image(color)] as Array[Image]))


func test_undo_and_redo() -> void:
	add(Color.RED)
	add(Color.BLUE)
	assert_eq(sheet.frames.size(), 2)
	doc.undo()
	assert_eq(sheet.frames.size(), 1)
	doc.undo()
	assert_true(sheet.is_empty())
	assert_false(doc.can_undo())
	doc.redo()
	doc.redo()
	assert_eq(sheet.frames.size(), 2)
	assert_color(sheet.frames[Vector2i(1, 0)], Vector2i.ZERO, Color.BLUE)


func test_undo_flip_restores_pixels() -> void:
	var img := make_image(Color.RED)
	img.set_pixel(0, 0, Color.BLUE)
	doc.perform("Add", sheet.add_frames.bind([img] as Array[Image]))
	doc.perform("Flip", FrameEdits.flip.bind(sheet, [Vector2i.ZERO] as Array[Vector2i], true))
	assert_color(sheet.frames[Vector2i.ZERO], Vector2i(15, 0), Color.BLUE)
	doc.undo()
	assert_color(sheet.frames[Vector2i.ZERO], Vector2i(0, 0), Color.BLUE)


func test_no_change_records_nothing() -> void:
	doc.perform("Nothing", sheet.remove_frames.bind([Vector2i(5, 5)] as Array[Vector2i]))
	assert_false(doc.can_undo())
	assert_false(doc.is_dirty)


func test_dirty_follows_saved_version() -> void:
	add(Color.RED)
	assert_true(doc.is_dirty)
	doc.mark_saved()
	assert_false(doc.is_dirty)
	add(Color.BLUE)
	assert_true(doc.is_dirty)
	doc.undo()
	assert_false(doc.is_dirty, "back at the saved state")
	doc.undo()
	add(Color.GREEN)
	assert_true(doc.is_dirty, "a different branch is never the saved state")


func test_one_update_per_perform() -> void:
	var count := [0]
	sheet.updated.connect(func() -> void: count[0] += 1)
	doc.perform(
		"Many",
		func() -> void:
			for i in 5:
				sheet.add_frames([make_image(Color.RED)] as Array[Image])
	)
	assert_eq(count[0], 1)


func test_reset_forgets_history_and_path() -> void:
	add(Color.RED)
	doc.path = "x.png"
	doc.reset()
	assert_true(sheet.is_empty())
	assert_false(doc.can_undo())
	assert_eq(doc.path, "")
	assert_false(doc.is_dirty)


func test_go_to_history() -> void:
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		add(color)
	assert_eq(doc.get_history(), PackedStringArray(["Add", "Add", "Add"]))
	assert_eq(doc.get_history_position(), 3)
	doc.go_to_history(1)
	assert_eq(sheet.frames.size(), 1)
	assert_eq(doc.get_history().size(), 3, "undone steps stay until a new edit")
	doc.go_to_history(3)
	assert_eq(sheet.frames.size(), 3)
	doc.go_to_history(0)
	assert_true(sheet.is_empty())
	assert_false(doc.is_dirty, "back to where it started")


func export_as(target: ExportOptions.Target) -> void:
	var settings := sheet.export_settings.duplicate()
	settings.target = target
	doc.perform("Export settings", sheet.set_export_settings.bind(settings))


func test_export_choices_are_unsaved_but_not_undo_steps() -> void:
	add(Color.RED)
	doc.mark_saved()
	export_as(ExportOptions.Target.GIF)
	assert_true(doc.is_dirty)
	assert_eq(doc.get_history(), PackedStringArray(["Add"]))
	doc.mark_saved()
	assert_false(doc.is_dirty, "saving clears it")
	export_as(ExportOptions.Target.SPRITES)
	export_as(ExportOptions.Target.GIF)
	assert_false(doc.is_dirty, "back to the saved choice")


func test_undo_after_export_choices_undoes_the_last_edit() -> void:
	add(Color.RED)
	add(Color.BLUE)
	export_as(ExportOptions.Target.GIF)
	doc.undo()
	assert_eq(sheet.frames.size(), 1)
	assert_eq(sheet.export_settings.target, ExportOptions.Target.GIF, "choices aren't undone")
	doc.redo()
	assert_eq(sheet.frames.size(), 2)
	assert_eq(sheet.export_settings.target, ExportOptions.Target.GIF)


func test_undo_to_saved_version_with_other_export_choices_stays_unsaved() -> void:
	add(Color.RED)
	doc.mark_saved()
	add(Color.BLUE)
	export_as(ExportOptions.Target.GIF)
	doc.undo()
	assert_true(doc.is_dirty, "the export choices still differ")
	doc.load_state({})
	assert_false(doc.is_dirty, "opening clears it")


func test_layout_export_settings_are_still_undone() -> void:
	export_as(ExportOptions.Target.GIF)
	var spaced := {"target": ExportOptions.Target.GIF, "spacing": 4}
	doc.perform("Spacing", sheet.set_export_settings.bind(spaced))
	assert_eq(doc.get_history(), PackedStringArray(["Spacing"]))
	doc.undo()
	assert_false(sheet.export_settings.has("spacing"))
	assert_eq(sheet.export_settings.target, ExportOptions.Target.GIF, "only the layout's")
