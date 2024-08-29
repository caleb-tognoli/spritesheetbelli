extends Control


@onready var save_sprites_dialog: FileDialog = $SaveSpritesDialog
@onready var save_spritesheet_dialog: FileDialog = $SaveSpritesheetDialog
@onready var notification_dialog: AcceptDialog = $NotificationDialog
@onready var confirmation_dialog: ConfirmationDialog = $ConfirmationDialog
@onready var preview_area: Control = %PreviewArea
@onready var grid_rows: LineEdit = %GridRows
@onready var grid_columns: LineEdit = %GridColumns
@onready var sprite_width: LineEdit = %SpriteWidth
@onready var sprite_height: LineEdit = %SpriteHeight
@onready var add_sprites: Button = %AddSprites
@onready var export_sprites: Button = %ExportSprites
@onready var export_spritesheet: Button = %ExportSpritesheet
@onready var print_selected: Button = %PrintSelected
@onready var spritesheet_width: Label = %SpritesheetWidth
@onready var spritesheet_height: Label = %SpritesheetHeight


func _ready() -> void:
	preview_area.spritesheet_preview.spritesheet = Global.spritesheet
	set_text_params(Global.spritesheet)
	disable_if_empty()
	
	Global.spritesheet.updated.connect(set_text_params.bind(Global.spritesheet))
	Global.spritesheet.updated.connect(disable_if_empty)
	save_sprites_dialog.dir_selected.connect(save_sprites)
	save_spritesheet_dialog.file_selected.connect(save_spritesheet)
	export_sprites.pressed.connect(save_sprites_dialog.popup)
	export_spritesheet.pressed.connect(save_spritesheet_dialog.popup)
	grid_rows.text_submitted.connect(
		func(str_rows):
			set_spritesheet_grid_size(Global.spritesheet.grid_size.x, int(str_rows))
	)
	grid_columns.text_submitted.connect(
		func(str_columns):
			set_spritesheet_grid_size(int(str_columns), Global.spritesheet.grid_size.y)
	)
	sprite_width.text_submitted.connect(
		func(str_width):
			var width: int = int(str_width)
			var height: int = (Global.spritesheet.sprite_size.y * width) / Global.spritesheet.sprite_size.x
			Global.spritesheet.resize_frames(Vector2i(width, height))
	)
	sprite_height.text_submitted.connect(
		func(str_height):
			var height: int = int(str_height)
			var width: int = (Global.spritesheet.sprite_size.x * height) / Global.spritesheet.sprite_size.y
			Global.spritesheet.resize_frames(Vector2i(width, height))
	)
	
	print_selected.pressed.connect(
		func():
			print(preview_area.spritesheet_preview.get_selected_frames().keys())
	)


func set_text_params(spritesheet: Spritesheet) -> void:
	grid_rows.text = str(spritesheet.grid_size.y)
	grid_columns.text = str(spritesheet.grid_size.x)
	sprite_width.text = str(spritesheet.sprite_size.x)
	sprite_height.text = str(spritesheet.sprite_size.y)
	spritesheet_width.text = str(spritesheet.sprite_size.x * spritesheet.grid_size.x)
	spritesheet_height.text = str(spritesheet.sprite_size.y * spritesheet.grid_size.y)


func disable_if_empty():
	var is_empty := Global.spritesheet.is_empty()
	export_sprites.disabled = is_empty
	export_spritesheet.disabled = is_empty
	grid_rows.editable = not is_empty
	grid_columns.editable = not is_empty
	sprite_width.editable = not is_empty
	sprite_height.editable = not is_empty


func show_notification_dialog(title: String, dialog_text: String):
	notification_dialog.title = title
	notification_dialog.dialog_text = dialog_text
	notification_dialog.popup_centered()


func show_confirmation_dialog(title: String, dialog_text: String, confirm_action: Callable):
	confirmation_dialog.title = title
	confirmation_dialog.dialog_text = dialog_text
	confirmation_dialog.confirmed.connect(confirm_action, CONNECT_ONE_SHOT)
	var disconnect_action := confirmation_dialog.confirmed.disconnect.bind(confirm_action)
	if not confirmation_dialog.canceled.is_connected(disconnect_action):
		confirmation_dialog.canceled.connect(disconnect_action, CONNECT_ONE_SHOT)
	confirmation_dialog.popup_centered()


func set_spritesheet_grid_size(columns: int, rows: int):
	var frames_outside_count := 0
	for coord in Global.spritesheet.frames:
		if columns <= coord.x or rows <= coord.y:
			frames_outside_count += 1
	
	var spritesheet_set_size := Global.spritesheet.set_grid_size.bind(Vector2i(columns, rows))
	
	if frames_outside_count > 0:
		show_confirmation_dialog(
			"Confirm resize",
			"Resizing the grid to %d×%d would delete %d sprites." % 
				[columns, rows, frames_outside_count],
			spritesheet_set_size
		)
	else:
		spritesheet_set_size.call()
	Global.spritesheet.updated.emit()


func save_sprites(folder: String):
	var sprites := Global.spritesheet.frames.values()
	var i := 0
	while i < sprites.size():
		sprites[i].save_png(folder + "\\" + str(i) + ".png")
		i += 1
	show_notification_dialog(
		"Saved successfully",
		"Saved %d images to %s." % [sprites.size(), folder.get_file()]
	)


func save_spritesheet(path: String):
	var svp = Global.spritesheet.get_subviewport()
	var popup := Popup.new()
	var svp_container := SubViewportContainer.new()
	popup.size = svp.size
	svp_container.add_child(svp)
	popup.add_child(svp_container)
	popup.position = svp.size * -2
	add_child(popup)
	popup.visible = true
	
	await RenderingServer.frame_post_draw
	
	var spritesheet_image := svp.get_texture().get_image()
	if not spritesheet_image:
		show_notification_dialog(
			"Error",
			"The maximum image size is 16384×16384 pixels due to graphics hardware limitations. Larger images may fail to process.",
		)
		return
	
	var extension := path.get_extension()
	match extension:
		"png":
			spritesheet_image.save_png(path)
		"jpg":
			spritesheet_image.save_jpg(path)
		"webp":
			spritesheet_image.save_webp(path)
	
	popup.queue_free()
	show_notification_dialog(
		"Saved successfully",
		"Saved spritesheet to %s." % [path.get_base_dir().get_file()]
	)
