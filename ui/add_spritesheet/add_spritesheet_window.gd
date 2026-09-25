class_name AddSpritesheetWindow
extends Window

const DROPDOWN_ICON := preload("res://assets/icons/GuiTreeArrowDown.svg")

signal canceled
## Emitted after frames were added to the open spritesheet
signal frames_added

@onready var preview_area: PreviewArea = %PreviewArea
@onready var add_selected_frames_btn: Button = %AddSelectedFrames
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var grid_columns: SpinBox = %GridColumns
@onready var grid_rows: SpinBox = %GridRows
@onready var offset_x: SpinBox = %OffsetX
@onready var offset_y: SpinBox = %OffsetY
@onready var spacing_x: SpinBox = %SpacingX
@onready var spacing_y: SpinBox = %SpacingY
@onready var slice_info: Label = %SliceInfo

@export var spritesheet_image: Image

var spritesheet: Spritesheet
## Where the frames are, from a data file exported with the image, or null
var sheet_data: SheetData
## Switches between the frames from [member sheet_data] and cutting a grid
var data_toggle := CheckButton.new()
## Opens the rarely needed offset and spacing fields in a floating panel
var more_options_btn := Button.new()
var more_options_popup := PopupPanel.new()


func _ready() -> void:
	close_requested.connect(hide)
	close_requested.connect(canceled.emit)
	add_selected_frames_btn.pressed.connect(add_selected_frames_to_global)
	add_selected_frames_btn.icon = preload("res://assets/icons/Add.svg")
	add_spritesheet_btn.icon = preload("res://assets/icons/SpriteSheet.svg")
	add_spritesheet_btn.pressed.connect(add_spritesheet_to_global)
	preview_area.spritesheet_preview.selection_changed.connect(on_preview_update)
	grid_columns.value_changed.connect(
		func(columns: float) -> void: update_grid_size(int(columns), spritesheet.grid_size.y)
	)
	grid_rows.value_changed.connect(
		func(rows: float) -> void: update_grid_size(spritesheet.grid_size.x, int(rows))
	)

	for field: SpinBox in [grid_columns, grid_rows, offset_x, offset_y, spacing_x, spacing_y]:
		SpinScroll.enable(field)
	for field: SpinBox in [offset_x, offset_y, spacing_x, spacing_y]:
		field.value_changed.connect(
			func(_value: float) -> void:
				update_grid_size(spritesheet.grid_size.x, spritesheet.grid_size.y)
				_update_options_label()
		)

	# Offset and spacing are rarely needed, so they're in a panel that drops down
	var offset_box := offset_x.get_parent().get_parent() as Control
	var spacing_box := spacing_x.get_parent().get_parent() as Control
	more_options_btn.icon = DROPDOWN_ICON
	more_options_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	more_options_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more_options_btn.tooltip_text = "For sheets with a margin around or gaps between the frames"
	offset_box.add_sibling(more_options_btn)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 8)
	more_options_popup.add_child(fields)
	add_child(more_options_popup)
	for box: Control in [offset_box, spacing_box]:
		box.reparent(fields, false)
		LabelLink.link(box.get_child(0) as Label, box.get_child(1) as Control)
	more_options_btn.pressed.connect(
		func() -> void:
			var below := more_options_btn.get_global_rect()
			below.position.y += below.size.y + 4
			more_options_popup.popup_on_parent(Rect2i(Rect2(below.position, Vector2.ZERO)))
	)
	_update_options_label()

	var grid_box := grid_columns.get_parent().get_parent() as Control
	grid_box.add_sibling(data_toggle)
	grid_box.get_parent().move_child(data_toggle, 0)
	data_toggle.tooltip_text = "Cut the frames where the data file says they are"
	data_toggle.toggled.connect(func(_on: bool) -> void: _slice())

	preview_area.spritesheet_preview.able_to_lock_spaces = false
	preview_area.spritesheet_preview.able_to_move_frames = false
	# Show the whole sheet once the window has its size
	visibility_changed.connect(
		func() -> void:
			if visible:
				await get_tree().process_frame
				preview_area.spritesheet_preview.fit_to_view()
	)


## Shows [param img] cut where [param data] says the frames are, or else sliced into a
## guessed grid. [param file_name] can hold a size hint, [param data_name] names the data.
func setup(img: Image, file_name := "", data: SheetData = null, data_name := "") -> void:
	spritesheet_image = img
	sheet_data = data
	for field: SpinBox in [offset_x, offset_y, spacing_x, spacing_y]:
		field.set_value_no_signal(0)
	_update_options_label()

	var guessed_size := GridGuesser.guess(img, file_name)
	grid_columns.set_value_no_signal(guessed_size.x)
	grid_rows.set_value_no_signal(guessed_size.y)
	data_toggle.visible = data != null
	data_toggle.text = tr("Use %s") % data_name
	data_toggle.set_pressed_no_signal(data != null)
	_slice()

	preview_area.spritesheet_preview.camera.position = Vector2.ONE * -50
	preview_area.spritesheet_preview.set_zoom(1)


## Cuts the image with the data file when it's used, or else with the grid fields
func _slice() -> void:
	var use_data := sheet_data != null and data_toggle.button_pressed
	for control: Control in [grid_columns.get_parent().get_parent(), more_options_btn]:
		control.visible = not use_data
	if not use_data:
		update_grid_size(int(grid_columns.value), int(grid_rows.value))
		return
	spritesheet = sheet_data.to_spritesheet(spritesheet_image)
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()
	slice_info.remove_theme_color_override("font_color")
	slice_info.tooltip_text = ""
	slice_info.text = tr("%d frames") % spritesheet.frames.size()
	if not spritesheet.animations.is_empty():
		slice_info.text += tr(" · %d animations") % spritesheet.animations.size()


func on_preview_update() -> void:
	var selection_size := preview_area.spritesheet_preview.get_selected_coords().size()
	add_selected_frames_btn.disabled = selection_size == 0
	add_selected_frames_btn.text = tr("Add selected frames (%d)") % selection_size


func update_grid_size(columns: int, rows: int) -> void:
	rows = max(1, rows)
	columns = max(1, columns)
	spritesheet = Spritesheet.new()
	var grid_size := Vector2i(columns, rows)
	var offset := Vector2i(int(offset_x.value), int(offset_y.value))
	var spacing := Vector2i(int(spacing_x.value), int(spacing_y.value))
	var result := Slicer.slice(spritesheet_image, grid_size, offset, spacing)

	spritesheet.begin_batch()
	spritesheet.set_grid_size(grid_size)
	for coord: Vector2i in result.frames:
		spritesheet.set_frame(coord, result.frames[coord])
	spritesheet.end_batch()
	_show_slice_info(result.cell_size, result.unused)
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()

	grid_columns.set_value_no_signal(columns)
	grid_rows.set_value_no_signal(rows)


func add_spritesheet_to_global() -> void:
	if spritesheet.is_empty():
		close_requested.emit()
		return

	# Place the whole grid below the existing frames, keeping empty rows and columns
	var target := Global.spritesheet
	Global.document.perform(
		"Add spritesheet",
		func() -> void:
			var offset := Vector2i(0, target.get_first_free_row())
			target.set_grid_size(target.grid_size.max(spritesheet.grid_size + offset))
			for coord: Vector2i in spritesheet.frames:
				target.set_frame(coord + offset, spritesheet.frames[coord])
			for row: int in spritesheet.row_names:
				target.set_row_name(row + offset.y, spritesheet.row_names[row])
			for animation in spritesheet.animations:
				animation.name = target.get_unique_animation_name(animation.name)
				var cells: Array[Vector2i] = []
				for cell in animation.cells:
					cells.append(cell + offset)
				animation.cells = cells
				target.add_animation(animation)
			# Keep the added sheet's layout without touching free cells elsewhere
			target.lock_free_cells(Rect2i(offset, spritesheet.grid_size))
	)
	frames_added.emit()
	close_requested.emit()


func add_selected_frames_to_global() -> void:
	var imgs: Array[Image] = []
	for coord in preview_area.spritesheet_preview.get_selected_coords():
		imgs.append(spritesheet.frames[coord])
	Global.document.perform(
		"Add frames", Global.spritesheet.add_frames.bind(imgs, Settings.get_value(&"add_mode"))
	)
	frames_added.emit()
	close_requested.emit()


func _show_slice_info(cell_size: Vector2i, unused: Vector2i) -> void:
	slice_info.text = tr("Cell size: %d×%d px") % [cell_size.x, cell_size.y]
	slice_info.tooltip_text = ""
	slice_info.remove_theme_color_override("font_color")
	if unused != Vector2i.ZERO:
		var parts: PackedStringArray = []
		if unused.x > 0:
			parts.append("%d px on the right" % unused.x)
		if unused.y > 0:
			parts.append("%d px at the bottom" % unused.y)
		slice_info.text += tr(" · %s not used") % " and ".join(parts)
		slice_info.tooltip_text = "The image doesn't divide evenly into this grid"
		slice_info.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))


## Shows the offset and spacing on the button when they're set
func _update_options_label() -> void:
	var offset := Vector2i(int(offset_x.value), int(offset_y.value))
	var spacing := Vector2i(int(spacing_x.value), int(spacing_y.value))
	var parts: PackedStringArray = []
	if offset != Vector2i.ZERO:
		parts.append(tr("Offset %d×%d") % [offset.x, offset.y])
	if spacing != Vector2i.ZERO:
		parts.append(tr("Spacing %d×%d") % [spacing.x, spacing.y])
	more_options_btn.text = " · ".join(parts) if parts else tr("Offset & Spacing")
