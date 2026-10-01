class_name ReloadDialog
extends AcceptDialog
## Asks whether to reload a linked file that changed on disk, keeping the edits made to
## its frames here or not. With more changed files, the answer can go for all of them.

enum Choice {
	KEEP_EDITS,  ## Reload and make the edits made here again
	RESET,  ## Reload as the file is
	IGNORE,  ## Leave the frames as they are
}

## Emitted with the [enum Choice], and whether it goes for the other changed files too
signal chosen(choice: Choice, for_all: bool)

var message := Label.new()
var for_all_check := CheckBox.new()
var reset_button: Button
var ignore_button: Button
var _edited := false
var _others_edited := false


func _init() -> void:
	title = "File Changed"
	DialogButtons.apply(self, true)
	dialog_hide_on_ok = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.custom_minimum_size = Vector2(360, 0)
	box.add_child(message)
	for_all_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for_all_check.toggled.connect(func(_on: bool) -> void: _update_buttons())
	box.add_child(for_all_check)
	ignore_button = add_cancel_button("Ignore")
	ignore_button.tooltip_text = "Keep the frames as they are"
	reset_button = DialogButtons.add_alternative(self, L10n.mark("Reload, Reset"), &"reset")
	reset_button.tooltip_text = "Reload the file as it is, without the edits made here"
	get_ok_button().icon = MainActions.RELOAD_ICON
	get_ok_button().tooltip_text = "Reload the file and make the edits made here again"

	confirmed.connect(func() -> void: _choose(Choice.KEEP_EDITS))
	canceled.connect(func() -> void: _choose(Choice.IGNORE))
	custom_action.connect(
		func(_action: StringName) -> void:
			hide()
			_choose(Choice.RESET)
	)


## Asks about [param path], which [param frames] frames come from, [param edited] of
## them edited here. [param others] more files changed, some with edited frames when
## [param others_edited].
func ask(path: String, frames: int, edited: int, others: int, others_edited: bool) -> void:
	var text := tr("%s changed on disk. Reload it?") % path.get_file()
	if edited > 0:
		var detail := tr_n(
			"%d of its %d frames was edited here (flipped, trimmed, moved…).",
			"%d of its %d frames were edited here (flipped, trimmed, moved…).",
			edited
		)
		text += "\n\n" + detail % [edited, frames]
	message.text = text
	message.tooltip_text = path
	_edited = edited > 0
	_others_edited = others_edited
	for_all_check.visible = others > 0
	for_all_check.button_pressed = false
	for_all_check.text = (
		tr("Do the same for the other changed file")
		if others == 1
		else (
			tr_n(
				"Do the same for the other %d changed file",
				"Do the same for the other %d changed files",
				others
			)
			% others
		)
	)
	_update_buttons()
	popup_centered()


## Whether to keep or drop edits only matters when some frame was edited
func _update_buttons() -> void:
	var edited := _edited or (for_all_check.button_pressed and _others_edited)
	reset_button.visible = edited
	get_ok_button().text = "Reload, Keep Edits" if edited else "Reload"


func _choose(choice: Choice) -> void:
	chosen.emit(choice, for_all_check.visible and for_all_check.button_pressed)
