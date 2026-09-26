class_name PreviewArea
extends Control
## The spritesheet preview with its toolbar: the select, move and pivot tools and the
## actions given to [method set_toolbar_actions], like the toolbar above Godot's 2D editor.
## Zoom and centring the view float over the top-right corner, and notices over the
## bottom-right one, see [method show_notice].

const SELECT_ICON := preload("res://assets/icons/ToolSelect.svg")
const MOVE_ICON := preload("res://assets/icons/ToolMove.svg")
const PIVOT_ICON := preload("res://assets/icons/EditPivot.svg")
const SELECT_ALL_ICON := preload("res://assets/icons/ListSelect.svg")
const SELECT_NONE_ICON := preload("res://assets/icons/Clear.svg")
const ZOOM_OUT_ICON := preload("res://assets/icons/ZoomLess.svg")
const ZOOM_IN_ICON := preload("res://assets/icons/ZoomMore.svg")
const CENTER_VIEW_ICON := preload("res://assets/icons/CenterView.svg")
const WARNING_ICON := preload("res://assets/icons/StatusWarning.svg")

@onready var options_menu: ActionPopupMenu = $OptionsMenu
@onready var spritesheet_preview: SpritesheetPreview = %SpritesheetPreview
@onready var toolbar: PanelContainer = %Toolbar
@onready var stage: Control = %Stage
@onready var container: SubViewportContainer = %PreviewContainer

var select_tool_btn := _tool_button(SELECT_ICON)
var move_tool_btn := _tool_button(MOVE_ICON)
var pivot_tool_btn := _tool_button(PIVOT_ICON)
var center_view_btn := _tool_button(CENTER_VIEW_ICON, "Fit to view (F)")
var zoom_out_btn := _tool_button(ZOOM_OUT_ICON, "Zoom out (Ctrl+Minus)")
var zoom_label_btn := _tool_button(null, "Actual size (Ctrl+0)")
var zoom_in_btn := _tool_button(ZOOM_IN_ICON, "Zoom in (Ctrl+Equal)")
## Something to know about what's shown, with a warning icon, in the bottom-right corner
var notice := PanelContainer.new()
var notice_label := Label.new()
var animation_preview := AnimationPreview.new()
## Shown in the middle while the spritesheet is empty. Hidden when empty.
var empty_hint := Label.new()

var _tool_group := HBoxContainer.new()
## Action buttons after the tools, and view toggles before the zoom
var _edit_bar := HBoxContainer.new()
var _view_bar := HBoxContainer.new()
## Buttons that run actions, by action id, kept enabled and checked like their actions
var _action_buttons: Dictionary[StringName, Button] = {}
## Buttons that open a menu of actions, with the ids in it
var _menu_buttons: Dictionary[Button, Array] = {}


func _ready() -> void:
	# Never wider than its place: a toolbar that doesn't fit wraps instead
	var layout := $Layout as Control
	layout.grow_horizontal = Control.GROW_DIRECTION_END
	layout.minimum_size_changed.connect(update_minimum_size)
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
	_build_overlay()
	update_ui()
	spritesheet_preview.preview_updated.connect(update_ui)
	spritesheet_preview.zoom_changed.connect(update_zoom_label)
	spritesheet_preview.hover_changed.connect(update_tooltip)
	spritesheet_preview.tool_changed.connect(func(_tool: int) -> void: update_ui())
	update_zoom_label(spritesheet_preview.camera.zoom.x)


func _build_toolbar() -> void:
	# Wraps onto a second row when the preview is too narrow for every button
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 2)
	bar.add_theme_constant_override("v_separation", 2)
	toolbar.add_child(bar)

	# Tools
	var tools := ButtonGroup.new()
	select_tool_btn.tooltip_text = "Select mode (Q): click or drag to select frames"
	move_tool_btn.tooltip_text = (
		"Move mode (W): drag to move the selected frames, or the dragged one; Alt+drag "
		+ "copies. Arrow keys move the selected frames inside their cells."
	)
	pivot_tool_btn.tooltip_text = (
		"Pivot mode (E): drag on a frame to put the pivot of the selected frames " + "there"
	)
	for button: Button in [select_tool_btn, move_tool_btn, pivot_tool_btn]:
		button.toggle_mode = true
		button.button_group = tools
		_tool_group.add_child(button)
	select_tool_btn.button_pressed = true
	select_tool_btn.pressed.connect(set_tool.bind(SpritesheetPreview.Tool.SELECT))
	move_tool_btn.pressed.connect(set_tool.bind(SpritesheetPreview.Tool.MOVE))
	pivot_tool_btn.pressed.connect(set_tool.bind(SpritesheetPreview.Tool.PIVOT))
	bar.add_child(_tool_group)

	for group: HBoxContainer in [_edit_bar, _view_bar]:
		group.add_theme_constant_override("separation", 2)
	bar.add_child(_edit_bar)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(_view_bar)


## Zoom and centring over the top-right corner of the preview, like Godot's 2D editor,
## and the notice over the bottom-right one
func _build_overlay() -> void:
	var overlay := VBoxContainer.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("separation", 6)
	var zoom := PanelContainer.new()
	zoom.theme_type_variation = &"PreviewOverlay"
	zoom.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	zoom.add_child(row)
	zoom_label_btn.custom_minimum_size.x = 56
	for button: Button in [center_view_btn, zoom_out_btn, zoom_label_btn, zoom_in_btn]:
		row.add_child(button)
	overlay.add_child(zoom)
	center_view_btn.pressed.connect(func() -> void: spritesheet_preview.fit_to_view())
	zoom_out_btn.pressed.connect(func() -> void: spritesheet_preview.zoom_by(0.8))
	zoom_in_btn.pressed.connect(func() -> void: spritesheet_preview.zoom_by(1.25))
	# The percentage goes back to 100%
	zoom_label_btn.pressed.connect(
		func() -> void:
			spritesheet_preview.set_zoom(1, spritesheet_preview.get_viewport_rect().size / 2)
	)

	notice.theme_type_variation = &"PreviewOverlay"
	notice.visible = false
	var notice_row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = WARNING_ICON
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	notice_row.add_child(icon)
	notice_row.add_child(notice_label)
	notice.add_child(notice_row)

	stage.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10
	)
	overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stage.add_child(notice)
	notice.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10
	)
	notice.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	notice.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Shows [param text] with a warning icon over the preview, or hides it when empty
func show_notice(text: String, tooltip := "") -> void:
	notice_label.text = text
	notice.tooltip_text = tooltip
	notice.visible = not text.is_empty()


## As wide as the toolbar's widest group, so the splits around the preview never squeeze
## it narrower than its toolbar
func _get_minimum_size() -> Vector2:
	var layout := get_node_or_null(^"Layout") as Control
	return Vector2(layout.get_combined_minimum_size().x, 0) if layout else Vector2.ZERO


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

	var can_move := spritesheet_preview.able_to_move_frames
	_tool_group.visible = can_move
	_update_separators()
	var moving := spritesheet_preview.tool == SpritesheetPreview.Tool.MOVE
	select_tool_btn.set_pressed_no_signal(
		spritesheet_preview.tool == SpritesheetPreview.Tool.SELECT
	)
	move_tool_btn.set_pressed_no_signal(moving)
	pivot_tool_btn.set_pressed_no_signal(spritesheet_preview.tool == SpritesheetPreview.Tool.PIVOT)
	container.mouse_default_cursor_shape = (Control.CURSOR_MOVE if moving else Control.CURSOR_ARROW)


## Adds buttons for actions to the toolbar: [param edit_groups] are arrays of action ids
## after the tools, each group after a separator, and [param view_ids] are
## toggles before the zoom. An id in [param submenus] (as in
## [method ActionPopupMenu.set_actions]) is a button that opens that menu.
func set_toolbar_actions(edit_groups: Array, view_ids: Array[StringName], submenus := {}) -> void:
	for group: Array in edit_groups:
		_edit_bar.add_child(VSeparator.new())
		for id: StringName in group:
			_edit_bar.add_child(_action_button(id, submenus))
	for id in view_ids:
		_view_bar.add_child(_action_button(id, submenus))
	if not Actions.state_changed.is_connected(_refresh_action_buttons):
		Actions.state_changed.connect(_refresh_action_buttons)
	_refresh_action_buttons()


func _action_button(id: StringName, submenus: Dictionary) -> Button:
	if submenus.has(id):
		var entry: Array = submenus[id]
		var menu_button := _tool_button(entry[2] if entry.size() > 2 else null, entry[0])
		var menu := ActionPopupMenu.new()
		menu_button.add_child(menu)
		var ids: Array[StringName] = []
		ids.assign(entry[1])
		menu.set_actions(ids, submenus)
		menu_button.pressed.connect(
			func() -> void:
				var below := menu_button.get_screen_transform() * Vector2(0, menu_button.size.y)
				menu.popup(Rect2i(Vector2i(below), Vector2i.ZERO))
		)
		_menu_buttons[menu_button] = ids
		return menu_button
	var action := Actions.get_action(id)
	var button := _tool_button(action.icon, action.label.trim_suffix("…"))
	var shortcut := Actions.get_shortcut_text(id)
	if shortcut:
		button.tooltip_text += " (%s)" % shortcut
	button.toggle_mode = Actions.is_toggle(id)
	button.pressed.connect(func() -> void: Actions.run(id))
	_action_buttons[id] = button
	return button


func _refresh_action_buttons() -> void:
	# Pivots are opt-in, see the use_pivots setting
	pivot_tool_btn.visible = Actions.is_available(&"tool_pivot")
	for id in _action_buttons:
		var button := _action_buttons[id]
		button.visible = Actions.is_available(id)
		button.disabled = not Actions.is_enabled(id)
		if button.toggle_mode:
			button.set_pressed_no_signal(Actions.is_checked(id))
	for button in _menu_buttons:
		var ids: Array = _menu_buttons[button]
		button.visible = ids.any(
			func(id: StringName) -> bool: return not id.is_empty() and Actions.is_available(id)
		)
		button.disabled = not ids.any(
			func(id: StringName) -> bool: return not id.is_empty() and Actions.is_enabled(id)
		)
	_update_separators()


## A group's separator only shows between buttons: after the tools or an earlier group,
## and before a button of its own group
func _update_separators() -> void:
	var before := _tool_group.visible
	var separator: VSeparator = null
	for child: Control in _edit_bar.get_children():
		if child is VSeparator:
			separator = child
			separator.visible = false
		elif child.visible:
			if separator and before:
				separator.visible = true
			before = true


## Actions offered when right-clicking the preview, with [param submenus] as in
## [method ActionPopupMenu.set_actions]
func set_context_actions(ids: Array[StringName], submenus := {}) -> void:
	options_menu.set_actions(ids, submenus)


func select_all(select: bool) -> void:
	spritesheet_preview.select_all(select)


## Describes the cell under the mouse
func update_tooltip(coord: Vector2i) -> void:
	container.tooltip_text = describe_cell(spritesheet_preview.spritesheet, coord)


static func describe_cell(sheet: Spritesheet, coord: Vector2i) -> String:
	if sheet.layout == Spritesheet.Layout.PACKED:
		return describe_packed_frame(sheet, coord)
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
		var link: Dictionary = sheet.frame_sources.get(coord, {})
		if link:
			text += "\n" + describe_link(link)
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


## Describes a frame in the packed layout: its name, where it is and how it's packed
static func describe_packed_frame(sheet: Spritesheet, coord: Vector2i) -> String:
	var place: Dictionary = sheet.placements.get(coord, {})
	if place.is_empty():
		return ""
	var index: int = sheet.index_of(coord) + Settings.get_value(&"index_start")
	var lines := PackedStringArray()
	var frame_name := sheet.frames[coord].resource_name
	lines.append(
		TranslationServer.translate("Frame %d") % index + (" · " + frame_name if frame_name else "")
	)
	var rect := PackedLayout.get_rect(sheet, coord)
	lines.append(
		(
			TranslationServer.translate("Page %d at %d, %d · %d×%d px")
			% [place.page + 1, rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		)
	)
	var notes := PackedStringArray()
	if place.rotated:
		notes.append(TranslationServer.translate("turned"))
	if place.get("pinned", false):
		notes.append(TranslationServer.translate("pinned"))
	for other: Vector2i in sheet.placements:
		var other_place: Dictionary = sheet.placements[other]
		if (
			other != coord
			and other_place.page == place.page
			and other_place.position == place.position
		):
			notes.append(
				TranslationServer.translate("shares its place with a frame that looks the same")
			)
			break
	if notes:
		lines.append(", ".join(notes))
	var link: Dictionary = sheet.frame_sources.get(coord, {})
	if link:
		lines.append(describe_link(link))
	return "\n".join(lines)


## The file a linked frame comes from, and whether it was edited here since
static func describe_link(link: Dictionary) -> String:
	var text: String = link.path
	if FrameSource.has_edits(link):
		text += " " + TranslationServer.translate("(edited here)")
	return text
