class_name PreviewArea
extends Control

@onready var options_menu: ActionPopupMenu = $OptionsMenu
@onready var spritesheet_preview: SpritesheetPreview = %SpritesheetPreview
@onready var select_all_btn: Button = %SelectAll
@onready var select_none_btn: Button = %SelectNone
@onready var num_selected: Label = %NumSelected

@onready var zoom: MenuButton = %Zoom
@onready var container: SubViewportContainer = $PreviewContainer

var animation_preview := AnimationPreview.new()
## Shown in the middle while the spritesheet is empty. Hidden when empty.
var empty_hint := Label.new()

const ZOOM_PRESETS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
const ZOOM_FIT_ID := 100


func _ready() -> void:
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_hint.theme_type_variation = &"EmptyHint"
	add_child(empty_hint)
	move_child(empty_hint, container.get_index() + 1)

	var zoom_menu := zoom.get_popup()
	for preset in ZOOM_PRESETS:
		zoom_menu.add_item("%d%%" % roundi(preset * 100), ZOOM_PRESETS.find(preset))
	zoom_menu.add_separator()
	zoom_menu.add_item("Fit to View", ZOOM_FIT_ID)
	zoom_menu.id_pressed.connect(
		func(id: int) -> void:
			if id == ZOOM_FIT_ID:
				spritesheet_preview.fit_to_view()
			else:
				spritesheet_preview.set_zoom(ZOOM_PRESETS[id], container.size / 2)
	)
	animation_preview.preview = spritesheet_preview
	animation_preview.visible = false
	add_child(animation_preview)
	animation_preview.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	animation_preview.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	animation_preview.grow_vertical = Control.GROW_DIRECTION_BEGIN
	animation_preview.position -= Vector2(10, 44)
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
	empty_hint.visible = is_empty and not empty_hint.text.is_empty()
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
	var index: int = sheet.index_of(coord) + Settings.get_value(&"index_start")
	var position := "Cell %d (column %d, row %d)" % [index, coord.x, coord.y]
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
