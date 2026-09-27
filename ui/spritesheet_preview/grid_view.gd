class_name GridView
extends RefCounted
## How a [SpritesheetPreview] shows the grid layout: the cells where the export puts them,
## with their frames, extruded edges, locks and lines.

const LOCKED_COLOR := Color(0.85, 0.85, 0.85, 0.9)
## On-screen size of the lock icon on locked cells
const LOCK_ICON_SIZE := 28.0

## Drawn over the cells, so the same in both themes
static var _lock_icon := AppTheme.unthemed_icon(preload("res://assets/icons/Lock.svg"))

## The sheet shown, an empty one until [method update]
var sheet := Spritesheet.new()
## Where the grid's cells are, as in the exported image: after its padding, a step apart
## with the spacing and extruded edges between them
var origin := Vector2.ZERO
var step := Vector2.ZERO
## Size of the exported image
var content_size := Vector2.ZERO
var extrude := 0


## Places cells again after the sheet changed, as the export does, see
## [method SpritesheetExporter.get_cell_rect]
func update(value: Spritesheet) -> void:
	sheet = value
	var options := ExportOptions.new()
	options.apply(sheet.export_settings)
	var cell := sheet.sprite_size
	extrude = options.extrude
	origin = Vector2(SpritesheetExporter.get_cell_rect(sheet, Vector2i.ZERO, options).position)
	step = Vector2(cell + Vector2i.ONE * (options.extrude * 2 + options.spacing))
	content_size = Vector2(SpritesheetExporter.get_image_size(sheet, options))


## Whether there's room between or around the cells
func has_gaps() -> bool:
	return origin != Vector2.ZERO or step != Vector2(sheet.sprite_size)


func get_cell_rect(coord: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(coord) * step, Vector2(sheet.sprite_size))


## The cell at [param world], also outside the grid. The space between cells is split
## between its neighbours.
func get_cell_unclamped(world: Vector2) -> Vector2i:
	if sheet.sprite_size.x <= 0 or sheet.sprite_size.y <= 0:
		return Vector2i.ZERO
	var gap := step - Vector2(sheet.sprite_size)
	return Vector2i(((world - origin + gap / 2) / step).floor())


## The range of cells in [param visible_rect], so drawing skips the rest of large sheets
func get_visible_cells(visible_rect: Rect2) -> Rect2i:
	var start := Vector2i(((visible_rect.position - origin) / step).floor())
	start = start.max(Vector2i.ZERO)
	var end := Vector2i(((visible_rect.end - origin) / step).ceil())
	end = end.min(sheet.grid_size)
	return Rect2i(start, (end - start).max(Vector2i.ZERO))


## The checkerboard, the cells and the lines between them, under the selection. Frames in
## [param lifted] are picked up to move, so the canvas draws them where they'd land
## instead. [param hovered] is the cell to highlight, or NO_CELL.
func draw(
	canvas: SpritesheetPreview,
	visible_rect: Rect2,
	pixel: float,
	lifted: Dictionary[Vector2i, bool],
	hovered: Vector2i
) -> void:
	if canvas.show_checkerboard:
		canvas.draw_checkerboard(Rect2(Vector2.ZERO, content_size), pixel)
	var visible_cells := get_visible_cells(visible_rect)
	for y in range(visible_cells.position.y, visible_cells.end.y):
		for x in range(visible_cells.position.x, visible_cells.end.x):
			var coord := Vector2i(x, y)
			var rect := get_cell_rect(coord)
			if sheet.has_frame(coord):
				if not lifted.has(coord):
					draw_frame(canvas, coord, rect)
					if extrude > 0:
						_draw_extrusion(canvas, coord, rect)
			elif sheet.is_locked(coord):
				_draw_lock(canvas, rect, pixel)
			if coord == hovered:
				canvas.draw_rect(rect, SpritesheetPreview.HOVER_COLOR)
	if canvas.show_grid:
		_draw_lines(canvas, visible_cells, pixel)


## The frame in its place in the cell [param rect]
func draw_frame(
	canvas: SpritesheetPreview, coord: Vector2i, rect: Rect2, modulate_color := Color.WHITE
) -> void:
	var texture: Texture2D = canvas.get_frame_texture(coord).texture
	var in_cell := sheet.get_frame_rect_in_cell(coord)
	canvas.draw_texture_rect(
		texture,
		Rect2(rect.position + Vector2(in_cell.position), in_cell.size),
		false,
		modulate_color
	)


## The frame's edge pixels repeated outward by the extrusion, like in the export
func _draw_extrusion(canvas: SpritesheetPreview, coord: Vector2i, cell: Rect2) -> void:
	var texture: Texture2D = canvas.get_frame_texture(coord).texture
	var in_cell := Rect2(sheet.get_frame_rect_in_cell(coord))
	var frame := Rect2(cell.position + in_cell.position, in_cell.size)
	var size := texture.get_size()
	var amount := float(extrude)
	var last := size - Vector2.ONE
	# Sides, then corners: where to draw, and which pixels of the frame to stretch there
	for part: Array in [
		[
			Rect2(frame.position.x - amount, frame.position.y, amount, frame.size.y),
			Rect2(0, 0, 1, size.y)
		],
		[Rect2(frame.end.x, frame.position.y, amount, frame.size.y), Rect2(last.x, 0, 1, size.y)],
		[
			Rect2(frame.position.x, frame.position.y - amount, frame.size.x, amount),
			Rect2(0, 0, size.x, 1)
		],
		[Rect2(frame.position.x, frame.end.y, frame.size.x, amount), Rect2(0, last.y, size.x, 1)],
		[Rect2(frame.position - Vector2.ONE * amount, Vector2.ONE * amount), Rect2(0, 0, 1, 1)],
		[Rect2(frame.end.x, frame.position.y - amount, amount, amount), Rect2(last.x, 0, 1, 1)],
		[Rect2(frame.position.x - amount, frame.end.y, amount, amount), Rect2(0, last.y, 1, 1)],
		[Rect2(frame.end, Vector2.ONE * amount), Rect2(last, Vector2.ONE)],
	]:
		canvas.draw_texture_rect_region(texture, part[0], part[1])


## A dimmed cell with a lock in the middle, kept small when zoomed out
func _draw_lock(canvas: SpritesheetPreview, rect: Rect2, pixel: float) -> void:
	canvas.draw_rect(rect, Color(0, 0, 0, 0.25))
	var icon_size := minf(LOCK_ICON_SIZE * pixel, minf(rect.size.x, rect.size.y) * 0.6)
	var icon_rect := Rect2(rect.get_center() - Vector2.ONE * icon_size / 2, Vector2.ONE * icon_size)
	canvas.draw_texture_rect(_lock_icon, icon_rect, false, LOCKED_COLOR)


## Lines between the cells, or around each cell when there's space between them
func _draw_lines(canvas: SpritesheetPreview, visible_cells: Rect2i, pixel: float) -> void:
	var color := canvas.grid_color
	if has_gaps():
		for y in range(visible_cells.position.y, visible_cells.end.y):
			for x in range(visible_cells.position.x, visible_cells.end.x):
				canvas.draw_rect(get_cell_rect(Vector2i(x, y)), color, false, pixel)
		return
	var cell_size := Vector2(sheet.sprite_size)
	var size := cell_size * Vector2(sheet.grid_size)
	for row in sheet.grid_size.y + 1:
		canvas.draw_line(
			Vector2(0, row * cell_size.y), Vector2(size.x, row * cell_size.y), color, pixel
		)
	for column in sheet.grid_size.x + 1:
		canvas.draw_line(
			Vector2(column * cell_size.x, 0), Vector2(column * cell_size.x, size.y), color, pixel
		)
