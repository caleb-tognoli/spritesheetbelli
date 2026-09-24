class_name PreviewArea
extends Control

@onready var options_menu: ActionPopupMenu = $OptionsMenu
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
	spritesheet_preview.zoom_changed.connect(update_zoom_label)
	update_zoom_label(spritesheet_preview.camera.zoom.x)


func update_zoom_label(value: float) -> void:
	zoom.text = "%d%%" % roundi(value * 100)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if options_menu.item_count == 0:
				return
			if options_menu.visible:
				options_menu.visible = false
			else:
				# The screen transform accounts for the window position and display scaling
				var screen_position := get_screen_transform() * (event.position as Vector2)
				options_menu.popup(Rect2i(Vector2i(screen_position), Vector2i.ZERO))


func update_ui() -> void:
	var is_empty := spritesheet_preview.spritesheet.is_empty()
	select_all_btn.visible = not is_empty
	select_none_btn.visible = not is_empty

	var selection_size := spritesheet_preview.get_selected_coords().size()
	var selection_empty := is_empty or selection_size == 0
	num_selected.visible = not selection_empty
	num_selected.text = "%d selected" % [selection_size]


## Actions offered when right-clicking the preview
func set_context_actions(ids: Array[StringName]) -> void:
	options_menu.set_actions(ids)


func select_all(select: bool) -> void:
	for frame: SpritesheetPreviewFrame in spritesheet_preview.frames.get_children():
		frame.selected = select
