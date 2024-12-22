extends Node


var spritesheet: Spritesheet = Spritesheet.new()
var filepath: String:
	set(v):
		filepath = v
		update_window_title()
var has_unsaved_changes: bool:
	set(v):
		has_unsaved_changes = v
		update_window_title()


func _ready() -> void:
	spritesheet.updated.connect(set.bind("has_unsaved_changes", true))
	update_window_title()


func update_window_title():
	var title: String = ""
	
	if has_unsaved_changes:
		title += "(*) "
	if not filepath.is_empty():
		title += filepath.get_file()
	
	if not title.is_empty():
		title += " - "
	title += ProjectSettings.get_setting("application/config/name")
	
	DisplayServer.window_set_title(title)


func reset_spritesheet() -> void:
	spritesheet.frames = {}
	spritesheet.sprite_size = Vector2.ZERO
	spritesheet.grid_size = Vector2.ZERO
	spritesheet.updated.emit()
