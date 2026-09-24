class_name PreviewArea
extends Control

@onready var options_menu: ActionPopupMenu = $OptionsMenu
@onready var spritesheet_preview: SpritesheetPreview = %SpritesheetPreview
@onready var select_all_btn: Button = %SelectAll
@onready var select_none_btn: Button = %SelectNone
@onready var num_selected: Label = %NumSelected

@onready var zoom: Label = %Zoom
@onready var container: SubViewportContainer = $PreviewContainer


func _ready() -> void:
	update_ui()
	spritesheet_preview.preview_updated.connect(update_ui)
	select_all_btn.pressed.connect(select_all.bind(true))
	select_none_btn.pressed.connect(select_all.bind(false))
	spritesheet_preview.zoom_changed.connect(update_zoom_label)
	spritesheet_preview.hover_changed.connect(update_tooltip)
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
	spritesheet_preview.select_all(select)


## Describes the cell under the mouse
func update_tooltip(coord: Vector2i) -> void:
	container.tooltip_text = describe_cell(spritesheet_preview.spritesheet, coord)


static func describe_cell(sheet: Spritesheet, coord: Vector2i) -> String:
	if not sheet.is_inside(coord):
		return ""
	var position := "Cell %d (column %d, row %d)" % [sheet.index_of(coord), coord.x, coord.y]
	if sheet.has_frame(coord):
		var source := sheet.frames[coord]
		var size := sheet.get_frame_image(coord).get_size()
		var text := "%s\n%d×%d px" % [position, size.x, size.y]
		if source.resource_name:
			text += "\n" + source.resource_name
		return text
	if sheet.is_locked(coord):
		return "%s\nLocked: kept empty when adding sprites. Click to unlock." % position
	return "%s\nEmpty. Click to lock it so added sprites skip it." % position
