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

@export var spritesheet_image: Image

var spritesheet: Spritesheet


func _ready() -> void:
	close_requested.connect(hide)
	close_requested.connect(canceled.emit)
	add_selected_frames_btn.pressed.connect(add_selected_frames_to_global)
	add_spritesheet_btn.pressed.connect(add_spritesheet_to_global)
	preview_area.spritesheet_preview.preview_updated.connect(on_preview_update)
	grid_columns.value_changed.connect(
		func(columns: float): update_grid_size(int(columns), spritesheet.grid_size.y)
	)
	grid_rows.value_changed.connect(
		func(rows: float): update_grid_size(spritesheet.grid_size.x, int(rows))
	)

	preview_area.spritesheet_preview.able_to_lock_spaces = false


## Shows [param img] sliced into a guessed grid. [param file_name] can hold a size hint.
func setup(img: Image, file_name := ""):
	spritesheet_image = img

	var guessed_size := GridGuesser.guess(img, file_name)
	update_grid_size(guessed_size.x, guessed_size.y)

	preview_area.spritesheet_preview.camera.position = Vector2.ONE * -50
	preview_area.spritesheet_preview.set_zoom(1)


func on_preview_update():
	var selection_size := preview_area.spritesheet_preview.get_selected_coords().size()
	add_selected_frames_btn.disabled = selection_size == 0
	add_selected_frames_btn.text = "Add selected frames (%d)" % selection_size


func update_grid_size(columns: int, rows: int):
	rows = max(1, rows)
	columns = max(1, columns)
	spritesheet = Spritesheet.new()
	var grid_size := Vector2i(columns, rows)
	var cell_size := spritesheet_image.get_size() / grid_size

	spritesheet.begin_batch()
	spritesheet.set_grid_size(grid_size)
	for row in grid_size.y:
		for column in grid_size.x:
			var frame_img := spritesheet_image.get_region(
				Rect2i(Vector2i(column, row) * cell_size, cell_size)
			)
			if not frame_img.is_invisible():
				spritesheet.set_frame(Vector2i(column, row), frame_img)
	spritesheet.end_batch()
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()

	grid_columns.set_value_no_signal(columns)
	grid_rows.set_value_no_signal(rows)


func add_spritesheet_to_global():
	if spritesheet.is_empty():
		close_requested.emit()
		return

	# Place the whole grid below the existing frames, keeping empty rows and columns
	var target := Global.spritesheet
	Global.document.perform(
		"Add spritesheet",
		func():
			var offset := Vector2i(0, target.get_first_free_row())
			target.set_grid_size(target.grid_size.max(spritesheet.grid_size + offset))
			for coord: Vector2i in spritesheet.frames:
				target.set_frame(coord + offset, spritesheet.frames[coord])
			# Keep the added sheet's layout without touching free cells elsewhere
			target.lock_free_cells(Rect2i(offset, spritesheet.grid_size))
	)
	frames_added.emit()
	close_requested.emit()


func add_selected_frames_to_global():
	var imgs: Array[Image] = []
	for coord in preview_area.spritesheet_preview.get_selected_coords():
		imgs.append(spritesheet.frames[coord])
	Global.document.perform("Add frames", Global.spritesheet.add_frames.bind(imgs))
	frames_added.emit()
	close_requested.emit()
