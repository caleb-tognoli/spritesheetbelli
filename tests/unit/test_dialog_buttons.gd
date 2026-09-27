extends "res://tests/test_case.gd"


## The visible buttons of [param dialog]'s row, and whether anything else shows between
## them
static func visible_row(dialog: AcceptDialog) -> Array[Control]:
	var shown: Array[Control] = []
	for child in dialog.get_ok_button().get_parent().get_children():
		if child is Control and (child as Control).visible:
			shown.append(child)
	return shown


## OK and Cancel in the platform's order
static func pair(ok: Control, cancel: Control) -> Array[Control]:
	return [ok, cancel] if DialogButtons.is_cancel_last() else [cancel, ok]


func test_buttons_are_together_at_the_right_in_the_platform_order() -> void:
	var dialog := ConfirmationDialog.new()
	DialogButtons.apply(dialog)
	var extra := dialog.add_button("Extra", false, "extra")
	add_child(dialog)
	var row := dialog.get_ok_button().get_parent() as HBoxContainer
	assert_eq(row.alignment, BoxContainer.ALIGNMENT_END)
	var expected: Array[Control] = [extra]
	expected.append_array(pair(dialog.get_ok_button(), dialog.get_cancel_button()))
	assert_eq(visible_row(dialog), expected, "no spacers between them, other buttons first")
	extra.hide()
	extra.show()
	assert_eq(visible_row(dialog), expected, "the spacers stay hidden")
	dialog.popup_centered()
	await get_tree().process_frame
	for button: Button in [extra, dialog.get_ok_button(), dialog.get_cancel_button()]:
		assert_eq(button.custom_minimum_size.x, DialogButtons.MIN_WIDTH, "from the theme")
	var cancel_or_ok := expected[-1] as Button
	assert_eq(cancel_or_ok.get_rect().end.x, row.size.x, "at the right")
	dialog.free()


func test_every_dialog_has_its_buttons_at_the_right() -> void:
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var dialogs := main.find_children("*", "AcceptDialog", true, false)
	dialogs.append_array(Notify.find_children("*", "AcceptDialog", true, false))
	var checked := 0
	for dialog: AcceptDialog in dialogs:
		# The system's own file dialogs, the ones inside Godot's controls, and Edit
		# Animation's, which is going away
		var internal := not dialog in dialog.get_parent().get_children()
		if dialog is FileDialog or internal or dialog.get_parent() is AnimationFramesEditor:
			continue
		checked += 1
		var row := dialog.get_ok_button().get_parent() as HBoxContainer
		assert_eq(row.alignment, BoxContainer.ALIGNMENT_END, dialog.title)
		for control in visible_row(dialog):
			assert_true(control is Button, "%s: only buttons show" % dialog.title)
	assert_true(checked >= 12, "found the dialogs")

	var unsaved: ConfirmationDialog = main.files.unsaved_changes_dialog
	var expected: Array[Control] = [visible_row(unsaved)[0]]
	expected.append_array(pair(unsaved.get_ok_button(), unsaved.get_cancel_button()))
	assert_eq(visible_row(unsaved), expected, "Don't Save goes left of Save and Cancel")
	assert_eq((expected[0] as Button).text, "Don't Save")
	main.queue_free()


func test_add_spritesheet_buttons_are_in_the_dialog_order() -> void:
	var window: AddSpritesheetWindow = (
		load("res://ui/add_spritesheet/add_spritesheet_window.tscn").instantiate()
	)
	add_child(window)
	var row := window.add_spritesheet_btn.get_parent()
	var buttons: Array = [window.add_selected_frames_btn]
	buttons.append_array(pair(window.add_spritesheet_btn, window.cancel_btn))
	var last := Array(row.get_children().slice(row.get_child_count() - 3))
	assert_eq(last, buttons, "at the end, the main two in the dialogs' order")
	assert_eq(row.get_child(0), window.keep_empty_cells, "the option at the left")
	var canceled := [0]
	window.canceled.connect(func() -> void: canceled[0] += 1)
	window.cancel_btn.pressed.emit()
	assert_eq(canceled[0], 1, "Cancel cancels")
	window.free()
