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
	spritesheet_preview.zoom_changed.connect(update_zoom_label)
	update_zoom_label(spritesheet_preview.camera.zoom.x)


func update_zoom_label(value: float) -> void:
	zoom.text = "%d%%" % roundi(value * 100)


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

	var selection_size := spritesheet_preview.get_selected_coords().size()
	var selection_empty := is_empty or selection_size == 0
	num_selected.visible = not selection_empty
	num_selected.text = "%d selected" % [selection_size]

	for i in options_menu.item_count:
		options_menu.set_item_disabled(i, selection_empty)


func select_all(select: bool) -> void:
	for frame: SpritesheetPreviewFrame in spritesheet_preview.frames.get_children():
		frame.selected = select


func options_menu_item_pressed(id: int):
	var sheet: Spritesheet = spritesheet_preview.spritesheet
	var selected := spritesheet_preview.get_selected_coords()
	match id:
		0:
			sheet.flip_frames(selected, true)
		1:
			sheet.flip_frames(selected, false)
		2:
			sheet.rotate_frames(selected, true)
		3:
			sheet.rotate_frames(selected, false)
		4:
			sheet.remove_frames(selected)

	# The preview is rebuilt at the end of the frame, restore the selection after that
	await get_tree().process_frame
	spritesheet_preview.set_selected_coords(selected)
