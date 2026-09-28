class_name AnimationLabels
extends RefCounted
## Names animations on the grid of a [SpritesheetPreview]: a whole row or column in the
## margin where it starts, and other areas outlined with the name on the edge at their
## first frame, see [AnimationLabelLayout]. Each label is in its animation's colour
## ([member SheetAnimation.color]). Names keep the same size at any zoom and are never
## drawn over each other: one that finds no room isn't drawn.
## Only in the grid layout, and only once [member enabled].

## A label was clicked, double-clicked, or right-clicked at [param position] in the view
signal clicked(index: int)
signal double_clicked(index: int)
signal menu_requested(index: int, position: Vector2)
## The label under the mouse changed, -1 when none is
signal hovered_changed(index: int)

const FONT_SIZE := 13
## Space around a name in its tag, and between labels and the grid, on screen
const PADDING := Vector2(5, 1)
const GAP := 6.0
## Space between stacked names
const STACK_GAP := 2.0
## On-screen width of outlines, and how much further inside each overlapping one is drawn
const LINE_WIDTH := 2.0
const INSET_STEP := 2.0
## Opacity of the tint over the frames of the label under the mouse
const HOVER_TINT := 0.25

var enabled := false
## Returns the index of the animation playing in the animation panel, or -1
var get_playing := func() -> int: return -1
## The labels shown: results of [method AnimationLabelLayout.classify], with their
## animation's [code]index[/code], [code]name[/code] and [code]color[/code] and what
## [method AnimationLabelLayout.arrange] says of them
var labels: Array[Dictionary] = []
## The animation whose label is under the mouse, or -1
var hovered := -1

var _sheet := Spritesheet.new()
var _grid := GridView.new()
## The animation playing when the labels were last updated
var _playing := -1
## Where each name was last drawn, on screen, by animation index
var _tags: Dictionary[int, Rect2] = {}
var _palette: AppTheme.Palette
var _palette_for := []
var _tag_box := StyleBoxFlat.new()


func _init() -> void:
	_tag_box.set_corner_radius_all(3)
	_tag_box.set_border_width_all(1)


## Works out the labels again after [param sheet] or the animation playing changed
func update(sheet: Spritesheet, grid: GridView) -> void:
	_sheet = sheet
	_grid = grid
	_playing = get_playing.call()
	labels.clear()
	_tags.clear()
	if enabled and sheet.layout == Spritesheet.Layout.GRID:
		var animations := sheet.animations
		for i in animations.size():
			var shown := i == _playing if sheet.label_playing_only else animations[i].show_label
			if not shown:
				continue
			var label := AnimationLabelLayout.classify(
				animations[i].get_frame_cells(sheet), sheet.grid_size, sheet.has_frame
			)
			if label.shape == AnimationLabelLayout.Shape.NONE:
				continue
			label.index = i
			label.name = animations[i].name
			label.color = animations[i].color
			labels.append(label)
		var arranged := AnimationLabelLayout.arrange(labels)
		for i in labels.size():
			labels[i].merge(arranged[i])
	if not labels.any(func(label: Dictionary) -> bool: return label.index == hovered):
		set_hovered(-1)


## Whether the animation playing changed since the labels were last updated
func is_outdated() -> bool:
	return get_playing.call() != _playing


## Indices of the animations of [param sheet] that can be labelled, see
## [method AnimationLabelLayout.classify]
static func get_labelled(sheet: Spritesheet) -> Array[int]:
	var indices: Array[int] = []
	var animations := sheet.animations
	for i in animations.size():
		var cells := animations[i].get_frame_cells(sheet)
		var shape: int = (
			AnimationLabelLayout.classify(cells, sheet.grid_size, sheet.has_frame).shape
		)
		if shape != AnimationLabelLayout.Shape.NONE:
			indices.append(i)
	return indices


## What the tooltip of a label says, like "6 frames · 12 fps · loop"
static func describe(sheet: Spritesheet, index: int) -> String:
	if index < 0 or index >= sheet.animations.size():
		return ""
	var animation := sheet.animations[index]
	var count := animation.get_frame_cells(sheet).size()
	var frames := TranslationServer.translate("%d frames") % count
	if count == 1:
		frames = TranslationServer.translate("1 frame")
	var fps := animation.fps
	var speed := str(roundi(fps)) if is_equal_approx(fps, roundf(fps)) else String.num(fps, 2)
	var mode: String = SheetAnimation.MODE_NAMES[animation.mode]
	return "%s · %s fps · %s" % [frames, speed, TranslationServer.translate(mode).to_lower()]


func set_hovered(index: int) -> void:
	if index != hovered:
		hovered = index
		hovered_changed.emit(index)


## The animation whose name is at [param position] in the view, or -1
func get_label_at(position: Vector2) -> int:
	for index in _tags:
		if _tags[index].has_point(position):
			return index
	return -1


## Where the animation's name was last drawn in the view, or an empty rectangle
func get_tag_rect(index: int) -> Rect2:
	return _tags.get(index, Rect2())


## Whether a name is drawn over [param rect], on screen, so nothing else is written there
func covers(rect: Rect2) -> bool:
	for index in _tags:
		if _tags[index].intersects(rect):
			return true
	return false


## Room the names need around the grid when it's fitted in the view, on screen: left, top,
## right and bottom
func get_margins() -> Vector4:
	var margins := Vector4.ZERO
	var font := ThemeDB.fallback_font
	for label in labels:
		var size := _tag_size(label.name, font)
		var stacked: float = GAP + label.stack_size * (size.y + STACK_GAP)
		match label.side:
			AnimationLabelLayout.Side.LEFT:
				margins.x = maxf(margins.x, size.x + GAP)
			AnimationLabelLayout.Side.RIGHT:
				margins.z = maxf(margins.z, size.x + GAP)
			AnimationLabelLayout.Side.TOP:
				margins.y = maxf(margins.y, stacked)
			AnimationLabelLayout.Side.BOTTOM:
				margins.w = maxf(margins.w, stacked)
			_:
				# Names of outlines around the top row stand above the grid
				if label.cells[0].y == 0:
					margins.y = maxf(margins.y, size.y)
	return margins


## Handles the mouse over names: hovering, clicking, double-clicking and right-clicking
## them. Returns whether [param event] was handled, so the preview leaves it.
func handle_input(canvas: SpritesheetPreview, event: InputEvent) -> bool:
	var mouse := event as InputEventMouse
	if labels.is_empty() or mouse == null or not canvas.is_idle():
		if mouse != null:
			set_hovered(-1)
		return false
	var index := get_label_at(mouse.position)
	if event is InputEventMouseMotion:
		if index >= 0:
			canvas.clear_hover()
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		if index != hovered:
			set_hovered(index)
			canvas.queue_redraw()
		return index >= 0
	var button := event as InputEventMouseButton
	if index < 0 or button == null:
		return false
	match button.button_index:
		MOUSE_BUTTON_LEFT when button.pressed:
			if button.double_click:
				double_clicked.emit(index)
			else:
				clicked.emit(index)
		MOUSE_BUTTON_RIGHT when not button.pressed:
			menu_requested.emit(index, button.position)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			pass
		_:
			# The wheel still zooms over names
			return false
	return true


#region Drawing


## Works out where each name goes in the view of [param canvas], see
## [method get_tag_rect]. Returns the labels from the most important, the playing one, on:
## names are placed in that order, so the playing one always finds room.
func place_tags(canvas: SpritesheetPreview) -> Array[Dictionary]:
	_tags.clear()
	var order := labels.duplicate()
	order.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if (a.index == _playing) != (b.index == _playing):
				return a.index == _playing
			return a.index < b.index
	)
	var font := ThemeDB.fallback_font
	var wanted: Array[Rect2] = []
	var away: Array[Vector2] = []
	for label: Dictionary in order:
		var spot := _get_tag_spot(canvas, label, font)
		wanted.append(spot[0])
		away.append(spot[1])
	var placed := AnimationLabelLayout.place(wanted, away, STACK_GAP)
	for i in order.size():
		if placed[i].has_area():
			_tags[order[i].index] = placed[i]
	return order


## Draws the outlines and names, over the cells and under the frame numbers
func draw(canvas: SpritesheetPreview) -> void:
	var order := place_tags(canvas)
	if order.is_empty():
		return
	var pixel := 1.0 / canvas.camera.zoom.x
	var palette := _get_palette()
	var font := ThemeDB.fallback_font
	# Drawn from the least important, so the playing one is on top
	order.reverse()
	for label: Dictionary in order:
		if label.index == hovered:
			for cell: Vector2i in label.cells:
				canvas.draw_rect(_grid.get_cell_rect(cell), Color(label.color, HOVER_TINT))
	var outlined := order.filter(AnimationLabelLayout.is_outlined)
	# Every line's halo first, so lines where outlines meet stay whole
	for halo: bool in [true, false]:
		for label: Dictionary in outlined:
			var color: Color = palette.surface if halo else label.color
			var width := (LINE_WIDTH + (2.0 if halo else 0.0)) * pixel
			_draw_outline(canvas, label, color, width, pixel)
	for label: Dictionary in order:
		if _tags.has(label.index):
			_draw_tag(canvas, label, _tags[label.index], font)
	canvas.draw_set_transform(Vector2.ZERO)


func _get_palette() -> AppTheme.Palette:
	var key := [Settings.get_value(&"theme"), Settings.get_value(&"accent_color")]
	if key != _palette_for:
		_palette_for = key
		_palette = AppTheme.palette(key[0] == "light", key[1])
	return _palette


static func _tag_size(text: String, font: Font) -> Vector2:
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	return (size + PADDING * 2).ceil()


## Where a name would go on screen, and the way it may move to make room:
## [code][Rect2, Vector2][/code]
func _get_tag_spot(canvas: SpritesheetPreview, label: Dictionary, font: Font) -> Array:
	var size := _tag_size(label.name, font)
	var step := size.y + STACK_GAP
	var grid_size := _sheet.grid_size
	var line: int = label.line
	var spot := Vector2.ZERO
	var away := Vector2.RIGHT
	match label.side:
		AnimationLabelLayout.Side.LEFT, AnimationLabelLayout.Side.RIGHT:
			var first: Rect2 = to_screen_rect(canvas, _grid.get_cell_rect(Vector2i(0, line)))
			var last: Rect2 = to_screen_rect(
				canvas, _grid.get_cell_rect(Vector2i(grid_size.x - 1, line))
			)
			spot.y = first.get_center().y - size.y / 2
			spot.y += (label.stack - (label.stack_size - 1) / 2.0) * step
			if label.side == AnimationLabelLayout.Side.LEFT:
				spot.x = first.position.x - GAP - size.x
				away = Vector2.LEFT
			else:
				spot.x = last.end.x + GAP
		AnimationLabelLayout.Side.TOP, AnimationLabelLayout.Side.BOTTOM:
			var first: Rect2 = to_screen_rect(canvas, _grid.get_cell_rect(Vector2i(line, 0)))
			var last: Rect2 = to_screen_rect(
				canvas, _grid.get_cell_rect(Vector2i(line, grid_size.y - 1))
			)
			spot.x = first.get_center().x - size.x / 2
			if label.side == AnimationLabelLayout.Side.TOP:
				spot.y = (
					first.position.y - GAP - size.y - (label.stack_size - 1 - label.stack) * step
				)
				away = Vector2.UP
			else:
				spot.y = last.end.y + GAP + label.stack * step
				away = Vector2.DOWN
		_:
			# On the outline's top edge at the first frame, like a tab
			var box: Rect2 = to_screen_rect(canvas, _get_cell_box(label.cells[0]))
			var inset: float = label.inset * INSET_STEP
			spot = box.position + Vector2.ONE * inset
			spot.y += 1 - size.y + label.stack * step
	return [Rect2(spot.round(), size), away]


## [param rect] in the preview's world as it is on screen
static func to_screen_rect(canvas: SpritesheetPreview, rect: Rect2) -> Rect2:
	var zoom := canvas.camera.zoom
	return Rect2((rect.position - canvas.camera.position) * zoom, rect.size * zoom)


## The cell with half the space around it, so the boxes of cells next to each other touch
func _get_cell_box(cell: Vector2i) -> Rect2:
	var gap := _grid.step - Vector2(_sheet.sprite_size)
	return Rect2(_grid.get_cell_rect(cell).position - gap / 2, _grid.step)


## A line around the animation's cells, inside them by its inset
func _draw_outline(
	canvas: SpritesheetPreview, label: Dictionary, color: Color, width: float, pixel: float
) -> void:
	var cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in label.cells:
		cells[cell] = true
	var inside: float = (LINE_WIDTH / 2 + label.inset * INSET_STEP) * pixel
	for cell in cells:
		var box := _get_cell_box(cell)
		for normal: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if cells.has(cell + normal):
				continue
			var along := Vector2i(absi(normal.y), absi(normal.x))
			var middle := box.get_center() + Vector2(normal) * (box.size / 2 - Vector2.ONE * inside)
			var half := (Vector2(along) * box.size / 2).length()
			var ends: Array[Vector2] = []
			for side: int in [-1, 1]:
				# Shorter at outer corners and longer at inner ones, so the lines meet
				var length := half + width / 2
				if not cells.has(cell + along * side):
					length -= inside
				elif cells.has(cell + along * side + normal):
					length += inside
				ends.append(middle + Vector2(along) * side * length)
			canvas.draw_line(ends[0], ends[1], color, width)


## The name in a tag at [param rect] on screen, filled with its animation's colour and
## written in whichever of the theme's text colours reads best on it
func _draw_tag(canvas: SpritesheetPreview, label: Dictionary, rect: Rect2, font: Font) -> void:
	var palette := _get_palette()
	var pixel := 1.0 / canvas.camera.zoom.x
	var fill: Color = label.color
	if label.index == hovered:
		fill = fill.lightened(0.2)
	var ink := AppTheme.readable_text([fill], palette.text)
	_tag_box.bg_color = fill
	_tag_box.border_color = label.color
	# Text is drawn unscaled so it keeps the same size at any zoom
	canvas.draw_set_transform(
		canvas.camera.position + rect.position * pixel, 0, Vector2.ONE * pixel
	)
	canvas.draw_style_box(_tag_box, Rect2(Vector2.ZERO, rect.size))
	var baseline := Vector2(PADDING.x, PADDING.y + font.get_ascent(FONT_SIZE))
	canvas.draw_string(font, baseline, label.name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ink)

#endregion
