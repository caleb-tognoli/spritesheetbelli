class_name PackedView
extends RefCounted
## How a [SpritesheetPreview] shows the packed layout: the pages side by side, each frame
## where it's packed, and an empty page after them to drop frames on.

const PAGE_LABEL_SIZE := 13
const PAGE_BORDER_COLOR := Color(1, 1, 1, 0.35)
const NEW_PAGE_COLOR := Color(1, 1, 1, 0.12)
const OUTLINE_COLOR := Color(1, 1, 1, 0.3)
const PIN_ICON := preload("res://assets/icons/Pin.svg")
## On-screen size of the pin on pinned frames
const PIN_SIZE := 16.0
const PIN_BACKGROUND := Color(0, 0, 0, 0.55)
const TURNED_COLOR := Color(0.5, 0.8, 1.0)

var sheet: Spritesheet
## Size of each page
var page_sizes: Array[Vector2i] = []
## Top-left corner of each page in the preview, and of the empty page after them
var page_origins: Array[Vector2] = []
## Frames in drawing order, the last on top
var _order: Array[Vector2i] = []


## Measures the pages again after the sheet changed
func update(value: Spritesheet) -> void:
	sheet = value
	page_sizes = PackedLayout.get_page_sizes(sheet)
	page_origins.clear()
	var x := 0.0
	var biggest := Vector2i.ONE * 64
	for size in page_sizes:
		biggest = biggest.max(size)
	var gap := maxf(24.0, maxf(biggest.x, biggest.y) * 0.06)
	for size in page_sizes:
		page_origins.append(Vector2(x, 0))
		x += size.x + gap
	page_origins.append(Vector2(x, 0))
	_order = sheet.get_sorted_coords().filter(
		func(c: Vector2i) -> bool: return sheet.placements.has(c)
	)


## The empty page after the others, where frames can be dropped to start a new page
func get_new_page_rect() -> Rect2:
	var size := Vector2i.ONE * 64
	for page_size in page_sizes:
		size = size.max(page_size)
	return Rect2(page_origins[-1], Vector2(size))


func get_page_rect(page: int) -> Rect2:
	if page >= page_sizes.size():
		return get_new_page_rect()
	return Rect2(page_origins[page], Vector2(page_sizes[page]))


## Every page, not the empty one
func get_content_rect() -> Rect2:
	var rect := Rect2()
	for page in page_sizes.size():
		rect = get_page_rect(page) if page == 0 else rect.merge(get_page_rect(page))
	return rect


## Where the frame is drawn, as it's stored: turned frames are as wide as they're tall
func get_frame_rect(coord: Vector2i) -> Rect2:
	var place: Dictionary = sheet.placements.get(coord, {})
	if place.is_empty():
		return Rect2()
	var rect := PackedLayout.get_rect(sheet, coord)
	return Rect2(page_origins[place.page] + Vector2(rect.position), Vector2(rect.size))


## The page under [param world], counting the empty page after the others, or -1
func get_page_at(world: Vector2) -> int:
	for page in page_origins.size():
		if get_page_rect(page).has_point(world):
			return page
	return -1


## The frame drawn on top at [param world], or NO_CELL
func get_frame_at(world: Vector2) -> Vector2i:
	for i in range(_order.size() - 1, -1, -1):
		if get_frame_rect(_order[i]).has_point(world):
			return _order[i]
	return Spritesheet.NO_CELL


func get_frames_in(box: Rect2) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in _order:
		if box.intersects(get_frame_rect(coord)):
			coords.append(coord)
	return coords


## The nearest frame from [param from] in [param direction], or [param from] when there's none
func get_neighbour(from: Vector2i, direction: Vector2i) -> Vector2i:
	var start := get_frame_rect(from).get_center()
	var best := from
	var best_score := INF
	for coord in _order:
		var delta := get_frame_rect(coord).get_center() - start
		var along := delta.dot(Vector2(direction))
		if coord == from or along <= 0:
			continue
		var score := along + absf(delta.dot(Vector2(direction.y, direction.x))) * 2
		if score < best_score:
			best_score = score
			best = coord
	return best


## Where a pivot (in unscaled pixels of the frame) is in the preview
func pivot_to_world(coord: Vector2i, pivot: Vector2) -> Vector2:
	var place: Dictionary = sheet.placements[coord]
	var rect := get_frame_rect(coord)
	var src: Rect2i = place.src
	var point := pivot * sheet.frame_scale - Vector2(src.position)
	if place.rotated:
		# Stored turned clockwise: the frame's left edge is the top of the stored pixels
		return rect.position + Vector2(src.size.y - point.y, point.x)
	return rect.position + point


## The pivot (in unscaled pixels of the frame) at [param world]
func world_to_pivot(coord: Vector2i, world: Vector2) -> Vector2:
	var place: Dictionary = sheet.placements[coord]
	var rect := get_frame_rect(coord)
	var src: Rect2i = place.src
	var local := world - rect.position
	var point := local
	if place.rotated:
		point = Vector2(local.y, src.size.y - local.x)
	return (point + Vector2(src.position)) / sheet.frame_scale


## The pages and their frames, under the selection
func draw(canvas: SpritesheetPreview, visible_rect: Rect2, pixel: float) -> void:
	for page in page_sizes.size():
		var rect := get_page_rect(page)
		if not rect.intersects(visible_rect):
			continue
		if canvas.show_checkerboard:
			canvas.draw_checkerboard(rect, pixel)
		canvas.draw_rect(rect, PAGE_BORDER_COLOR, false, pixel)
		var size := page_sizes[page]
		_draw_label(
			canvas, rect.position, tr("Page %d · %d×%d") % [page + 1, size.x, size.y], pixel
		)
	if canvas.is_dragging_frames():
		var new_page := get_new_page_rect()
		canvas.draw_rect(new_page, NEW_PAGE_COLOR)
		_draw_label(canvas, new_page.position, tr("New page"), pixel)
	for coord in _order:
		var rect := get_frame_rect(coord)
		if rect.intersects(visible_rect):
			draw_frame(canvas, coord, rect)
			if canvas.show_grid:
				canvas.draw_rect(rect, OUTLINE_COLOR, false, pixel)
			_draw_marks(canvas, coord, rect, pixel)


## The frame's packed pixels in [param rect], turned like they're stored
func draw_frame(
	canvas: SpritesheetPreview, coord: Vector2i, rect: Rect2, modulate_color := Color.WHITE
) -> void:
	var place: Dictionary = sheet.placements[coord]
	var shown := canvas.get_frame_texture(coord)
	var texture: Texture2D = shown.texture
	# While frames are scaled in the background, the original is stretched
	var src := Rect2(place.src)
	src = Rect2(src.position / shown.scale, src.size / shown.scale)
	if place.rotated:
		canvas.draw_set_transform(rect.position + Vector2(rect.size.x, 0), PI / 2)
		canvas.draw_texture_rect_region(
			texture, Rect2(Vector2.ZERO, Vector2(rect.size.y, rect.size.x)), src, modulate_color
		)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect_region(texture, rect, src, modulate_color)


## Small marks in the corners of pinned and turned frames
func _draw_marks(canvas: SpritesheetPreview, coord: Vector2i, rect: Rect2, pixel: float) -> void:
	var place: Dictionary = sheet.placements[coord]
	var mark := minf(6 * pixel, minf(rect.size.x, rect.size.y) / 3)
	if place.get("pinned", false):
		# The same size on screen at any zoom, but never bigger than half the frame
		var pin := minf(PIN_SIZE * pixel, minf(rect.size.x, rect.size.y) / 2)
		var corner := Rect2(rect.end.x - pin - pixel * 2, rect.position.y + pixel * 2, pin, pin)
		canvas.draw_circle(corner.get_center(), pin * 0.62, PIN_BACKGROUND)
		canvas.draw_texture_rect(PIN_ICON, corner.grow(-pin * 0.12), false)
	if place.rotated:
		var corner := rect.position
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[corner, corner + Vector2(mark * 2, 0), corner + Vector2(0, mark * 2)]
			),
			TURNED_COLOR
		)


func _draw_label(canvas: SpritesheetPreview, at: Vector2, text: String, pixel: float) -> void:
	canvas.draw_set_transform(at, 0, Vector2.ONE * pixel)
	canvas.draw_string(
		ThemeDB.fallback_font,
		Vector2(0, -6),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		PAGE_LABEL_SIZE,
		Color(0.8, 0.85, 1.0)
	)
	canvas.draw_set_transform(Vector2.ZERO)
