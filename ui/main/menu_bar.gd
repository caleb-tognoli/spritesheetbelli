class_name MainMenuBar
extends MenuBar
## The main menu, built from [code]Actions[/code]. An empty id is a separator.

const POPUP_THEME := preload("res://resources/themes/popup_menu_theme.tres")
const MENUS := {
	"File":
	[
		&"new",
		&"open",
		&"",
		&"save",
		&"save_as",
		&"",
		&"export_image",
		&"export_image_as",
		&"export_sprites",
		&"",
		&"add_sprites",
		&"add_folder",
		&"add_spritesheet",
		&"",
		&"quit",
	],
	"Edit":
	[
		&"undo",
		&"redo",
		&"",
		&"select_all",
		&"select_none",
		&"",
		&"flip_h",
		&"flip_v",
		&"rotate_cw",
		&"rotate_ccw",
		&"",
		&"delete_frames",
	],
	"View": [&"zoom_in", &"zoom_out", &"zoom_reset", &"zoom_fit"],
	"Help": [&"show_shortcuts"],
}


func _ready() -> void:
	# Actions are registered by the main scene, which is ready after its children
	build.call_deferred()


func build() -> void:
	for child in get_children():
		child.free()
	for title: String in MENUS:
		var popup := ActionPopupMenu.new()
		popup.name = title
		popup.theme = POPUP_THEME
		add_child(popup)
		var ids: Array[StringName] = []
		ids.assign(MENUS[title])
		popup.set_actions(ids)
