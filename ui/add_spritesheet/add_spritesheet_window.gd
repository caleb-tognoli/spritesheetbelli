class_name AddSpritesheetWindow
extends Window


signal canceled

@onready var preview_area: PreviewArea = %PreviewArea
@onready var add_selected_frames_btn: Button = %AddSelectedFrames
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var grid_columns: LineEdit = %GridColumns
@onready var grid_rows: LineEdit = %GridRows

@export var spritesheet_image: Image

var spritesheet: Spritesheet


func _ready() -> void:
	close_requested.connect(hide)
	close_requested.connect(canceled.emit)
	add_selected_frames_btn.pressed.connect(add_selected_frames_to_global)
	add_spritesheet_btn.pressed.connect(add_spritesheet_to_global)
	preview_area.spritesheet_preview.preview_updated.connect(on_preview_update)
	grid_columns.text_submitted.connect(
		func(columns_str: String):
			update_grid_size(int(columns_str), spritesheet.grid_size.y)
	)
	grid_rows.text_submitted.connect(
		func(rows_str: String):
			update_grid_size(spritesheet.grid_size.x, int(rows_str))
	)
	
	preview_area.spritesheet_preview.able_to_lock_spaces = false


func setup(img: Image):
	spritesheet_image = img
	
	var guessed_size := guess_grid_size(img.get_size())
	update_grid_size(guessed_size.x, guessed_size.y)
	
	preview_area.spritesheet_preview.camera.zoom = Vector2.ONE
	preview_area.spritesheet_preview.camera.position = Vector2.ONE * -50


func on_preview_update():
	var selection_size := preview_area.spritesheet_preview.get_selected_frames().size()
	add_selected_frames_btn.disabled = selection_size == 0
	add_selected_frames_btn.text = "Add selected frames (%d)" % selection_size


func update_grid_size(columns: int, rows: int):
	rows = max(1, rows)
	columns = max(1, columns)
	spritesheet = Spritesheet.new()
	var grid_size := Vector2i(columns, rows)
	spritesheet.grid_size = grid_size
	spritesheet.sprite_size = spritesheet_image.get_size() / grid_size
	
	for row in grid_size.y:
		for column in grid_size.x:
			var frame_position := Vector2i(column * spritesheet.sprite_size.x, row * spritesheet.sprite_size.y)
			var frame_img := spritesheet_image.get_region(Rect2i(frame_position, spritesheet.sprite_size))
			if not frame_img.is_invisible():
				spritesheet.frames[Vector2i(column, row)] = frame_img
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()
	
	grid_columns.text = str(columns)
	grid_rows.text = str(rows)


func add_spritesheet_to_global():
	var rows_images: Array[Array] = []
	for row in spritesheet.grid_size.y:
		rows_images.append([])
		for column in spritesheet.grid_size.x:
			if spritesheet.frames.has(Vector2i(column, row)):
				rows_images[row].append(spritesheet.frames[Vector2i(column, row)])
			else:
				rows_images[row].append(Image.new())
	for row_images in rows_images:
		var frames: Array[Image] = []
		frames.assign(row_images)
		Global.spritesheet.add_frames(frames, Spritesheet.AddMode.ROW)
	Global.spritesheet.lock_all_free_spaces()
	close_requested.emit()


func add_selected_frames_to_global():
	var selected_frames: Dictionary = preview_area.spritesheet_preview.get_selected_frames()
	var selected_frames_imgs: Array[Image] = []
	selected_frames_imgs.assign(selected_frames.values())
	Global.spritesheet.add_frames(selected_frames_imgs)
	close_requested.emit()


static func guess_grid_size(spritesheet_size: Vector2i) -> Vector2i:
	var gcd := Math.gcd(spritesheet_size.x, spritesheet_size.y)
	if gcd != 1:
		return spritesheet_size / gcd
	else:
		return Vector2i(3, 3)
