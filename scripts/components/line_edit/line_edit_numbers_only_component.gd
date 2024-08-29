class_name LineEditNumberOnlyComponent
extends Node


@onready var line_edit: LineEdit = get_parent()
@onready var regex_number_only = RegEx.new()

var old_text = ""


func _ready() -> void:
	regex_number_only.compile("^[0-9]*$")
	
	line_edit.text_changed.connect(_on_line_edit_text_changed)
	line_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _on_line_edit_text_changed(new_text: String):
	if regex_number_only.search(new_text):
		old_text = str(new_text)
	else:
		line_edit.text = old_text
		line_edit.set_caret_column(line_edit.text.length())
