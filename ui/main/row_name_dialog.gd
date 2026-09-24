class_name RowNameDialog
extends ConfirmationDialog
## Asks for the name of a row, such as "walk" or "jump".

signal name_chosen(row: int, row_name: String)

var line_edit := LineEdit.new()
var _row := 0


func _init() -> void:
	ok_button_text = "Rename"
	line_edit.placeholder_text = "For example: walk"
	line_edit.custom_minimum_size = Vector2(260, 0)
	add_child(line_edit)
	register_text_enter(line_edit)
	confirmed.connect(func() -> void: name_chosen.emit(_row, line_edit.text))


func open(row: int, current_name: String) -> void:
	_row = row
	title = "Name Row %d" % row
	line_edit.text = current_name
	popup_centered()
	line_edit.grab_focus()
	line_edit.select_all()
