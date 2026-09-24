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
@onready var original_size_btn: Button = %OriginalSize
@onready var resize_filter: OptionButton = %ResizeFilter
@onready var add_sprites_btn: Button = %AddSprites
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var spritesheet_width: Label = %SpritesheetWidth
@onready var spritesheet_height: Label = %SpritesheetHeight
@onready var preview: SpritesheetPreview = preview_area.spritesheet_preview

var shortcuts_dialog := ShortcutsDialog.new()
var settings_window := SettingsWindow.new()
var clipboard := FrameClipboard.new()


func _ready() -> void:
	# 0 is only shown while the spritesheet is empty
	for field: SpinBox in [grid_rows, grid_columns, sprite_width, sprite_height]:
		field.min_value = 0
	preview_area.spritesheet_preview.spritesheet = Global.spritesheet
	set_text_params(Global.spritesheet)
	disable_if_empty()

	Global.spritesheet.updated.connect(set_text_params.bind(Global.spritesheet))
	Global.spritesheet.updated.connect(disable_if_empty)
	add_sprites_btn.pressed.connect(Actions.run.bind(&"add_sprites"))
	add_spritesheet_btn.pressed.connect(Actions.run.bind(&"add_spritesheet"))
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
	files.restore_session.call_deferred()
	_register_actions()
	preview_area.set_context_actions(CONTEXT_ACTIONS)
	preview.preview_updated.connect(Actions.refresh)
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

	add.call(
		&"show_shortcuts", "Keyboard Shortcuts", func() -> void: shortcuts_dialog.popup_centered()
	)


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


## Resizes sprites to the given width or height (-1 = unchanged), keeping the
## ratio of the original frames when Keep aspect ratio is on
func set_sprite_size(width: int, height: int) -> void:
	var sheet := Global.spritesheet
	var base := sheet.get_base_sprite_size()
	if base.x <= 0 or base.y <= 0:
		return
	var new_size := sheet.sprite_size
	if width >= 0:
		new_size.x = width
		if keep_ratio_btn.button_pressed:
			new_size.y = roundi(width * base.y / float(base.x))
	if height >= 0:
		new_size.y = height
		if keep_ratio_btn.button_pressed:
			new_size.x = roundi(height * base.x / float(base.y))
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
	spritesheet_width.text = str(spritesheet.sprite_size.x * spritesheet.grid_size.x)
	spritesheet_height.text = str(spritesheet.sprite_size.y * spritesheet.grid_size.y)
	resize_filter.select(get_resize_filter())


func disable_if_empty() -> void:
	var is_empty := Global.spritesheet.is_empty()
	grid_rows.editable = not is_empty
	grid_columns.editable = not is_empty
	sprite_width.editable = not is_empty
	sprite_height.editable = not is_empty
	for button: BaseButton in [half_size_btn, double_size_btn, original_size_btn, resize_filter]:
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
				"Resizing the grid to %d×%d would delete %d sprites."
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
