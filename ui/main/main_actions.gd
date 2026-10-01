class_name MainActions
extends RefCounted
## The actions of the main window's menus, toolbar and shortcuts, with their icons and
## descriptions: files, editing frames and cells, rows, the view and help. The layout
## controller (see [LayoutController]) and [AnimationCommands] register their own.

const SAVE_ICON := preload("res://assets/icons/Save.svg")
const RELOAD_ICON := preload("res://assets/icons/Reload.svg")
## Icons of actions, also borrowed by the actions of [LayoutController]
const ICONS := {
	&"new": preload("res://assets/icons/New.svg"),
	&"open": preload("res://assets/icons/Load.svg"),
	&"save": SAVE_ICON,
	&"save_as": SAVE_ICON,
	&"export": preload("res://assets/icons/ExternalLink.svg"),
	&"add_spritesheet": preload("res://assets/icons/SpriteSheet.svg"),
	&"add_sprites": preload("res://assets/icons/Add.svg"),
	&"add_folder": preload("res://assets/icons/FolderAdd.svg"),
	&"settings": preload("res://assets/icons/Tools.svg"),
	&"undo": preload("res://assets/icons/Undo.svg"),
	&"redo": preload("res://assets/icons/Redo.svg"),
	&"cut": preload("res://assets/icons/ActionCut.svg"),
	&"copy": preload("res://assets/icons/ActionCopy.svg"),
	&"paste": preload("res://assets/icons/ActionPaste.svg"),
	&"duplicate": preload("res://assets/icons/Duplicate.svg"),
	&"select_all": PreviewArea.SELECT_ALL_ICON,
	&"select_none": PreviewArea.SELECT_NONE_ICON,
	&"tool_select": PreviewArea.SELECT_ICON,
	&"tool_move": PreviewArea.MOVE_ICON,
	&"flip_h": preload("res://assets/icons/MirrorX.svg"),
	&"flip_v": preload("res://assets/icons/MirrorY.svg"),
	&"rotate_cw": preload("res://assets/icons/RotateRight.svg"),
	&"rotate_ccw": preload("res://assets/icons/RotateLeft.svg"),
	&"color_key": preload("res://assets/icons/ColorPick.svg"),
	&"replace_image": preload("res://assets/icons/Image.svg"),
	&"reload_source": RELOAD_ICON,
	&"insert_cell": preload("res://assets/icons/InsertBefore.svg"),
	&"remove_cell": preload("res://assets/icons/RemoveInternal.svg"),
	&"delete_frames": preload("res://assets/icons/Remove.svg"),
	&"zoom_in": PreviewArea.ZOOM_IN_ICON,
	&"zoom_out": PreviewArea.ZOOM_OUT_ICON,
	&"zoom_reset": preload("res://assets/icons/ZoomReset.svg"),
	&"zoom_fit": preload("res://assets/icons/CenterView.svg"),
	&"edit_animations": preload("res://assets/icons/Animation.svg"),
	&"export_again": RELOAD_ICON,
	&"align_top": preload("res://assets/icons/ControlAlignCenterTop.svg"),
	&"align_bottom": preload("res://assets/icons/ControlAlignCenterBottom.svg"),
	&"align_left": preload("res://assets/icons/ControlAlignCenterLeft.svg"),
	&"align_right": preload("res://assets/icons/ControlAlignCenterRight.svg"),
	&"align_center": preload("res://assets/icons/ControlAlignCenter.svg"),
	&"add_outline": preload("res://assets/icons/Rectangle.svg"),
	&"trim": preload("res://assets/icons/RegionEdit.svg"),
	&"toggle_grid": preload("res://assets/icons/GridToggle.svg"),
	&"toggle_indices": preload("res://assets/icons/FrameNumbers.svg"),
	&"toggle_animation": preload("res://assets/icons/AnimatedTexture.svg"),
	&"toggle_history": preload("res://assets/icons/History.svg"),
	&"insert_row": preload("res://assets/icons/ExpandTree.svg"),
	&"remove_row": preload("res://assets/icons/CollapseTree.svg"),
	&"move_row_up": preload("res://assets/icons/MoveUp.svg"),
	&"move_row_down": preload("res://assets/icons/MoveDown.svg"),
	&"about": preload("res://assets/icons/Info.svg"),
	&"show_shortcuts": preload("res://assets/icons/Keyboard.svg"),
	&"command_palette": preload("res://assets/icons/Search.svg"),
	&"tool_pivot": PreviewArea.PIVOT_ICON,
	&"layout_grid": preload("res://assets/icons/LayoutGrid.svg"),
	&"layout_packed": preload("res://assets/icons/LayoutPacked.svg"),
	&"pin_toggle": preload("res://assets/icons/Pin.svg"),
	&"repack": preload("res://assets/icons/GridLayout.svg"),
	&"pivot_clear": preload("res://assets/icons/Clear.svg"),
	&"pivot_top_left": preload("res://assets/icons/ControlAlignTopLeft.svg"),
	&"pivot_bottom_left": preload("res://assets/icons/ControlAlignBottomLeft.svg"),
}
## What tooltips say after an action's name and shortcut, see [member AppAction.description]
const DESCRIPTIONS := {  # L10n.mark
	&"export": "The spritesheet as an image, as sprites or for a game engine",
	&"export_again": "Every export of the project, or else the Export dialog",
	&"add_spritesheet": "Cut a spritesheet image into frames and add them",
	&"add_sprites": "Image files as sprites",
	&"add_folder": "A folder's images as sprites, and the ones saved there later",
	&"tool_select": "Click or drag to select frames",
	&"tool_move":
	(
		"Drag to move the selected frames, or the dragged one; Alt+drag copies. Arrow keys "
		+ "move the selected frames inside their cells."
	),
	&"trim": "Of the selected frames, or of every frame when none are selected",
	&"color_key": "From the selected frames, or from every frame when none are selected",
}


## Registers the actions of [param main] (the main window), in menu order
static func register(main: Control) -> void:
	var sheet := Global.spritesheet
	var files: FileController = main.files
	var preview_area: PreviewArea = main.preview_area
	var preview: SpritesheetPreview = main.preview
	var clipboard: FrameClipboard = main.clipboard
	var status_bar: Control = main.status_bar
	var history_panel: HistoryPanel = main.history_panel
	var animation_panel: AnimationPanel = main.animation_panel
	var has_frames := func() -> bool: return not sheet.is_empty()
	var has_selection := func() -> bool: return not preview.get_selected_coords().is_empty()
	var add := func(id: StringName, label: String, run: Callable, can_run := Callable()) -> void:
		Actions.add(id, label, run, can_run, ICONS.get(id))

	add.call(&"new", L10n.mark("New"), files.new_spritesheet)
	add.call(&"open", L10n.mark("Open…"), files.open_spritesheet)
	add.call(&"save", L10n.mark("Save"), files.save, has_frames)
	add.call(&"save_as", L10n.mark("Save As…"), files.save_as, has_frames)
	add.call(
		&"export",
		L10n.mark("Export…"),
		func() -> void: (main.export_dialog as ExportDialog).popup_centered(),
		has_frames
	)
	add.call(&"export_again", L10n.mark("Export Again"), files.exports.export_again, has_frames)
	add.call(
		&"add_spritesheet",
		L10n.mark("Add Spritesheet…"),
		files.popup_file_dialog.bind(files.open_spritesheet_dialog)
	)
	add.call(
		&"add_sprites",
		L10n.mark("Add Sprite(s)…"),
		files.popup_file_dialog.bind(files.open_sprites_dialog)
	)
	add.call(
		&"add_folder",
		L10n.mark("Add Folder…"),
		files.popup_file_dialog.bind(files.open_folder_dialog)
	)
	add.call(
		&"settings",
		L10n.mark("Settings…"),
		func() -> void: (main.settings_window as SettingsWindow).popup_centered()
	)
	add.call(
		&"quit",
		L10n.mark("Quit"),
		func() -> void:
			files.confirm_unsaved_changes(
				L10n.mark("Save changes to %s before quitting?"), main.get_tree().quit
			)
	)

	for tool: Array in [
		[&"tool_select", L10n.mark("Select Mode"), SpritesheetPreview.Tool.SELECT],
		[&"tool_move", L10n.mark("Move Mode"), SpritesheetPreview.Tool.MOVE],
	]:
		Actions.add(
			tool[0],
			tool[1],
			preview_area.set_tool.bind(tool[2]),
			Callable(),
			ICONS[tool[0]],
			func() -> bool: return preview.tool == tool[2]
		)
	add.call(&"select_all", L10n.mark("Select All"), preview_area.select_all.bind(true), has_frames)
	add.call(
		&"select_none", L10n.mark("Select None"), preview_area.select_all.bind(false), has_selection
	)
	add.call(
		&"flip_h",
		L10n.mark("Flip Horizontally"),
		main.edit_selection.bind(L10n.mark("Flip"), _edit_with(FrameEdits.flip, [true])),
		has_selection
	)
	add.call(
		&"flip_v",
		L10n.mark("Flip Vertically"),
		main.edit_selection.bind(L10n.mark("Flip"), _edit_with(FrameEdits.flip, [false])),
		has_selection
	)
	add.call(
		&"rotate_cw",
		L10n.mark("Rotate 90° CW"),
		main.edit_selection.bind(L10n.mark("Rotate"), _edit_with(FrameEdits.rotate, [true])),
		has_selection
	)
	add.call(
		&"rotate_ccw",
		L10n.mark("Rotate 90° CCW"),
		main.edit_selection.bind(L10n.mark("Rotate"), _edit_with(FrameEdits.rotate, [false])),
		has_selection
	)
	add.call(
		&"delete_frames",
		L10n.mark("Delete"),
		main.edit_selection.bind(L10n.mark("Delete"), sheet.remove_frames),
		has_selection
	)

	add.call(&"copy", L10n.mark("Copy"), main.copy_selection, has_selection)
	add.call(
		&"cut",
		L10n.mark("Cut"),
		func() -> void:
			main.copy_selection()
			main.edit_selection(L10n.mark("Cut"), sheet.remove_frames),
		has_selection
	)
	add.call(
		&"paste",
		L10n.mark("Paste"),
		func() -> void: main.add_cells(L10n.mark("Paste"), clipboard.get_cells()),
		clipboard.has_content
	)
	add.call(
		&"duplicate",
		L10n.mark("Duplicate"),
		func() -> void: main.add_cells(L10n.mark("Duplicate"), main.get_selected_cells()),
		has_selection
	)
	add.call(
		&"trim",
		L10n.mark("Trim Transparent Borders"),
		main.edit_targets.bind(L10n.mark("Trim"), _edit_with(FrameEdits.trim)),
		has_frames
	)
	for align: Array in [
		[&"align_top", L10n.mark("Top"), Spritesheet.Alignment.TOP],
		[&"align_bottom", L10n.mark("Bottom"), Spritesheet.Alignment.BOTTOM],
		[&"align_left", L10n.mark("Left"), Spritesheet.Alignment.LEFT],
		[&"align_right", L10n.mark("Right"), Spritesheet.Alignment.RIGHT],
		[&"align_center", L10n.mark("Centre"), Spritesheet.Alignment.CENTER],
	]:
		add.call(
			align[0],
			align[1],
			main.edit_targets.bind(L10n.mark("Align"), _edit_with(FrameEdits.align, [align[2]])),
			has_frames
		)
	add.call(
		&"color_key",
		L10n.mark("Remove Background Colour…"),
		(main.color_key as ColorKeyPreview).open,
		has_frames
	)
	add.call(
		&"add_outline",
		L10n.mark("Add Outline…"),
		func() -> void: (main.outline_dialog as OutlineDialog).popup_centered(),
		has_selection
	)
	add.call(
		&"replace_image",
		L10n.mark("Replace Image…"),
		func() -> void: files.replace_frame_image(preview.get_selected_coords()[0]),
		func() -> bool: return preview.get_selected_coords().size() == 1
	)
	add.call(
		&"reload_source",
		L10n.mark("Reload from File"),
		func() -> void:
			(main.source_watcher as SourceWatcher).reload_frames(
				main.get_selected_linked_coords(), true, L10n.mark("Reload from file")
			),
		func() -> bool: return not main.get_selected_linked_coords().is_empty()
	)
	add.call(
		&"insert_cell",
		L10n.mark("Insert Empty Cell"),
		func() -> void:
			var coord := preview.get_selected_coords()[0]
			Global.document.perform(L10n.mark("Insert cell"), sheet.insert_empty_cell.bind(coord)),
		has_selection
	)
	add.call(
		&"remove_cell",
		L10n.mark("Remove Cell"),
		func() -> void:
			var coords := preview.get_selected_coords()
			coords.reverse()
			Global.document.perform(
				L10n.mark("Remove cells"),
				func() -> void:
					for coord in coords:
						sheet.remove_cell(coord)
			),
		has_selection
	)

	add.call(
		&"insert_row",
		L10n.mark("Insert Row"),
		func() -> void:
			var row := preview.get_selected_coords()[0].y
			var moved: Array[Vector2i] = []
			for coord in preview.get_selected_coords():
				moved.append(coord + Vector2i.DOWN if coord.y >= row else coord)
			Global.document.perform(L10n.mark("Insert row"), sheet.insert_row.bind(row))
			preview.set_selected_coords(moved),
		has_selection
	)
	add.call(
		&"remove_row",
		L10n.mark("Remove Row"),
		func() -> void:
			var rows := _selected_rows(preview)
			rows.reverse()
			preview.set_selected_coords([] as Array[Vector2i])
			Global.document.perform(
				L10n.mark("Remove rows"),
				func() -> void:
					for row in rows:
						sheet.remove_row(row)
			),
		has_selection
	)
	for move: Array in [
		[&"move_row_up", L10n.mark("Move Row Up"), -1],
		[&"move_row_down", L10n.mark("Move Row Down"), 1]
	]:
		add.call(
			move[0],
			move[1],
			func() -> void:
				var row := preview.get_selected_coords()[0].y
				var by: int = move[2]
				var moved: Array[Vector2i] = []
				for coord in preview.get_selected_coords():
					moved.append(coord + Vector2i(0, by) if coord.y == row else coord)
				Global.document.perform(L10n.mark("Move row"), sheet.move_row.bind(row, by))
				preview.set_selected_coords(moved),
			func() -> bool:
				if preview.get_selected_coords().is_empty():
					return false
				var target: int = preview.get_selected_coords()[0].y + move[2]
				return target >= 0 and target < sheet.grid_size.y
		)

	add.call(&"zoom_in", L10n.mark("Zoom In"), preview.zoom_by.bind(1.25))
	add.call(&"zoom_out", L10n.mark("Zoom Out"), preview.zoom_by.bind(0.8))
	add.call(&"zoom_reset", L10n.mark("Actual Size"), preview.reset_zoom)
	add.call(&"zoom_fit", L10n.mark("Fit to View"), preview.fit_to_view)
	Actions.add(
		&"toggle_status_bar",
		L10n.mark("Status Bar"),
		func() -> void: Settings.set_value(&"show_status_bar", not status_bar.visible),
		Callable(),
		null,
		func() -> bool: return status_bar.visible
	)
	Actions.add(
		&"toggle_history",
		L10n.mark("History"),
		func() -> void: Settings.set_value(&"show_history", not history_panel.visible),
		Callable(),
		ICONS[&"toggle_history"],
		func() -> bool: return history_panel.visible
	)
	add.call(&"edit_animations", L10n.mark("Edit"), animation_panel.edit, has_frames)
	Actions.add(
		&"toggle_animation",
		L10n.mark("Animation Panel"),
		animation_panel.toggle,
		Callable(),
		ICONS[&"toggle_animation"],
		animation_panel.is_expanded
	)
	for toggle: Array in [
		[&"toggle_grid", L10n.mark("Grid Lines"), &"show_grid"],
		[&"toggle_pixel_grid", L10n.mark("Pixel Grid"), &"show_pixel_grid"],
		[&"toggle_indices", L10n.mark("Frame Numbers"), &"show_indices"],
	]:
		Actions.add(
			toggle[0],
			toggle[1],
			func() -> void: Settings.set_value(toggle[2], not Settings.get_value(toggle[2])),
			Callable(),
			ICONS.get(toggle[0]),
			func() -> bool: return Settings.get_value(toggle[2])
		)

	add.call(&"undo", L10n.mark("Undo"), Global.document.undo, Global.document.can_undo)
	add.call(&"redo", L10n.mark("Redo"), Global.document.redo, Global.document.can_redo)

	add.call(
		&"about",
		L10n.mark("About spritesheetbelli"),
		func() -> void: (main.about_dialog as AboutDialog).popup_centered()
	)
	add.call(
		&"show_shortcuts",
		L10n.mark("Keyboard Shortcuts"),
		func() -> void: (main.shortcuts_dialog as ShortcutsDialog).popup_centered()
	)
	add.call(
		&"command_palette",
		L10n.mark("Command Palette…"),
		(main.command_palette as CommandPalette).open.bind(preview_area)
	)
	for id: StringName in DESCRIPTIONS:
		Actions.get_action(id).description = DESCRIPTIONS[id]


## Rows with a frame selected in [param preview], from top to bottom
static func _selected_rows(preview: SpritesheetPreview) -> Array[int]:
	var rows: Array[int] = []
	for coord in preview.get_selected_coords():
		if coord.y not in rows:
			rows.append(coord.y)
	rows.sort()
	return rows


## [param edit] from [FrameEdits] for the main window's [code]edit_selection()[/code], with
## [param args] after the coordinates
static func _edit_with(edit: Callable, args := []) -> Callable:
	return func(coords: Array[Vector2i]) -> void: edit.callv([Global.spritesheet, coords] + args)
