extends Button


@export var open_file_dialog: FileDialog


func _ready() -> void:
	open_file_dialog.files_selected.connect(Global.spritesheet.add_sprites)


func _pressed() -> void:
	open_file_dialog.popup()
