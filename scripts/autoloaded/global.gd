extends Node
## Holds the open document and keeps the window title in sync with it.

var document := Document.new()
## True when started from the command line to pack or export, without the window
var cli_mode := false
## The open document's spritesheet
var spritesheet: Spritesheet:
	get:
		return document.spritesheet


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if Cli.is_cli(args):
		cli_mode = true
		get_tree().quit(await Cli.run(args))
		return
	document.reset()
	document.changed.connect(update_window_title)
	update_window_title()
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"ui_scale":
				apply_ui_scale()
			elif key in [&"theme", &"accent_color"]:
				apply_theme()
	)
	apply_ui_scale()
	apply_theme()


## Frees the nodes held in [param holder]'s variables that were never added to the tree,
## such as dialogs when the command line quits before the window is set up
func free_unused_nodes(holder: Object) -> void:
	for property in holder.get_property_list():
		if property.type != TYPE_OBJECT:
			continue
		var value: Variant = holder.get(property.name)
		if value is Node and is_instance_valid(value) and (value as Node).get_parent() == null:
			(value as Node).free()


## Fills the project theme (an empty resource in project.godot) with the generated one,
## so every control and window uses it, whatever its parents are
func apply_theme() -> void:
	var light: bool = Settings.get_value(&"theme") == "light"
	var project_theme := ThemeDB.get_project_theme()
	if project_theme == null:
		return
	project_theme.clear()
	project_theme.merge_with(AppTheme.build(light, Settings.get_value(&"accent_color")))
	get_tree().root.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)


## Scales the whole interface; "Automatic" follows the screen's scale
func apply_ui_scale() -> void:
	var ui_scale: float = Settings.get_value(&"ui_scale")
	if ui_scale <= 0:
		ui_scale = DisplayServer.screen_get_scale()
	get_tree().root.content_scale_factor = ui_scale


func update_window_title() -> void:
	DisplayServer.window_set_title(get_window_title(document))


## Like "(*) walk.png - spritesheetbelli 1.0", with "(*)" for unsaved changes and
## "Untitled" for a document that isn't named after any file
static func get_window_title(doc: Document) -> String:
	var title := "(*) " if doc.is_dirty else ""
	var display_name := doc.get_display_name()
	title += display_name if display_name else TranslationServer.translate("Untitled")
	title += " - " + ProjectSettings.get_setting("application/config/name")
	title += " " + ProjectSettings.get_setting("application/config/version", "")
	return title
