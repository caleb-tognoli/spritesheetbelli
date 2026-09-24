extends Node
## Holds the open document and keeps the window title in sync with it.

var document := Document.new()
## The open document's spritesheet
var spritesheet: Spritesheet:
	get:
		return document.spritesheet


func _ready() -> void:
	document.changed.connect(update_window_title)
	update_window_title()


func update_window_title() -> void:
	var title := ""
	if document.is_dirty:
		title += "(*) "
	title += document.get_display_name()
	if not title.is_empty():
		title += " - "
	title += ProjectSettings.get_setting("application/config/name")
	DisplayServer.window_set_title(title)
