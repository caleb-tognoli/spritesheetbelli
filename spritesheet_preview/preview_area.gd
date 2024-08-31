class_name PreviewArea
extends Control


@onready var options_menu: PopupMenu = $OptionsMenu
@onready var spritesheet_preview: SpritesheetPreview = %SpritesheetPreview
@onready var select_all_btn: Button = %SelectAll
@onready var select_none_btn: Button = %SelectNone
@onready var num_selected: Label = %NumSelected

@onready var zoom: Label = %Zoom


func _ready() -> void:
	update_ui()
	spritesheet_preview.preview_updated.connect(update_ui)
	select_all_btn.pressed.connect(select_all.bind(true))
	select_none_btn.pressed.connect(select_all.bind(false))
	options_menu.id_pressed.connect(options_menu_item_pressed)


func _process(_delta: float) -> void:
	zoom.text = str(spritesheet_preview.camera.zoom.x * 100).pad_decimals(0) + "%"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if options_menu.visible:
				options_menu.visible = false
			else:
				options_menu.position = get_window().position + Vector2i(event.global_position)
				options_menu.show()


func update_ui() -> void:
	var is_empty := spritesheet_preview.spritesheet.is_empty()
	select_all_btn.visible = not is_empty
	select_none_btn.visible = not is_empty
	
	var selection_size := spritesheet_preview.get_selected_frames().size()
	var selection_empty := is_empty or selection_size == 0
	num_selected.visible = not selection_empty
	num_selected.text = "%d selected" % [selection_size]
	
	for i in options_menu.item_count:
		options_menu.set_item_disabled(i, selection_empty)


func select_all(select: bool) -> void:
	for frame: SpritesheetPreviewFrame in spritesheet_preview.frames.get_children():
		frame.selected = select


func options_menu_item_pressed(id: int):
	var selected_frames: Dictionary = spritesheet_preview.get_selected_frames()
	match id:
		0:
			for frame: Image in selected_frames.values():
				frame.flip_x()
		1:
			for frame: Image in selected_frames.values():
				frame.flip_y()
		2, 3:
			var max_sprite_size: Vector2i = spritesheet_preview.spritesheet.sprite_size
			for frame: Image in selected_frames.values():
				if id == 2:
					frame.rotate_90(CLOCKWISE)
				else:
					frame.rotate_90(COUNTERCLOCKWISE)
				var frame_new_size := frame.get_size()
				max_sprite_size.x = max(max_sprite_size.x, frame_new_size.x)
				max_sprite_size.y = max(max_sprite_size.y, frame_new_size.y)
			spritesheet_preview.spritesheet.sprite_size = max_sprite_size
			spritesheet_preview.spritesheet.pad_frames_to_sprite_size()
		4:
			for coord: Vector2i in selected_frames:
				spritesheet_preview.spritesheet.frames.erase(coord)
	
	spritesheet_preview.spritesheet.updated.emit()
	
	for coord: Vector2i in selected_frames:
		for frame: SpritesheetPreviewFrame in spritesheet_preview.frames.get_children():
			if frame.coordinate_in_spritesheet == coord:
				frame.selected = true
