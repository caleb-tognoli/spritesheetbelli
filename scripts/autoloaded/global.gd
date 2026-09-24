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
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"ui_scale":
				apply_ui_scale()
	)
	apply_ui_scale()


## Scales the whole interface; "Automatic" follows the screen's scale
func apply_ui_scale() -> void:
	var ui_scale: float = Settings.get_value(&"ui_scale")
	if ui_scale <= 0:
		ui_scale = DisplayServer.screen_get_scale()
	get_tree().root.content_scale_factor = ui_scale


func update_window_title() -> void:
	var title := ""
	if document.is_dirty:
		title += "(*) "
	title += document.get_display_name()
	if not title.is_empty():
		title += " - "
	title += ProjectSettings.get_setting("application/config/name")
	DisplayServer.window_set_title(title)
