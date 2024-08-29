class_name AcceptDialogCenterTextComponent
extends Node


@onready var dialog: AcceptDialog = get_parent()


func _ready() -> void:
	dialog.get_label().align = HORIZONTAL_ALIGNMENT_CENTER
