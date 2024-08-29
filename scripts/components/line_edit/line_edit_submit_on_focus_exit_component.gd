class_name LineEditSubmitOnFocusExitComponent
extends Node


@onready var line_edit: LineEdit = get_parent()


func _ready() -> void:
	line_edit.focus_exited.connect(
		func():
			line_edit.text_submitted.emit(line_edit.text)
	)
