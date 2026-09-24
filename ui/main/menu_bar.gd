class_name MainMenuBar
extends MenuBar
## The main menu, built from [code]Actions[/code]. An empty id is a separator.

const POPUP_THEME := preload("res://resources/themes/popup_menu_theme.tres")
const MENUS := {
	"File":
	[
		&"new",
		&"open",
		&"open_recent",
		&"",
		&"save",
		&"save_as",
		&"",
		&"export",
		&"",
		&"add_sprites",
		&"add_folder",
		&"add_spritesheet",
		&"",
		&"settings",
		&"quit",
	],
	"Edit":
	[
		&"undo",
		&"redo",
		&"",
		&"cut",
		&"copy",
		&"paste",
		&"duplicate",
		&"delete_frames",
		&"",
		&"select_all",
		&"select_none",
	],
	"Frame":
	[
		&"flip_h",
		&"flip_v",
		&"rotate_cw",
		&"rotate_ccw",
		&"",
		&"trim",
		&"color_key",
		&"replace_image",
		&"",
		&"insert_cell",
		&"remove_cell",
		&"",
		&"name_row",
	],
	"View":
	[
		&"zoom_in",
		&"zoom_out",
		&"zoom_reset",
		&"zoom_fit",
		&"",
		&"toggle_animation",
		&"toggle_status_bar"
	],
	"Help": [&"show_shortcuts", &"", &"about"],
}

## Submenu of File, picked from with [signal RecentFilesMenu.file_chosen]
var recent_files := RecentFilesMenu.new()


func _ready() -> void:
	if Global.cli_mode:
		return
	# Actions are registered by the main scene, which is ready after its children
	build.call_deferred()


func build() -> void:
	for child in get_children():
		if child != recent_files:
			child.free()
	for title: String in MENUS:
		var popup := ActionPopupMenu.new()
		popup.name = title
		popup.theme = POPUP_THEME
		add_child(popup)
		var ids: Array[StringName] = []
		ids.assign(MENUS[title])
		popup.set_actions(ids, {&"open_recent": ["Open Recent", recent_files]})
