class_name Rulers
extends Control
## Rulers along the top and the left of a [SpritesheetPreview] in the grid layout, counting
## the pixels of each cell from its top-left corner, to make guides that are repeated in
## every cell (see [method Spritesheet.get_guides] and [GuideLines]).
##
## Like the rulers of Godot's 2D editor (CanvasItemEditor::_draw_rulers and
## CanvasItemManipulator::_gui_input_rulers_and_guides), but a ruler makes the guides it
## measures: clicking the left ruler adds a horizontal guide there and the top one a
## vertical guide, and dragging from the corner adds both. A guide is dragged by where it
## crosses its ruler, and removed by dropping it on the other ruler, or right-clicking it.
## Double-clicking it types where it goes.

## The guides of the sheet should be [param guides], one list for each axis, as an edit
## named [param action]
signal guides_requested(guides: Array[PackedInt32Array], action: String)

## Thickness of the rulers, Godot's editors/2d/ruler_width
const WIDTH := 16.0
## How near a guide on screen the mouse grabs it
const REACH := 8.0
const FONT_SIZE := 10
## Cells smaller than this on screen get no marks
const MIN_CELL := 4.0

var preview: SpritesheetPreview

## The guide on a ruler under the mouse: across which axis (or -1), and which one
var _hovered_axis := -1
var _hovered := GuideLines.NEW
## Where the grabbed guide is from the mouse, in pixels of the sheet, so it doesn't jump
var _grab := 0.0
var _edit_popup: PopupPanel
var _edit_spin: SpinBox
var _edit_axis := 0
var _edit_guide := 0
var _edit_cancelled := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Shows the rulers and the guides when they're turned on and there are cells, see the
## show_rulers setting
func refresh() -> void:
	var sheet := preview.spritesheet
	var shown: bool = (
		Settings.get_value(&"show_rulers")
		and not preview.is_packed()
		and sheet.sprite_size.x > 0
		and sheet.sprite_size.y > 0
		and sheet.grid_size != Vector2i.ZERO
	)
	if not shown and preview.guides.is_dragging():
		preview.guides.stop_drag()
	visible = shown
	if preview.guides.shown != shown:
		preview.guides.shown = shown
		preview.queue_redraw()
	queue_redraw()


## Only the rulers take the mouse, the preview gets it everywhere else
func _has_point(point: Vector2) -> bool:
	return point.x < WIDTH or point.y < WIDTH


#region Coordinates


## Where [param world] across [param axis] is on screen
func _to_screen(axis: int, world: float) -> float:
	return (world - preview.camera.position[axis]) * preview.camera.zoom[axis]


## The cell at [param world] across [param axis], kept in the grid
func _cell_at(axis: int, world: Vector2) -> int:
	var cell := preview.grid_view.get_cell_unclamped(world)[axis]
	return clampi(cell, 0, maxi(preview.spritesheet.grid_size[axis] - 1, 0))


## Where the cells [param index] across [param axis] start, in pixels of the sheet
func _cell_start(axis: int, index: int) -> float:
	return preview.grid_view.origin[axis] + index * preview.grid_view.step[axis]


## Where the mouse at [param point] is in the cell under it across [param axis], in
## pixels from its top-left corner
func _in_cell(axis: int, point: Vector2) -> float:
	var world := preview.screen_to_world(point)
	return world[axis] - _cell_start(axis, _cell_at(axis, world))


#endregion

#region Input


func _gui_input(event: InputEvent) -> void:
	var guides := preview.guides
	if event is InputEventMouseMotion:
		if guides.is_dragging():
			_drag_to(event.position)
		else:
			_hover(event.position)
		accept_event()
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed and button.double_click and _hovered_axis >= 0:
			_edit(_hovered_axis, _hovered, button.position)
		elif button.pressed:
			_press(button.position)
		elif guides.is_dragging():
			_release(button.position)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_RIGHT and _hovered_axis >= 0:
		if button.pressed:
			_remove(_hovered_axis, _hovered)
		accept_event()


## Esc lets go of the guides dragged, leaving them where they were
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE and preview.guides.is_dragging():
		preview.guides.stop_drag()
		preview.queue_redraw()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not preview.guides.is_dragging():
		_set_hovered(-1, GuideLines.NEW)


## Finds the guide crossing the ruler under [param point]
func _hover(point: Vector2) -> void:
	var sheet := preview.spritesheet
	var axis := -1
	if point.y < WIDTH and point.x >= WIDTH:
		axis = Vector2.AXIS_X
	elif point.x < WIDTH and point.y >= WIDTH:
		axis = Vector2.AXIS_Y
	var found := GuideLines.NEW
	if axis >= 0:
		var start := _cell_start(axis, _cell_at(axis, preview.screen_to_world(point)))
		for guide in sheet.get_guides(axis):
			var at := _to_screen(axis, start + sheet.guide_to_cell(axis, guide))
			if absf(at - point[axis]) <= REACH:
				found = guide
				break
	_set_hovered(axis if found != GuideLines.NEW else -1, found)


func _set_hovered(axis: int, guide: int) -> void:
	if axis == _hovered_axis and guide == _hovered:
		return
	_hovered_axis = axis
	_hovered = guide
	# Godot's cursors: across the guide
	match axis:
		Vector2.AXIS_X:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		Vector2.AXIS_Y:
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


## Grabs the guide under the mouse, or starts new ones: the left ruler makes horizontal
## guides, the top one vertical guides and the corner both
func _press(point: Vector2) -> void:
	var axes: Array[int] = []
	if point.x < WIDTH and point.y < WIDTH:
		axes = [Vector2.AXIS_X, Vector2.AXIS_Y]
	elif point.x < WIDTH:
		axes = [Vector2.AXIS_Y]
	else:
		axes = [Vector2.AXIS_X]
	var grabbed := GuideLines.NEW
	_grab = 0.0
	if axes.size() == 1 and _hovered_axis == axes[0]:
		grabbed = _hovered
		var axis := axes[0]
		_grab = preview.spritesheet.guide_to_cell(axis, grabbed) - _in_cell(axis, point)
	preview.guides.start_drag(axes, grabbed)
	_drag_to(point)


## Moves the dragged guides after the mouse, in the cell under it, on whole pixels.
## Over the ruler a guide is parallel to, it'd be removed, as in Godot.
func _drag_to(point: Vector2) -> void:
	var guides := preview.guides
	var size_in_cell := preview.spritesheet.sprite_size
	for axis in guides.dragged_axes:
		var to := roundi(_in_cell(axis, point) + _grab)
		guides.dragged_to[axis] = clampi(to, 0, size_in_cell[axis])
	if guides.dragged_axes.size() == 2:
		guides.removing = point.x < WIDTH or point.y < WIDTH
	else:
		guides.removing = point[guides.dragged_axes[0]] < WIDTH
	preview.queue_redraw()
	queue_redraw()


func _release(point: Vector2) -> void:
	_drag_to(point)
	var guides := preview.guides
	var sheet := preview.spritesheet
	var dropped := guides.get_dropped_guides(sheet)
	var action := ""
	if guides.dragged_axes.size() == 2:
		action = L10n.mark("Create Horizontal and Vertical Guides")
	elif guides.dragged_axes[0] == Vector2.AXIS_X:
		action = L10n.mark("Create Vertical Guide")
		if guides.grabbed != GuideLines.NEW:
			action = (
				L10n.mark("Remove Vertical Guide")
				if guides.removing
				else L10n.mark("Move Vertical Guide")
			)
	else:
		action = L10n.mark("Create Horizontal Guide")
		if guides.grabbed != GuideLines.NEW:
			action = (
				L10n.mark("Remove Horizontal Guide")
				if guides.removing
				else L10n.mark("Move Horizontal Guide")
			)
	guides.stop_drag()
	_hover(point)
	preview.queue_redraw()
	queue_redraw()
	if dropped != [sheet.get_guides(0), sheet.get_guides(1)]:
		guides_requested.emit(dropped, action)


func _remove(axis: int, guide: int) -> void:
	var sheet := preview.spritesheet
	var dropped: Array[PackedInt32Array] = [sheet.get_guides(0), sheet.get_guides(1)]
	var values := dropped[axis]
	values.remove_at(values.find(guide))
	dropped[axis] = values
	_set_hovered(-1, GuideLines.NEW)
	guides_requested.emit(
		dropped,
		L10n.mark("Remove Vertical Guide") if axis == 0 else L10n.mark("Remove Horizontal Guide")
	)


## Types where the guide goes, in pixels from the cells' top-left corner
func _edit(axis: int, guide: int, point: Vector2) -> void:
	if _edit_popup == null:
		_edit_popup = PopupPanel.new()
		_edit_spin = SpinBox.new()
		_edit_spin.suffix = "px"
		_edit_spin.select_all_on_focus = true
		_edit_popup.add_child(_edit_spin)
		add_child(_edit_popup)
		_edit_spin.get_line_edit().text_submitted.connect(
			func(_text: String) -> void: _edit_popup.hide()
		)
		_edit_popup.window_input.connect(
			func(event: InputEvent) -> void:
				if event.is_action_pressed(&"ui_cancel"):
					_edit_cancelled = true
		)
		_edit_popup.popup_hide.connect(_commit_edit)
	var sheet := preview.spritesheet
	_edit_axis = axis
	_edit_guide = guide
	_edit_cancelled = false
	_edit_spin.max_value = sheet.sprite_size[axis]
	_edit_spin.set_value_no_signal(sheet.guide_to_cell(axis, guide))
	_edit_spin.tooltip_text = (
		TranslationServer.translate("From the left of the cells")
		if axis == Vector2.AXIS_X
		else TranslationServer.translate("From the top of the cells")
	)
	var at := get_screen_transform() * (point + Vector2.ONE * WIDTH)
	_edit_popup.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
	_edit_spin.get_line_edit().grab_focus()


func _commit_edit() -> void:
	_edit_spin.apply()
	if _edit_cancelled:
		return
	var sheet := preview.spritesheet
	if not _edit_guide in sheet.get_guides(_edit_axis):
		return
	var dropped: Array[PackedInt32Array] = [sheet.get_guides(0), sheet.get_guides(1)]
	var values := dropped[_edit_axis]
	values.remove_at(values.find(_edit_guide))
	values.append(sheet.cell_to_guide(_edit_axis, _edit_spin.value))
	dropped[_edit_axis] = values
	var before := sheet.get_guides(_edit_axis)
	values.sort()
	if values != before:
		guides_requested.emit(
			dropped,
			(
				L10n.mark("Move Vertical Guide")
				if _edit_axis == 0
				else L10n.mark("Move Horizontal Guide")
			)
		)


func _get_tooltip(at_position: Vector2) -> String:
	if at_position.x < WIDTH and at_position.y < WIDTH:
		return TranslationServer.translate("Drag to add a horizontal and a vertical guide")
	if _hovered_axis >= 0:
		return TranslationServer.translate(
			(
				"Drag to move the guide, or onto the other ruler to remove it.\n"
				+ "Double-click to type where it goes, right-click to remove it."
			)
		)
	if at_position.x < WIDTH:
		return TranslationServer.translate("Click to add a horizontal guide")
	return TranslationServer.translate("Click to add a vertical guide")


#endregion

#region Drawing


func _draw() -> void:
	var background := get_theme_color(&"background", &"Rulers")
	var text := get_theme_color(&"font_color", &"Rulers")
	var graduation := text.lerp(background, 0.5)
	draw_rect(Rect2(WIDTH, 0, size.x - WIDTH, WIDTH), background)
	draw_rect(Rect2(0, WIDTH, WIDTH, size.y - WIDTH), background)
	for axis in 2:
		_draw_ruler(axis, graduation, text)
	draw_rect(Rect2(0, 0, WIDTH, WIDTH), graduation)
	_draw_dragged_label(text)


## How many pixels apart the numbers are: the first of 1, 2, 5, 10, 20, 50… that's at
## least 60 pixels on screen, as in Godot. (Godot's own steps can be 25, which would leave
## most cells with only a 0.)
static func label_step(zoom: float) -> int:
	var room := 60 * WIDTH / 15.0 / maxf(zoom, SpritesheetPreview.MIN_ZOOM)
	var decade := 1
	while true:
		for times: int in [1, 2, 5]:
			if times * decade >= room:
				return times * decade
		decade *= 10
	return decade


## The ruler across [param axis]: the top one across x, the left one across y. Marks
## count from 0 at each cell's top-left corner, where they're as long as the ruler is
## wide, numbered every [method label_step] pixels with Godot's 10 marks in between, the
## middle one longer.
func _draw_ruler(axis: int, graduation: Color, text: Color) -> void:
	var sheet := preview.spritesheet
	var zoom := preview.camera.zoom[axis]
	var cell := sheet.sprite_size[axis]
	if cell * zoom < MIN_CELL:
		return
	var step := label_step(zoom)
	var tick := maxi(step / 10, 1)
	var font := get_theme_default_font()
	var labelled := cell * zoom >= font.get_string_size("00", 0, -1, FONT_SIZE).x + 6
	var view := Rect2(preview.screen_to_world(Vector2.ZERO), size / preview.camera.zoom)
	var first := maxi(_cell_at(axis, view.position) - 1, 0)
	var last := _cell_at(axis, view.end)
	var guides := preview.guides.get_cell_guides(sheet, axis)
	for index in range(first, last + 1):
		var start := _cell_start(axis, index)
		var marks := range(0, cell, tick)
		marks.append(cell)
		for mark: int in marks:
			var at := roundf(_to_screen(axis, start + mark))
			if at < WIDTH or at > size[axis]:
				continue
			var length := 0.25
			if mark == 0 or mark == cell or mark % step == 0:
				length = 1.0
			elif step % 2 == 0 and mark % (step / 2) == 0:
				length = 0.67
			_draw_tick(axis, at, length, graduation)
			if labelled and mark % step == 0 and mark < cell:
				_draw_label(axis, at, str(mark), text, font)
		for in_cell in guides:
			if in_cell < 0 or in_cell > cell:
				continue
			var at := roundf(_to_screen(axis, start + in_cell))
			if at >= WIDTH and at <= size[axis]:
				var hovered := (
					axis == _hovered_axis and in_cell == sheet.guide_to_cell(axis, _hovered)
				)
				var color := GuideLines.DRAGGED_COLOR if hovered else GuideLines.COLOR
				_draw_tick(axis, at, 1.0, color, 3.0 if hovered else 1.0)


## A mark across the ruler at [param at], [param length] of the ruler's width long from
## its inner edge
func _draw_tick(axis: int, at: float, length: float, color: Color, width := 1.0) -> void:
	var from := Vector2(at, WIDTH * (1 - length))
	var to := Vector2(at, WIDTH)
	if axis == Vector2.AXIS_Y:
		from = Vector2(from.y, from.x)
		to = Vector2(to.y, to.x)
	draw_line(from, to, color, width)


## A number after the mark at [param at], turned on the left ruler like Godot's
func _draw_label(axis: int, at: float, label: String, color: Color, font: Font) -> void:
	var ascent := font.get_ascent(FONT_SIZE)
	if axis == Vector2.AXIS_X:
		draw_string(
			font, Vector2(at + 2, ascent), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color
		)
		return
	draw_set_transform(Vector2(ascent, at - 2), -PI / 2)
	draw_string(font, Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Where the dragged guides would go, next to them as in Godot
func _draw_dragged_label(color: Color) -> void:
	var guides := preview.guides
	if not guides.is_dragging() or guides.removing:
		return
	var font := get_theme_default_font()
	var font_size := 13
	var outline := color.inverted()
	var mouse := get_local_mouse_position()
	for axis in guides.dragged_axes:
		var label := TranslationServer.translate("%d px") % guides.dragged_to[axis]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var start := _cell_start(axis, _cell_at(axis, preview.screen_to_world(mouse)))
		var at := _to_screen(axis, start + guides.dragged_to[axis])
		var position := Vector2(at + 10, WIDTH + text_size.y / 2 + 10)
		if axis == Vector2.AXIS_Y:
			position = Vector2(WIDTH + 10, at + text_size.y / 2 + 10)
		draw_string_outline(
			font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, outline
		)
		draw_string(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

#endregion
