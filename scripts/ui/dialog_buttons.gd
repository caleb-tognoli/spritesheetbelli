class_name DialogButtons
## Lays out the buttons of every dialog the same way: at the right (in the middle for
## dialogs that are only a message or a question), at least [constant MIN_WIDTH] wide (the
## theme's [code]buttons_min_width[/code]), in the order [AcceptDialog] puts them for the
## platform. OK comes before Cancel on Windows and after it elsewhere (the
## [code]gui/common/swap_cancel_ok[/code] project setting can change that), and other
## buttons go to the left of the two.

## Windows' standard button width, in interface units, so scaled with the interface
const MIN_WIDTH := 88


## Moves the buttons of [param dialog] to the right, also ones added or shown later, or
## when [param centered], to the middle along with its text, for dialogs that are only a
## message or a question. Other buttons are added with
## [code]add_button(text, false)[/code], to go on the left, or with [method add_alternative].
static func apply(dialog: AcceptDialog, centered := false) -> void:
	var row := dialog.get_ok_button().get_parent() as HBoxContainer
	row.alignment = BoxContainer.ALIGNMENT_CENTER if centered else BoxContainer.ALIGNMENT_END
	if centered:
		dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hide_spacers(row)
	row.child_order_changed.connect(_hide_spacers.bind(row))


## Adds a button that answers otherwise than OK, like Don't Save beside Save: right after
## OK where OK comes before Cancel (Windows), and first elsewhere, away from OK (macOS).
## Added after Cancel, so it stays first.
static func add_alternative(dialog: AcceptDialog, text: String, action: StringName) -> Button:
	var button := dialog.add_button(text, false, action)
	if is_cancel_last():
		button.get_parent().move_child(button, dialog.get_ok_button().get_index() + 1)
	return button


## Puts [param ok] and [param cancel] at the end of [param row] in the order dialogs have
## them, [param others] before them, as wide and as far apart as a dialog's buttons, for
## windows that aren't an [AcceptDialog]
static func arrange(row: HBoxContainer, ok: Button, cancel: Button, others: Array[Button]) -> void:
	var buttons := others.duplicate()
	buttons.append_array([ok, cancel] if is_cancel_last() else [cancel, ok])
	for button: Button in buttons:
		button.custom_minimum_size.x = MIN_WIDTH
		row.move_child(button, -1)
	row.add_theme_constant_override(
		"separation", row.get_theme_constant(&"buttons_separation", &"AcceptDialog")
	)


## Whether Cancel is right of OK, found from a dialog Godot lays out
static func is_cancel_last() -> bool:
	var dialog := ConfirmationDialog.new()
	var last := dialog.get_cancel_button().get_index() > dialog.get_ok_button().get_index()
	dialog.free()
	return last


## Godot spreads the buttons out with a spacer beside each, shown along with its button.
## Kept hidden, they leave the buttons together.
static func _hide_spacers(row: HBoxContainer) -> void:
	for child in row.get_children():
		var spacer := child as Control
		if spacer is Button or spacer == null:
			continue
		if not spacer.visibility_changed.is_connected(spacer.hide):
			spacer.hide()
			spacer.visibility_changed.connect(spacer.hide)
