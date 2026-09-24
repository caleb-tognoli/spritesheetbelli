extends Control

const LINK_ICON := preload("res://assets/icons/Link.svg")
const UNLINK_ICON := preload("res://assets/icons/Unlink.svg")
const ICONS := {
	&"add_sprites": preload("res://assets/icons/Add.svg"),
	&"add_spritesheet": preload("res://assets/icons/SpriteSheet.svg"),
	&"flip_h": preload("res://assets/icons/MirrorX.svg"),
	&"flip_v": preload("res://assets/icons/MirrorY.svg"),
	&"rotate_cw": preload("res://assets/icons/RotateRight.svg"),
	&"rotate_ccw": preload("res://assets/icons/RotateLeft.svg"),
	&"delete_frames": preload("res://assets/icons/Remove.svg"),
}
## Actions offered when right-clicking frames
const CONTEXT_ACTIONS: Array[StringName] = [
	&"cut",
	&"copy",
	&"paste",
	&"duplicate",
	&"",
	&"flip_h",
	&"flip_v",
	&"rotate_cw",
	&"rotate_ccw",
	&"",
	&"insert_cell",
	&"remove_cell",
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
@onready var export_image_btn: Button = %ExportImage
@onready var export_settings_btn: Button = %ExportSettings
@onready var split: HSplitContainer = %Split
@onready var status_bar: Control = %StatusBar
@onready var sheet_info: Label = %SheetInfo
@onready var cell_info: Label = %CellInfo
@onready var legend: Label = %Legend
@onready var preview: SpritesheetPreview = preview_area.spritesheet_preview

var shortcuts_dialog := ShortcutsDialog.new()
var settings_window := SettingsWindow.new()
var clipboard := FrameClipboard.new()
var color_key_dialog := ColorKeyDialog.new()
var row_name_dialog := RowNameDialog.new()
var export_settings_dialog := ExportSettingsDialog.new()
var about_dialog := AboutDialog.new()
var _was_empty := true


func _ready() -> void:
	# The command line doesn't need the window
	if Global.cli_mode:
		queue_free()
		return
	# 0 is only shown while the spritesheet is empty
	for field: SpinBox in [grid_rows, grid_columns, sprite_width, sprite_height]:
		field.min_value = 0
		SpinScroll.enable(field)
	preview_area.spritesheet_preview.spritesheet = Global.spritesheet
	set_text_params(Global.spritesheet)
	disable_if_empty()

	Global.spritesheet.updated.connect(set_text_params.bind(Global.spritesheet))
	Global.spritesheet.updated.connect(disable_if_empty)
	add_sprites_btn.pressed.connect(Actions.run.bind(&"add_sprites"))
	add_spritesheet_btn.pressed.connect(Actions.run.bind(&"add_spritesheet"))
	export_image_btn.pressed.connect(Actions.run.bind(&"export_image"))
	export_settings_btn.pressed.connect(Actions.run.bind(&"export_settings"))
	get_window().min_size = Vector2i(820, 520)
	split.split_offset = Settings.get_value(&"sidebar_width")
	split.dragged.connect(func(offset: int) -> void: Settings.set_value(&"sidebar_width", offset))
	status_bar.visible = Settings.get_value(&"show_status_bar")
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"show_status_bar":
				status_bar.visible = Settings.get_value(key)
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
	keep_ratio_btn.toggled.connect(
		func(on: bool) -> void: keep_ratio_btn.icon = LINK_ICON if on else UNLINK_ICON
	)
	get_tree().auto_accept_quit = false
	add_child(shortcuts_dialog)
	add_child(settings_window)
	add_child(color_key_dialog)
	add_child(row_name_dialog)
	add_child(export_settings_dialog)
	add_child(about_dialog)
	row_name_dialog.name_chosen.connect(
		func(row: int, row_name: String) -> void:
			Global.document.perform("Name row", Global.spritesheet.set_row_name.bind(row, row_name))
	)
	preview.row_name_requested.connect(open_row_name_dialog)
	color_key_dialog.color_chosen.connect(
		func(color: Color, tolerance: float) -> void:
			edit_selection(
				"Remove background",
				func(coords: Array[Vector2i]) -> void:
					Global.spritesheet.color_key_frames(coords, color, tolerance)
			)
	)
	files.restore_session.call_deferred()
	files.get_selected_coords = preview.get_selected_coords
	(%MenuBar as MainMenuBar).recent_files.file_chosen.connect(files.open_recent)
	_register_actions()
	preview_area.set_context_actions(CONTEXT_ACTIONS)
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
	preview.lock_requested.connect(
		func(coord: Vector2i, locked: bool) -> void:
			Global.document.perform(
				"Lock cell" if locked else "Unlock cell",
				Global.spritesheet.set_locked.bind(coord, locked)
			)
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
	add.call(&"export_image", "Export Image", files.export_image, has_frames)
	add.call(&"export_image_as", "Export Image As…", files.export_image_as, has_frames)
	add.call(
		&"export_sprites",
		"Export Sprites…",
		files.popup_file_dialog.bind(files.save_sprites_dialog),
		has_frames
	)
	add.call(
		&"export_atlas",
		"Export Packed Atlas…",
		files.popup_file_dialog.bind(files.export_atlas_dialog),
		has_frames
	)
	add.call(
		&"export_settings",
		"Export Settings…",
		func() -> void: export_settings_dialog.popup_centered(),
		has_frames
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

	add.call(&"select_all", "Select All", preview_area.select_all.bind(true), has_frames)
	add.call(&"select_none", "Select None", preview_area.select_all.bind(false), has_selection)
	add.call(
		&"flip_h",
		"Flip Horizontally",
		edit_selection.bind("Flip", sheet.flip_frames.bind(true)),
		has_selection
	)
	add.call(
		&"flip_v",
		"Flip Vertically",
		edit_selection.bind("Flip", sheet.flip_frames.bind(false)),
		has_selection
	)
	add.call(
		&"rotate_cw",
		"Rotate 90° CW",
		edit_selection.bind("Rotate", sheet.rotate_frames.bind(true)),
		has_selection
	)
	add.call(
		&"rotate_ccw",
		"Rotate 90° CCW",
		edit_selection.bind("Rotate", sheet.rotate_frames.bind(false)),
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
		func() -> void: add_images("Paste", clipboard.get_images()),
		clipboard.has_content
	)
	add.call(
		&"duplicate",
		"Duplicate",
		func() -> void: add_images("Duplicate", get_selected_images()),
		has_selection
	)
	add.call(
		&"trim",
		"Trim Transparent Borders",
		edit_selection.bind("Trim", sheet.trim_frames),
		has_selection
	)
	add.call(
		&"color_key",
		"Remove Background Colour…",
		func() -> void: color_key_dialog.open(sheet.frames[preview.get_selected_coords()[0]]),
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
	var animation := preview_area.animation_preview
	Actions.add(
		&"toggle_animation",
		"Animation Preview",
		func() -> void: animation.visible = not animation.visible,
		has_frames,
		null,
		func() -> bool: return animation.visible
	)

	add.call(&"undo", "Undo", Global.document.undo, Global.document.can_undo)
	add.call(&"redo", "Redo", Global.document.redo, Global.document.can_redo)

	add.call(&"about", "About spritesheetbelli", func() -> void: about_dialog.popup_centered())
	add.call(
		&"show_shortcuts", "Keyboard Shortcuts", func() -> void: shortcuts_dialog.popup_centered()
	)


func open_row_name_dialog(row: int) -> void:
	row_name_dialog.open(row, Global.spritesheet.row_names.get(row, ""))


func get_selected_images() -> Array[Image]:
	var images: Array[Image] = []
	for coord in preview.get_selected_coords():
		images.append(Global.spritesheet.frames[coord])
	return images


func copy_selection() -> void:
	clipboard.copy(get_selected_images())
	Actions.refresh()


## Adds [param images] to free cells as one undoable step and selects them
func add_images(action_name: String, images: Array[Image]) -> void:
	if images.is_empty():
		return
	var mode: Spritesheet.AddMode = Settings.get_value(&"add_mode")
	var coords: Array[Vector2i] = Global.document.perform(
		action_name, Global.spritesheet.add_frames.bind(images, mode)
	)
	preview.set_selected_coords(coords)


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
	if new_size.x <= 0 or new_size.y <= 0:
		set_text_params(Global.spritesheet)
		return
	Global.document.perform(
		"Resize sprites", Global.spritesheet.resize_sprites.bind(new_size, get_resize_filter())
	)


## Multiplies the current scale, e.g. 2 to double the size
func scale_sprites(factor: float) -> void:
	var sheet := Global.spritesheet
	Global.document.perform(
		"Resize sprites",
		sheet.set_frame_scale.bind(sheet.frame_scale * factor, get_resize_filter())
	)


## The sheet's filter once it has been resized, otherwise the default from the settings
func get_resize_filter() -> Image.Interpolation:
	var sheet := Global.spritesheet
	if sheet.frame_scale != Vector2.ONE:
		return sheet.scale_filter
	return Settings.get_value(&"resize_filter")


func set_text_params(spritesheet: Spritesheet) -> void:
	grid_rows.set_value_no_signal(spritesheet.grid_size.y)
	grid_columns.set_value_no_signal(spritesheet.grid_size.x)
	sprite_width.set_value_no_signal(spritesheet.sprite_size.x)
	sprite_height.set_value_no_signal(spritesheet.sprite_size.y)
	var image_size := SpritesheetExporter.get_image_size(
		spritesheet, ExportOptions.from_sheet(spritesheet)
	)
	sheet_size.text = "%d × %d px" % [image_size.x, image_size.y]
	update_sheet_info()
	resize_filter.select(get_resize_filter())


## Frame count, grid and image size in the status bar
func update_sheet_info() -> void:
	var sheet := Global.spritesheet
	if sheet.is_empty():
		sheet_info.text = tr("No frames. Add sprites or drop images here.")
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
	legend.text = tr("Hatched cells are locked") if not sheet.locked_coordinates.is_empty() else ""
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
		Actions.refresh()
