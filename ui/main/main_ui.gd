extends Control

const SAVE_ICON := preload("res://assets/icons/Save.svg")
const LINK_ICON := preload("res://assets/icons/Link.svg")
const UNLINK_ICON := preload("res://assets/icons/Unlink.svg")
const RELOAD_ICON := preload("res://assets/icons/Reload.svg")
const ICONS := {
	&"new": preload("res://assets/icons/New.svg"),
	&"open": preload("res://assets/icons/Load.svg"),
	&"save": SAVE_ICON,
	&"save_as": SAVE_ICON,
	&"export": preload("res://assets/icons/ExternalLink.svg"),
	&"add_sprites": preload("res://assets/icons/Add.svg"),
	&"add_folder": preload("res://assets/icons/Folder.svg"),
	&"add_spritesheet": preload("res://assets/icons/SpriteSheet.svg"),
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
	&"name_row": preload("res://assets/icons/Rename.svg"),
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
	&"insert_row": preload("res://assets/icons/ExpandTree.svg"),
	&"remove_row": preload("res://assets/icons/CollapseTree.svg"),
	&"move_row_up": preload("res://assets/icons/MoveUp.svg"),
	&"move_row_down": preload("res://assets/icons/MoveDown.svg"),
	&"about": preload("res://assets/icons/Info.svg"),
	&"show_shortcuts": preload("res://assets/icons/Keyboard.svg"),
	&"tool_pivot": PreviewArea.PIVOT_ICON,
	&"layout_grid": preload("res://assets/icons/LayoutGrid.svg"),
	&"layout_packed": preload("res://assets/icons/LayoutPacked.svg"),
	&"pin_toggle": preload("res://assets/icons/Pin.svg"),
	&"repack": RELOAD_ICON,
	&"pivot_clear": preload("res://assets/icons/Clear.svg"),
}
## Pixels to scale before it's done on worker threads behind a progress bar
const SLOW_SCALE_WORK := 1_000_000
## Action buttons in the toolbar, in groups, and the view toggles next to the zoom
const TOOLBAR_GROUPS := [
	[&"flip_h", &"flip_v", &"rotate_ccw", &"rotate_cw"],
	[&"align_menu", &"pivot_menu", &"trim"],
	[&"pin_toggle", &"repack"],
]
const TOOLBAR_TOGGLES: Array[StringName] = [
	&"layout_grid", &"layout_packed", &"toggle_grid", &"toggle_indices", &"toggle_animation"
]
## Actions offered when right-clicking frames
const CONTEXT_ACTIONS: Array[StringName] = [
	&"cut",
	&"copy",
	&"paste",
	&"duplicate",
	&"",
	&"transform_menu",
	&"align_menu",
	&"pivot_menu",
	&"",
	&"insert_cell",
	&"remove_cell",
	&"rows_menu",
	&"pin_toggle",
	&"",
	&"delete_frames",
]

@onready var files: FileController = $Files
@onready var preview_area: PreviewArea = %PreviewArea
@onready var grid_rows: SpinBox = %GridRows
@onready var grid_columns: SpinBox = %GridColumns
@onready var sprite_width: SpinBox = %SpriteWidth
@onready var sprite_height: SpinBox = %SpriteHeight
@onready var keep_ratio_btn: Button = %KeepRatio
@onready var half_size_btn: Button = %HalfSize
@onready var double_size_btn: Button = %DoubleSize
@onready var triple_size_btn: Button = %TripleSize
@onready var original_size_btn: Button = %OriginalSize
@onready var resize_filter: OptionButton = %ResizeFilter
@onready var add_sprites_btn: Button = %AddSprites
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var sheet_size: Label = %SheetSize
@onready var export_btn: Button = %Export
@onready var split: HSplitContainer = %Split
@onready var preview_split: HSplitContainer = %PreviewSplit
@onready var history_panel: HistoryPanel = %HistoryPanel
@onready var status_bar: Control = %StatusBar
@onready var sheet_info: Label = %SheetInfo
@onready var cell_info: Label = %CellInfo
@onready var legend: Label = %Legend
@onready var preview: SpritesheetPreview = preview_area.spritesheet_preview

var shortcuts_dialog := ShortcutsDialog.new()
var settings_window := SettingsWindow.new()
var clipboard := FrameClipboard.new()
var color_key_dialog := ColorKeyDialog.new()
var outline_dialog := OutlineDialog.new()
var row_name_dialog := RowNameDialog.new()
var export_dialog := ExportDialog.new()
var about_dialog := AboutDialog.new()
var animation_window := AnimationWindow.new()
var source_watcher := SourceWatcher.new()
var layout_controller := LayoutController.new()
var _was_empty := true


func _ready() -> void:
	# The command line doesn't need the window
	if Global.cli_mode:
		Global.free_unused_nodes(self)
		queue_free()
		return
	# 0 is only shown while the spritesheet is empty
	for field: SpinBox in [grid_rows, grid_columns, sprite_width, sprite_height]:
		field.min_value = 0
		SpinScroll.enable(field)
	preview_area.spritesheet_preview.spritesheet = Global.spritesheet
	add_child(layout_controller)
	layout_controller.setup(self)
	set_text_params(Global.spritesheet)
	disable_if_empty()

	Global.spritesheet.updated.connect(set_text_params.bind(Global.spritesheet))
	Global.spritesheet.updated.connect(disable_if_empty)
	Global.spritesheet.updated.connect(_prepare_scaled_images)
	add_sprites_btn.pressed.connect(Actions.run.bind(&"add_sprites"))
	add_spritesheet_btn.pressed.connect(Actions.run.bind(&"add_spritesheet"))
	export_btn.pressed.connect(Actions.run.bind(&"export"))
	export_btn.icon = ICONS[&"export"]
	get_window().min_size = Vector2i(820, 520)
	split.split_offset = Settings.get_value(&"sidebar_width")
	split.dragged.connect(func(offset: int) -> void: Settings.set_value(&"sidebar_width", offset))
	status_bar.visible = Settings.get_value(&"show_status_bar")
	history_panel.visible = Settings.get_value(&"show_history")
	# The split offset is from the preview's side, so a wider history is a negative offset
	preview_split.split_offset = Settings.get_value(&"history_width")
	preview_split.dragged.connect(
		func(offset: int) -> void: Settings.set_value(&"history_width", offset)
	)
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"show_status_bar":
				status_bar.visible = Settings.get_value(key)
			elif key == &"show_history":
				history_panel.visible = Settings.get_value(key)
				Actions.refresh()
	)
	preview.hover_changed.connect(update_cell_info)
	grid_rows.value_changed.connect(
		func(rows: float) -> void:
			set_spritesheet_grid_size(Global.spritesheet.grid_size.x, int(rows))
	)
	grid_columns.value_changed.connect(
		func(columns: float) -> void:
			set_spritesheet_grid_size(int(columns), Global.spritesheet.grid_size.y)
	)
	sprite_width.value_changed.connect(func(width: float) -> void: set_sprite_size(int(width), -1))
	sprite_height.value_changed.connect(
		func(height: float) -> void: set_sprite_size(-1, int(height))
	)
	half_size_btn.pressed.connect(scale_sprites.bind(0.5))
	double_size_btn.pressed.connect(scale_sprites.bind(2.0))
	triple_size_btn.pressed.connect(scale_sprites.bind(3.0))
	original_size_btn.pressed.connect(
		func() -> void:
			Global.document.perform(
				"Original size", Global.spritesheet.set_frame_scale.bind(Vector2.ONE)
			)
	)
	resize_filter.item_selected.connect(
		func(filter: int) -> void:
			var sheet := Global.spritesheet
			Global.document.perform(
				"Resize filter", sheet.set_frame_scale.bind(sheet.frame_scale, filter)
			)
	)
	# Clicking the Filter label opens the list, like clicking the list itself
	LabelLink.link(resize_filter.get_parent().get_child(0) as Label, resize_filter)
	keep_ratio_btn.toggled.connect(
		func(on: bool) -> void: keep_ratio_btn.icon = LINK_ICON if on else UNLINK_ICON
	)
	get_tree().auto_accept_quit = false
	add_child(shortcuts_dialog)
	add_child(settings_window)
	add_child(color_key_dialog)
	add_child(outline_dialog)
	add_child(row_name_dialog)
	add_child(export_dialog)
	export_dialog.export_requested.connect(files.choose_export_path)
	add_child(about_dialog)
	add_child(source_watcher)
	animation_window.preview = preview
	add_child(animation_window)
	var animation_preview := preview_area.animation_preview
	animation_preview.details_requested.connect(animation_window.open)
	# The small player follows the animation being edited
	animation_window.list.item_selected.connect(animation_preview.select_animation)
	row_name_dialog.name_chosen.connect(
		func(row: int, row_name: String) -> void:
			Global.document.perform("Name row", Global.spritesheet.set_row_name.bind(row, row_name))
	)
	preview.row_name_requested.connect(open_row_name_dialog)
	color_key_dialog.color_chosen.connect(remove_background)
	outline_dialog.outline_chosen.connect(add_outline)
	files.restore_session.call_deferred()
	files.get_selected_coords = preview.get_selected_coords
	(%MenuBar as MainMenuBar).recent_files.file_chosen.connect(files.open_recent)
	_register_actions()
	layout_controller.register_actions()
	preview_area.set_context_actions(CONTEXT_ACTIONS, MainMenuBar.SUBMENUS)
	preview_area.set_toolbar_actions(TOOLBAR_GROUPS, TOOLBAR_TOGGLES, MainMenuBar.SUBMENUS)
	preview_area.empty_hint.text = (
		"Drop images, folders or a .sbelli project here\n"
		+ "or use Add Sprite(s) and Add Spritesheet (Ctrl+I, Ctrl+Shift+I)"
	)
	preview_area.update_ui()
	preview.preview_updated.connect(Actions.refresh)
	preview.selection_changed.connect(update_sheet_info)
	# Show the whole sheet when frames first appear, e.g. after adding or opening
	Global.spritesheet.updated.connect(
		func() -> void:
			if _was_empty and not Global.spritesheet.is_empty():
				preview.fit_to_view.call_deferred()
			_was_empty = Global.spritesheet.is_empty()
	)
	preview.move_requested.connect(
		func(coords: Array[Vector2i], offset: Vector2i, copy: bool) -> void:
			var targets: Array[Vector2i] = Global.document.perform(
				"Copy frames" if copy else "Move frames",
				Global.spritesheet.move_frames.bind(coords, offset, copy)
			)
			preview.set_selected_coords(targets)
	)
	preview.nudge_requested.connect(
		func(coords: Array[Vector2i], offset: Vector2i) -> void:
			Global.document.perform(
				"Nudge frames", Global.spritesheet.nudge_frames.bind(coords, offset)
			)
	)
	preview.lock_requested.connect(
		func(coord: Vector2i, locked: bool) -> void:
			Global.document.perform(
				"Lock cell" if locked else "Unlock cell",
				Global.spritesheet.set_locked.bind(coord, locked)
			)
	)
	preview.placement_move_requested.connect(
		func(coords: Array[Vector2i], page: int, offset: Vector2i) -> void:
			var sheet := Global.spritesheet
			var places := PackedLayout.moved(sheet, coords, page, offset)
			if places:
				Global.document.perform("Move frames", sheet.set_placements.bind(places))
	)
	preview.pivot_requested.connect(
		func(coords: Array[Vector2i], pivot: Vector2) -> void:
			Global.document.perform("Set pivot", Global.spritesheet.set_pivots.bind(coords, pivot))
	)


func _register_actions() -> void:
	var sheet := Global.spritesheet
	var has_frames := func() -> bool: return not sheet.is_empty()
	var has_selection := func() -> bool: return not preview.get_selected_coords().is_empty()
	var add := func(id: StringName, label: String, run: Callable, can_run := Callable()) -> void:
		Actions.add(id, label, run, can_run, ICONS.get(id))

	add.call(&"new", "New", files.new_spritesheet)
	add.call(&"open", "Open…", files.open_spritesheet)
	add.call(&"save", "Save", files.save, has_frames)
	add.call(&"save_as", "Save As…", files.save_as, has_frames)
	add.call(&"export", "Export…", func() -> void: export_dialog.popup_centered(), has_frames)
	add.call(
		&"export_again",
		"Export Again",
		files.export_again,
		func() -> bool: return has_frames.call() and Global.document.last_export != ""
	)
	add.call(
		&"add_sprites", "Add Sprite(s)…", files.popup_file_dialog.bind(files.open_sprites_dialog)
	)
	add.call(&"add_folder", "Add Folder…", files.popup_file_dialog.bind(files.open_folder_dialog))
	add.call(
		&"add_spritesheet",
		"Add Spritesheet…",
		files.popup_file_dialog.bind(files.open_spritesheet_dialog)
	)
	add.call(&"settings", "Settings…", func() -> void: settings_window.popup_centered())
	add.call(
		&"quit", "Quit", func() -> void: files.confirm_unsaved_changes("quitting", get_tree().quit)
	)

	for tool: Array in [
		[&"tool_select", "Select Mode", SpritesheetPreview.Tool.SELECT],
		[&"tool_move", "Move Mode", SpritesheetPreview.Tool.MOVE],
	]:
		Actions.add(
			tool[0],
			tool[1],
			preview_area.set_tool.bind(tool[2]),
			Callable(),
			ICONS[tool[0]],
			func() -> bool: return preview.tool == tool[2]
		)
	add.call(&"select_all", "Select All", preview_area.select_all.bind(true), has_frames)
	add.call(&"select_none", "Select None", preview_area.select_all.bind(false), has_selection)
	add.call(
		&"flip_h",
		"Flip Horizontally",
		edit_selection.bind("Flip", _edit_with(FrameEdits.flip, [true])),
		has_selection
	)
	add.call(
		&"flip_v",
		"Flip Vertically",
		edit_selection.bind("Flip", _edit_with(FrameEdits.flip, [false])),
		has_selection
	)
	add.call(
		&"rotate_cw",
		"Rotate 90° CW",
		edit_selection.bind("Rotate", _edit_with(FrameEdits.rotate, [true])),
		has_selection
	)
	add.call(
		&"rotate_ccw",
		"Rotate 90° CCW",
		edit_selection.bind("Rotate", _edit_with(FrameEdits.rotate, [false])),
		has_selection
	)
	add.call(
		&"delete_frames",
		"Delete",
		edit_selection.bind("Delete", sheet.remove_frames),
		has_selection
	)

	add.call(&"copy", "Copy", copy_selection, has_selection)
	add.call(
		&"cut",
		"Cut",
		func() -> void:
			copy_selection()
			edit_selection("Cut", sheet.remove_frames),
		has_selection
	)
	add.call(
		&"paste",
		"Paste",
		func() -> void: add_cells("Paste", clipboard.get_cells()),
		clipboard.has_content
	)
	add.call(
		&"duplicate",
		"Duplicate",
		func() -> void: add_cells("Duplicate", get_selected_cells()),
		has_selection
	)
	add.call(
		&"trim",
		"Trim Transparent Borders",
		edit_selection.bind("Trim", _edit_with(FrameEdits.trim)),
		has_selection
	)
	for align: Array in [
		[&"align_top", "Top", Spritesheet.Alignment.TOP],
		[&"align_bottom", "Bottom", Spritesheet.Alignment.BOTTOM],
		[&"align_left", "Left", Spritesheet.Alignment.LEFT],
		[&"align_right", "Right", Spritesheet.Alignment.RIGHT],
		[&"align_center", "Centre", Spritesheet.Alignment.CENTER],
	]:
		add.call(
			align[0],
			align[1],
			edit_selection.bind("Align", _edit_with(FrameEdits.align, [align[2]])),
			has_selection
		)
	add.call(
		&"color_key",
		"Remove Background Colour…",
		func() -> void: color_key_dialog.open(sheet.frames[preview.get_selected_coords()[0]]),
		has_selection
	)
	add.call(
		&"add_outline",
		"Add Outline…",
		func() -> void: outline_dialog.popup_centered(),
		has_selection
	)
	add.call(
		&"name_row",
		"Name Row…",
		func() -> void: open_row_name_dialog(preview.get_selected_coords()[0].y),
		has_selection
	)
	add.call(
		&"replace_image",
		"Replace Image…",
		func() -> void: files.replace_frame_image(preview.get_selected_coords()[0]),
		func() -> bool: return preview.get_selected_coords().size() == 1
	)
	add.call(
		&"reload_source",
		"Reload from File",
		func() -> void:
			source_watcher.reload_frames(get_selected_linked_coords(), true, "Reload from file"),
		func() -> bool: return not get_selected_linked_coords().is_empty()
	)
	add.call(
		&"insert_cell",
		"Insert Empty Cell",
		func() -> void:
			var coord := preview.get_selected_coords()[0]
			Global.document.perform("Insert cell", sheet.insert_empty_cell.bind(coord)),
		has_selection
	)
	add.call(
		&"remove_cell",
		"Remove Cell",
		func() -> void:
			var coords := preview.get_selected_coords()
			coords.reverse()
			Global.document.perform(
				"Remove cells",
				func() -> void:
					for coord in coords:
						sheet.remove_cell(coord)
			),
		has_selection
	)

	add.call(
		&"insert_row",
		"Insert Row",
		func() -> void:
			var row := preview.get_selected_coords()[0].y
			var moved: Array[Vector2i] = []
			for coord in preview.get_selected_coords():
				moved.append(coord + Vector2i.DOWN if coord.y >= row else coord)
			Global.document.perform("Insert row", sheet.insert_row.bind(row))
			preview.set_selected_coords(moved),
		has_selection
	)
	add.call(
		&"remove_row",
		"Remove Row",
		func() -> void:
			var rows := _selected_rows()
			rows.reverse()
			preview.set_selected_coords([] as Array[Vector2i])
			Global.document.perform(
				"Remove rows",
				func() -> void:
					for row in rows:
						sheet.remove_row(row)
			),
		has_selection
	)
	for move: Array in [
		[&"move_row_up", "Move Row Up", -1], [&"move_row_down", "Move Row Down", 1]
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
				Global.document.perform("Move row", sheet.move_row.bind(row, by))
				preview.set_selected_coords(moved),
			func() -> bool:
				if preview.get_selected_coords().is_empty():
					return false
				var target: int = preview.get_selected_coords()[0].y + move[2]
				return target >= 0 and target < sheet.grid_size.y
		)

	add.call(&"zoom_in", "Zoom In", preview.zoom_by.bind(1.25))
	add.call(&"zoom_out", "Zoom Out", preview.zoom_by.bind(0.8))
	add.call(
		&"zoom_reset",
		"Actual Size",
		func() -> void: preview.set_zoom(1, preview.get_viewport_rect().size / 2)
	)
	add.call(&"zoom_fit", "Fit to View", preview.fit_to_view)
	Actions.add(
		&"toggle_status_bar",
		"Status Bar",
		func() -> void: Settings.set_value(&"show_status_bar", not status_bar.visible),
		Callable(),
		null,
		func() -> bool: return status_bar.visible
	)
	Actions.add(
		&"toggle_history",
		"History",
		func() -> void: Settings.set_value(&"show_history", not history_panel.visible),
		Callable(),
		null,
		func() -> bool: return history_panel.visible
	)
	add.call(&"edit_animations", "Animations…", func() -> void: animation_window.open(), has_frames)
	var animation := preview_area.animation_preview
	Actions.add(
		&"toggle_animation",
		"Animation Preview",
		func() -> void: animation.visible = not animation.visible,
		has_frames,
		ICONS[&"toggle_animation"],
		func() -> bool: return animation.visible
	)
	for toggle: Array in [
		[&"toggle_grid", "Grid Lines", &"show_grid"],
		[&"toggle_indices", "Frame Numbers", &"show_indices"],
	]:
		Actions.add(
			toggle[0],
			toggle[1],
			func() -> void: Settings.set_value(toggle[2], not Settings.get_value(toggle[2])),
			Callable(),
			ICONS[toggle[0]],
			func() -> bool: return Settings.get_value(toggle[2])
		)

	add.call(&"undo", "Undo", Global.document.undo, Global.document.can_undo)
	add.call(&"redo", "Redo", Global.document.redo, Global.document.can_redo)

	add.call(&"about", "About spritesheetbelli", func() -> void: about_dialog.popup_centered())
	add.call(
		&"show_shortcuts", "Keyboard Shortcuts", func() -> void: shortcuts_dialog.popup_centered()
	)


## Rows with a selected frame, from top to bottom
func _selected_rows() -> Array[int]:
	var rows: Array[int] = []
	for coord in preview.get_selected_coords():
		if coord.y not in rows:
			rows.append(coord.y)
	rows.sort()
	return rows


func open_row_name_dialog(row: int) -> void:
	row_name_dialog.open(row, Global.spritesheet.row_names.get(row, ""))


## Selected frames that came from a file, see [FrameSource]
func get_selected_linked_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in preview.get_selected_coords():
		if Global.spritesheet.frame_sources.has(coord):
			coords.append(coord)
	return coords


## The selected frames with what they hold, but not where they are in the packed layout,
## see [method Spritesheet.get_cell_data]
func get_selected_cells() -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for coord in preview.get_selected_coords():
		var data := Global.spritesheet.get_cell_data(coord)
		data.erase("placement")
		cells.append(data)
	return cells


func copy_selection() -> void:
	clipboard.copy(get_selected_cells())
	Actions.refresh()


## Adds frames with what they hold to free cells as one undoable step and selects them
func add_cells(action_name: String, cells: Array[Dictionary]) -> void:
	if cells.is_empty():
		return
	var mode: Spritesheet.AddMode = Settings.get_value(&"add_mode")
	var coords: Array[Vector2i] = Global.document.perform(
		action_name, Global.spritesheet.add_cells.bind(cells, mode)
	)
	preview.set_selected_coords(coords)


## Outlines the selected frames, see [method FrameEdits.outline]
func add_outline(color: Color, thickness: int, corners: bool) -> void:
	await edit_selection_in_background(
		"Outline",
		"Adding outlines",
		func(img: Image) -> Image: return ImageUtils.outline(img, color, thickness, corners),
		FrameEdits.outline_move(thickness),
		FrameEdits.outline_op(color, thickness, corners)
	)


## Makes pixels close to [param color] transparent in the selected frames
func remove_background(color: Color, tolerance: float) -> void:
	await edit_selection_in_background(
		"Remove background",
		"Removing background",
		func(img: Image) -> Image:
			ImageUtils.color_key(img, color, tolerance)
			return img,
		Callable(),
		FrameEdits.color_key_op(color, tolerance)
	)


## Replaces each selected frame with [code]edit.call(copy_of_it)[/code], worked out on
## worker threads with a progress bar when it takes a while, then applied as one undoable
## step. [param move] and [param op] are as in [method Spritesheet.edit_frames].
func edit_selection_in_background(
	action_name: String, progress_text: String, edit: Callable, move := Callable(), op := {}
) -> void:
	var sheet := Global.spritesheet
	var coords := preview.get_selected_coords()
	var sources: Array[Image] = []
	for coord in coords:
		sources.append(sheet.frames[coord])
	var results := await Parallel.map(
		sources.size(),
		func(i: int) -> Image: return edit.call(sources[i].duplicate()),
		func(done: int, total: int) -> void: Notify.progress(progress_text, done, total)
	)
	Notify.hide_progress()
	Global.document.perform(
		action_name,
		func() -> void:
			for i in coords.size():
				# Skip frames that changed in the meantime
				if sheet.frames.get(coords[i]) == sources[i]:
					var result: Image = results[i]
					sheet.edit_frames(
						[coords[i]] as Array[Vector2i],
						func(_copy: Image) -> Image: return result,
						move,
						false,
						op
					)
	)


## [param edit] from [FrameEdits] for [method edit_selection], with [param args] after the
## coordinates
static func _edit_with(edit: Callable, args := []) -> Callable:
	return func(coords: Array[Vector2i]) -> void: edit.callv([Global.spritesheet, coords] + args)


## Runs [param edit] with the coordinates of the selected frames, as one undoable step
func edit_selection(action_name: String, edit: Callable) -> void:
	var coords := preview.get_selected_coords()
	if not coords.is_empty():
		Global.document.perform(action_name, edit.bind(coords))


## Resizes sprites to the given width or height (-1 = unchanged). With the size linked,
## the other side follows the current proportions, so a deliberate stretch is kept.
func set_sprite_size(width: int, height: int) -> void:
	var sheet := Global.spritesheet
	var base := sheet.get_base_sprite_size()
	if base.x <= 0 or base.y <= 0:
		return
	# Scale factors are exact, unlike the rounded sprite size
	var aspect := sheet.frame_scale.y / sheet.frame_scale.x
	var new_size := sheet.sprite_size
	if width >= 0:
		new_size.x = width
		if keep_ratio_btn.button_pressed:
			new_size.y = roundi(base.y * width / float(base.x) * aspect)
	if height >= 0:
		new_size.y = height
		if keep_ratio_btn.button_pressed:
			new_size.x = roundi(base.x * height / float(base.y) / aspect)
	resize_sprites(new_size)


func resize_sprites(new_size: Vector2i) -> void:
	if new_size.x <= 0 or new_size.y <= 0 or not _check_sprite_size(new_size):
		set_text_params(Global.spritesheet)
		return
	Global.document.perform(
		"Resize sprites", Global.spritesheet.resize_sprites.bind(new_size, get_resize_filter())
	)


## Multiplies the current scale, e.g. 2 to double the size
func scale_sprites(factor: float) -> void:
	var sheet := Global.spritesheet
	if not _check_sprite_size(Vector2i((Vector2(sheet.sprite_size) * factor).round())):
		return
	Global.document.perform(
		"Resize sprites",
		sheet.set_frame_scale.bind(sheet.frame_scale * factor, get_resize_filter())
	)


## Shows an error and returns false when sprites would be too big to show
func _check_sprite_size(new_size: Vector2i) -> bool:
	var limit := ImageUtils.MAX_TEXTURE_SIZE
	if new_size.x <= limit and new_size.y <= limit:
		return true
	Notify.error(
		(
			tr("Sprites can be at most %d×%d px, and these would be %d×%d px.")
			% [limit, limit, new_size.x, new_size.y]
		)
	)
	return false


## The sheet's filter once it has been resized, otherwise the default from the settings
## Scaling many or big frames takes a while, e.g. after resizing, changing the filter or
## undoing either: scale them on worker threads while a progress bar shows
func _prepare_scaled_images() -> void:
	var sheet := Global.spritesheet
	if (
		sheet.scaled_frames.is_preparing()
		or sheet.scaled_frames.get_pending_work() < SLOW_SCALE_WORK
	):
		return
	await sheet.scaled_frames.prepare(
		func(done: int, total: int) -> void: Notify.progress("Resizing sprites", done, total)
	)
	Notify.hide_progress()
	if not is_inside_tree():
		return
	preview.queue_redraw()
	# The scale may have changed again in the meantime
	_prepare_scaled_images()


## The sheet's filter. New sheets start with the one chosen in the settings.
func get_resize_filter() -> Image.Interpolation:
	return Global.spritesheet.scale_filter


func set_text_params(spritesheet: Spritesheet) -> void:
	grid_rows.set_value_no_signal(spritesheet.grid_size.y)
	grid_columns.set_value_no_signal(spritesheet.grid_size.x)
	sprite_width.set_value_no_signal(spritesheet.sprite_size.x)
	sprite_height.set_value_no_signal(spritesheet.sprite_size.y)
	var image_size := SpritesheetExporter.get_image_size(
		spritesheet, ExportOptions.from_sheet(spritesheet)
	)
	sheet_size.text = "%d × %d px" % [image_size.x, image_size.y]
	if spritesheet.layout == Spritesheet.Layout.PACKED:
		sheet_size.text = AtlasPanel.describe(spritesheet)
	layout_controller.update()
	update_sheet_info()
	resize_filter.select(get_resize_filter())


## Frame count, grid and image size in the status bar
func update_sheet_info() -> void:
	var sheet := Global.spritesheet
	if sheet.is_empty():
		sheet_info.text = tr("No frames. Add sprites or drop images here.")
	elif sheet.layout == Spritesheet.Layout.PACKED:
		sheet_info.text = tr("%d frames · %s") % [sheet.frames.size(), AtlasPanel.describe(sheet)]
		var selected := preview.get_selected_coords().size()
		if selected:
			sheet_info.text += " · " + tr("%d selected") % selected
	else:
		var selected := preview.get_selected_coords().size()
		var image_size := SpritesheetExporter.get_image_size(sheet, ExportOptions.from_sheet(sheet))
		sheet_info.text = (
			tr("%d frames · %d×%d grid · %d×%d px")
			% [
				sheet.frames.size(),
				sheet.grid_size.x,
				sheet.grid_size.y,
				image_size.x,
				image_size.y
			]
		)
		if selected:
			sheet_info.text += " · " + tr("%d selected") % selected
	legend.text = (
		tr("Cells with a lock stay empty") if not sheet.locked_coordinates.is_empty() else ""
	)
	legend.tooltip_text = "Locked cells are kept empty when adding sprites. Click one to unlock it."


## Describes the cell under the mouse in the status bar
func update_cell_info(coord: Vector2i) -> void:
	cell_info.text = PreviewArea.describe_cell(Global.spritesheet, coord).replace("\n", " · ")


func disable_if_empty() -> void:
	var is_empty := Global.spritesheet.is_empty()
	grid_rows.editable = not is_empty
	grid_columns.editable = not is_empty
	sprite_width.editable = not is_empty
	sprite_height.editable = not is_empty
	for button: BaseButton in [
		half_size_btn, double_size_btn, triple_size_btn, original_size_btn, resize_filter
	]:
		button.disabled = is_empty
	original_size_btn.disabled = is_empty or Global.spritesheet.frame_scale == Vector2.ONE


func set_spritesheet_grid_size(columns: int, rows: int) -> void:
	var frames_outside_count := Global.spritesheet.count_frames_outside(Vector2i(columns, rows))
	var spritesheet_set_size := Global.document.perform.bind(
		"Resize grid", Global.spritesheet.set_grid_size.bind(Vector2i(columns, rows))
	)

	if frames_outside_count > 0 and Settings.get_value(&"confirm_grid_shrink"):
		Notify.confirm(
			"Confirm resize",
			(
				tr("Resizing the grid to %d×%d would delete %d sprites.")
				% [columns, rows, frames_outside_count]
			),
			spritesheet_set_size
		)
	else:
		spritesheet_set_size.call()
	# Show the current size again if the change was canceled or not possible
	set_text_params(Global.spritesheet)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		files.confirm_unsaved_changes("closing", get_tree().quit)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		clipboard.on_focus_in()
		source_watcher.on_focus_in()
		Actions.refresh()
