class_name AddSpritesheetWindow
extends Window

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


func _ready() -> void:
	close_requested.connect(hide)
	close_requested.connect(canceled.emit)
	add_selected_frames_btn.pressed.connect(add_selected_frames_to_global)
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
		)

	preview_area.spritesheet_preview.able_to_lock_spaces = false
	# Show the whole sheet once the window has its size
	visibility_changed.connect(
		func() -> void:
			if visible:
				await get_tree().process_frame
				preview_area.spritesheet_preview.fit_to_view()
	)


## Shows [param img] sliced into a guessed grid. [param file_name] can hold a size hint.
func setup(img: Image, file_name := "") -> void:
	spritesheet_image = img
	for field: SpinBox in [offset_x, offset_y, spacing_x, spacing_y]:
		field.set_value_no_signal(0)

	var guessed_size := GridGuesser.guess(img, file_name)
	update_grid_size(guessed_size.x, guessed_size.y)

	preview_area.spritesheet_preview.camera.position = Vector2.ONE * -50
	preview_area.spritesheet_preview.set_zoom(1)


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
		slice_info.text += tr("\n%s not used") % " and ".join(parts)
		slice_info.tooltip_text = "The image doesn't divide evenly into this grid"
		slice_info.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
