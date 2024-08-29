class_name LineEditSetDefaultOnEmptySubmitComponent
extends Node


@export var default_value: String

@onready var line_edit: LineEdit = get_parent()


func _ready() -> void:
	line_edit.text_submitted.connect(set_default_if_empty)


func set_default_if_empty(new_text: String):
	if new_text.is_empty():
		line_edit.text = default_value
		line_edit.text_submitted.emit(line_edit.text)
