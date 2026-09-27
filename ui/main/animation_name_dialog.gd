class_name AnimationNameDialog
extends ConfirmationDialog
## Asks for the name of an animation being made, or renamed, such as "walk" or "jump".

signal name_chosen(animation_name: String)

var line_edit := LineEdit.new()


func _init() -> void:
	DialogButtons.apply(self)
	line_edit.placeholder_text = "For example: walk"
	line_edit.custom_minimum_size = Vector2(260, 0)
	add_child(line_edit)
	register_text_enter(line_edit)
	line_edit.text_changed.connect(_update_ok)
	confirmed.connect(
		func() -> void:
			var animation_name := line_edit.text.strip_edges()
			if animation_name:
				name_chosen.emit(animation_name)
	)


## Opens the dialog with [param suggested] picked, so typing replaces it. [param renaming]
## names an animation that exists rather than a new one.
func open(suggested: String, renaming := false) -> void:
	title = "Rename Animation" if renaming else "New Animation"
	ok_button_text = "Rename" if renaming else "Create"
	line_edit.text = suggested
	_update_ok(suggested)
	popup_centered()
	line_edit.grab_focus()
	line_edit.select_all()


## An animation needs a name
func _update_ok(text: String) -> void:
	get_ok_button().disabled = text.strip_edges().is_empty()
