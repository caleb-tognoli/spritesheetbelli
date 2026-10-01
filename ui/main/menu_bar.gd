class_name MainMenuBar
extends MenuBar
## The main menu, built from [code]Actions[/code]. An empty id is a separator.

const POPUP_THEME := preload("res://resources/themes/popup_menu_theme.tres")
## Submenus of actions, shown when hovering them: [code][label, action ids, icon][/code],
## and for a toolbar button that opens one, a description for its tooltip
const SUBMENUS := {  # L10n.mark
	&"transform_menu":
	[
		"Transform",
		[&"flip_h", &"flip_v", &"", &"rotate_cw", &"rotate_ccw"],
		preload("res://assets/icons/ToolRotate.svg"),
	],
	&"align_menu":
	[
		"Align in Cell",
		[&"align_top", &"align_bottom", &"align_left", &"align_right", &"align_center"],
		preload("res://assets/icons/ControlAlignCenter.svg"),
		"Of the selected frames, or of every frame when none are selected",
	],
	&"pivot_menu":
	[
		"Pivot",
		[
			&"pivot_center",
			&"pivot_top",
			&"pivot_bottom",
			&"pivot_left",
			&"pivot_right",
			&"pivot_top_left",
			&"pivot_bottom_left",
			&"",
			&"pivot_clear",
		],
		preload("res://assets/icons/EditPivot.svg"),
		"Of the selected frames, or of every frame when none are selected",
	],
	&"rows_menu":
	[
		"Rows",
		[&"insert_row", &"remove_row", &"", &"move_row_up", &"move_row_down"],
		preload("res://assets/icons/Panels2.svg"),
	],
	&"animation_menu":
	[
		"Animation",
		[&"animation_from_row", &"animation_from_column", &"animation_from_selection"],
		preload("res://assets/icons/Animation.svg"),
	],
}
const MENUS := {  # L10n.mark
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
		&"export_again",
		&"",
		&"add_spritesheet",
		&"add_sprites",
		&"add_folder",
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
		&"align_menu",
		&"pivot_menu",
		&"trim",
		&"color_key",
		&"add_outline",
		&"replace_image",
		&"reload_source",
		&"",
		&"insert_cell",
		&"remove_cell",
		&"rows_menu",
		&"",
		&"pin_toggle",
		&"repack",
	],
	"Animation":
	[
		&"animation_from_row",
		&"animation_from_column",
		&"animation_from_selection",
		&"",
		&"edit_animations",
		&"duplicate_animation",
		&"mirror_animation",
		&"delete_animation",
		&"",
		&"toggle_animation",
		&"toggle_onion_skin",
		&"animation_labels",
	],
	"View":
	[
		&"layout_grid",
		&"layout_packed",
		&"",
		&"zoom_in",
		&"zoom_out",
		&"zoom_reset",
		&"zoom_fit",
		&"",
		&"toggle_grid",
		&"toggle_pixel_grid",
		&"toggle_indices",
		&"toggle_sprites",
		&"toggle_history",
		&"toggle_status_bar"
	],
	"Help": [&"command_palette", &"show_shortcuts", &"", &"about"],
}

## Submenu of File, picked from with [signal RecentFilesMenu.file_chosen]
var recent_files := RecentFilesMenu.new()


func _ready() -> void:
	if Global.cli_mode:
		Global.free_unused_nodes(self)
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
		var submenus := SUBMENUS.duplicate()
		submenus[&"open_recent"] = [L10n.mark("Open Recent"), recent_files]
		popup.set_actions(ids, submenus)
