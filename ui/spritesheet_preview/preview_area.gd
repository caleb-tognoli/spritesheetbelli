class_name PreviewArea
extends Control
## The spritesheet preview with its toolbar: the select and move tools, selection
## buttons and zoom, like the toolbar above Godot's 2D editor.

const SELECT_ICON := preload("res://assets/icons/ToolSelect.svg")
const MOVE_ICON := preload("res://assets/icons/ToolMove.svg")
const SELECT_ALL_ICON := preload("res://assets/icons/ListSelect.svg")
const SELECT_NONE_ICON := preload("res://assets/icons/Clear.svg")
const ZOOM_OUT_ICON := preload("res://assets/icons/ZoomLess.svg")
const ZOOM_IN_ICON := preload("res://assets/icons/ZoomMore.svg")

@onready var options_menu: ActionPopupMenu = $OptionsMenu
@onready var spritesheet_preview: SpritesheetPreview = %SpritesheetPreview
@onready var toolbar: PanelContainer = %Toolbar
@onready var stage: Control = %Stage
@onready var container: SubViewportContainer = %PreviewContainer

var select_tool_btn := _tool_button(SELECT_ICON)
var move_tool_btn := _tool_button(MOVE_ICON)
var select_all_btn := _tool_button(SELECT_ALL_ICON, "Select all frames (Ctrl+A)")
var select_none_btn := _tool_button(SELECT_NONE_ICON, "Clear the selection (Esc)")
var num_selected := Label.new()
var zoom_out_btn := _tool_button(ZOOM_OUT_ICON, "Zoom out (Ctrl+Minus)")
var zoom_label_btn := _tool_button(null, "Fit to view (F)")
var zoom_in_btn := _tool_button(ZOOM_IN_ICON, "Zoom in (Ctrl+Equal)")
var animation_preview := AnimationPreview.new()
## Shown in the middle while the spritesheet is empty. Hidden when empty.
var empty_hint := Label.new()

var _tool_group := HBoxContainer.new()
var _tool_separator := VSeparator.new()


func _ready() -> void:
	_build_toolbar()
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_hint.theme_type_variation = &"EmptyHint"
	stage.add_child(empty_hint)

	animation_preview.preview = spritesheet_preview
	animation_preview.visible = false
	stage.add_child(animation_preview)
	animation_preview.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	animation_preview.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	animation_preview.grow_vertical = Control.GROW_DIRECTION_BEGIN
	animation_preview.position -= Vector2(10, 10)
	update_ui()
	spritesheet_preview.preview_updated.connect(update_ui)
	spritesheet_preview.zoom_changed.connect(update_zoom_label)
	spritesheet_preview.hover_changed.connect(update_tooltip)
	spritesheet_preview.tool_changed.connect(func(_tool: int) -> void: update_ui())
	update_zoom_label(spritesheet_preview.camera.zoom.x)


func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	toolbar.add_child(bar)

	# Tools
	var tools := ButtonGroup.new()
	select_tool_btn.tooltip_text = "Select mode (Q): click or drag to select frames"
	move_tool_btn.tooltip_text = (
		"Move mode (W): drag to move the selected frames, or the dragged one. " + "Alt+drag copies."
	)
	for button: Button in [select_tool_btn, move_tool_btn]:
		button.toggle_mode = true
		button.button_group = tools
		_tool_group.add_child(button)
	select_tool_btn.button_pressed = true
	select_tool_btn.pressed.connect(set_tool.bind(SpritesheetPreview.Tool.SELECT))
	move_tool_btn.pressed.connect(set_tool.bind(SpritesheetPreview.Tool.MOVE))
	bar.add_child(_tool_group)
	bar.add_child(_tool_separator)

	# Selection
	bar.add_child(select_all_btn)
	bar.add_child(select_none_btn)
	num_selected.theme_type_variation = &"StatusLabel"
	bar.add_child(num_selected)
	select_all_btn.pressed.connect(select_all.bind(true))
	select_none_btn.pressed.connect(select_all.bind(false))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# Zoom, like Godot: the percentage fits the view
	zoom_label_btn.custom_minimum_size.x = 56
	for button: Button in [zoom_out_btn, zoom_label_btn, zoom_in_btn]:
		bar.add_child(button)
	zoom_out_btn.pressed.connect(func() -> void: spritesheet_preview.zoom_by(0.8))
	zoom_in_btn.pressed.connect(func() -> void: spritesheet_preview.zoom_by(1.25))
	zoom_label_btn.pressed.connect(func() -> void: spritesheet_preview.fit_to_view())


static func _tool_button(icon: Texture2D, tooltip := "") -> Button:
	var button := Button.new()
	button.theme_type_variation = &"ToolbarButton"
	button.icon = icon
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	return button


func set_tool(value: SpritesheetPreview.Tool) -> void:
	spritesheet_preview.tool = value
	update_ui()


func update_zoom_label(value: float) -> void:
	zoom_label_btn.text = "%d%%" % roundi(value * 100)


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
	select_all_btn.disabled = is_empty

	var can_move := spritesheet_preview.able_to_move_frames
	_tool_group.visible = can_move
	_tool_separator.visible = can_move
	var moving := spritesheet_preview.tool == SpritesheetPreview.Tool.MOVE
	select_tool_btn.set_pressed_no_signal(not moving)
	move_tool_btn.set_pressed_no_signal(moving)
	container.mouse_default_cursor_shape = (Control.CURSOR_MOVE if moving else Control.CURSOR_ARROW)

	var selection_size := spritesheet_preview.get_selected_coords().size()
	var selection_empty := is_empty or selection_size == 0
	select_none_btn.visible = not selection_empty
	num_selected.visible = not selection_empty
	num_selected.text = tr("%d selected") % selection_size


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
	var cell_text := (
		TranslationServer.translate("Cell %d (column %d, row %d)") % [index, coord.x, coord.y]
	)
	if sheet.has_frame(coord):
		var source := sheet.frames[coord]
		var frame_size := sheet.get_frame_rect_in_cell(coord).size
		var text := "%s\n%d×%d px" % [cell_text, frame_size.x, frame_size.y]
		if source.resource_name:
			text += "\n" + source.resource_name
		return text
	if sheet.is_locked(coord):
		return (
			"%s\n%s"
			% [
				cell_text,
				TranslationServer.translate(
					"Locked: kept empty when adding sprites. Click to unlock."
				)
			]
		)
	return (
		"%s\n%s"
		% [
			cell_text,
			TranslationServer.translate("Empty. Click to lock it so added sprites skip it.")
		]
	)
