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
	&"flip_h", &"flip_v", &"rotate_cw", &"rotate_ccw", &"", &"delete_frames"
]

@onready var files: FileController = $Files
@onready var preview_area: Control = %PreviewArea
@onready var grid_rows: SpinBox = %GridRows
@onready var grid_columns: SpinBox = %GridColumns
@onready var sprite_width: SpinBox = %SpriteWidth
@onready var sprite_height: SpinBox = %SpriteHeight
@onready var keep_ratio_btn: Button = %KeepRatio
@onready var add_sprites_btn: Button = %AddSprites
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var spritesheet_width: Label = %SpritesheetWidth
@onready var spritesheet_height: Label = %SpritesheetHeight
@onready var preview: SpritesheetPreview = preview_area.spritesheet_preview

var shortcuts_dialog := ShortcutsDialog.new()


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
		func(rows: float): set_spritesheet_grid_size(Global.spritesheet.grid_size.x, int(rows))
	)
	grid_columns.value_changed.connect(
		func(columns: float):
			set_spritesheet_grid_size(int(columns), Global.spritesheet.grid_size.y)
	)
	sprite_width.value_changed.connect(func(width: float): set_sprite_size(int(width), -1))
	sprite_height.value_changed.connect(func(height: float): set_sprite_size(-1, int(height)))
	keep_ratio_btn.toggled.connect(
		func(on: bool): keep_ratio_btn.icon = LINK_ICON if on else UNLINK_ICON
	)
	get_tree().auto_accept_quit = false
	add_child(shortcuts_dialog)
	_register_actions()
	preview_area.set_context_actions(CONTEXT_ACTIONS)
	preview.preview_updated.connect(Actions.refresh)
	preview.move_requested.connect(
		func(coords: Array[Vector2i], offset: Vector2i, copy: bool):
			var targets: Array[Vector2i] = Global.document.perform(
				"Copy frames" if copy else "Move frames",
				Global.spritesheet.move_frames.bind(coords, offset, copy)
			)
			preview.set_selected_coords(targets)
	)
	preview.lock_requested.connect(
		func(coord: Vector2i, locked: bool):
			Global.document.perform(
				"Lock cell" if locked else "Unlock cell",
				Global.spritesheet.set_locked.bind(coord, locked)
			)
	)


func _register_actions() -> void:
	var sheet := Global.spritesheet
	var has_frames := func() -> bool: return not sheet.is_empty()
	var has_selection := func() -> bool: return not preview.get_selected_coords().is_empty()
	var add := func(id: StringName, label: String, run: Callable, can_run := Callable()):
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
	add.call(&"quit", "Quit", func(): files.confirm_unsaved_changes("quitting", get_tree().quit))

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

	add.call(&"zoom_in", "Zoom In", preview.zoom_by.bind(1.25))
	add.call(&"zoom_out", "Zoom Out", preview.zoom_by.bind(0.8))
	add.call(
		&"zoom_reset",
		"Actual Size",
		func(): preview.set_zoom(1, preview.get_viewport_rect().size / 2)
	)
	add.call(&"zoom_fit", "Fit to View", preview.fit_to_view)

	add.call(&"undo", "Undo", Global.document.undo, Global.document.can_undo)
	add.call(&"redo", "Redo", Global.document.redo, Global.document.can_redo)

	add.call(&"show_shortcuts", "Keyboard Shortcuts", func(): shortcuts_dialog.popup_centered())


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
	Global.document.perform("Resize sprites", Global.spritesheet.resize_sprites.bind(new_size))


func set_text_params(spritesheet: Spritesheet) -> void:
	grid_rows.set_value_no_signal(spritesheet.grid_size.y)
	grid_columns.set_value_no_signal(spritesheet.grid_size.x)
	sprite_width.set_value_no_signal(spritesheet.sprite_size.x)
	sprite_height.set_value_no_signal(spritesheet.sprite_size.y)
	spritesheet_width.text = str(spritesheet.sprite_size.x * spritesheet.grid_size.x)
	spritesheet_height.text = str(spritesheet.sprite_size.y * spritesheet.grid_size.y)


func disable_if_empty():
	var is_empty := Global.spritesheet.is_empty()
	grid_rows.editable = not is_empty
	grid_columns.editable = not is_empty
	sprite_width.editable = not is_empty
	sprite_height.editable = not is_empty


func set_spritesheet_grid_size(columns: int, rows: int):
	var frames_outside_count := Global.spritesheet.count_frames_outside(Vector2i(columns, rows))
	var spritesheet_set_size := Global.document.perform.bind(
		"Resize grid", Global.spritesheet.set_grid_size.bind(Vector2i(columns, rows))
	)

	if frames_outside_count > 0:
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
