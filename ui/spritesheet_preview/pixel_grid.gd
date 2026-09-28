class_name PixelGrid
extends RefCounted
## Faint lines between the pixels of frames in a [SpritesheetPreview] zoomed in far enough,
## and what's at the pixel under the mouse, for the status bar.
##
## Lines follow each frame's own pixels: a frame scaled 2× gets a line every two pixels
## of the sheet. They go on whole pixels of the sheet, where the scaled frame starts
## showing the next pixel of the frame as [method Image.resize] with Nearest picks them
## (see [method _to_frame_pixel]), so the lines match the pixels drawn, even at scales
## that aren't whole. Only frames get lines, as only their pixels are the frames'.

## Zoom from which the lines are shown when the pixel grid is on
const MIN_ZOOM := 6.0
## How much of the grid colour's opacity the lines have
const OPACITY := 0.4


## Whether the lines are shown at [param zoom] when the pixel grid is [param on]
static func is_shown(on: bool, zoom: float) -> bool:
	return on and zoom >= MIN_ZOOM - PixelZoom.EPSILON


## Where the pixels of the frame at [param coord] are in [param canvas], or an empty
## dictionary without a frame there: [code]rect[/code] where it's drawn, in whole pixels,
## [code]src[/code] the part of the scaled frame drawn there, [code]rotated[/code] when it's
## turned clockwise like packed frames, [code]page[/code] its page when packed (else -1),
## and the sizes of the frame, [code]size[/code], and of the scaled frame,
## [code]scaled[/code]
static func get_frame_view(canvas: SpritesheetPreview, coord: Vector2i) -> Dictionary:
	var sheet := canvas.spritesheet
	if not sheet.has_frame(coord):
		return {}
	var size := sheet.frames[coord].get_size()
	var view := {"size": size, "scaled": sheet.scaled_frames.scaled_size(size)}
	if canvas.is_packed():
		var place: Dictionary = sheet.placements.get(coord, {})
		if place.is_empty():
			return {}
		view.rect = Rect2i(canvas.packed_view.get_frame_rect(coord))
		view.src = place.src
		view.rotated = place.rotated
		view.page = place.page
		return view
	var in_cell := sheet.get_frame_rect_in_cell(coord)
	var cell := Rect2i(canvas.grid_view.get_cell_rect(coord))
	view.rect = Rect2i(cell.position + in_cell.position, in_cell.size)
	view.src = Rect2i(Vector2i.ZERO, in_cell.size)
	view.rotated = false
	view.page = -1
	return view


## What's at [param pixel], a whole pixel of [param canvas], for the frame at
## [param coord]: [code]sheet[/code] the pixel of the exported sheet, or of page
## [code]page[/code] of [code]pages[/code] when packed (else -1). On one of the frame's
## pixels, also [code]frame[/code] the pixel of the unscaled frame and [code]color[/code]
## the colour shown there. Empty without a frame.
static func probe(canvas: SpritesheetPreview, coord: Vector2i, pixel: Vector2i) -> Dictionary:
	var view := get_frame_view(canvas, coord)
	if view.is_empty():
		return {}
	# The grid is laid out as it's exported, and packed pages start at whole pixels
	var info := {"sheet": pixel, "page": view.page, "pages": 1}
	if view.page >= 0:
		info.sheet = pixel - Vector2i(canvas.packed_view.page_origins[view.page])
		info.pages = canvas.packed_view.page_sizes.size()
	var rect: Rect2i = view.rect
	if not rect.has_point(pixel):
		return info
	var scaled := _to_scaled(view, pixel - rect.position)
	var size: Vector2i = view.size
	var scaled_size: Vector2i = view.scaled
	info.frame = Vector2i(
		_to_frame_pixel(scaled.x, size.x, scaled_size.x),
		_to_frame_pixel(scaled.y, size.y, scaled_size.y)
	)
	info.color = _get_color(canvas.spritesheet, coord, scaled, info.frame)
	return info


## Says where [param info] from [method probe] is and the colour there, like
## "3, 5 in the frame (35, 5 on the sheet) · #ff8000, alpha 255"
static func describe(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var sheet: Vector2i = info.sheet
	var where := TranslationServer.translate("%d, %d on the sheet") % [sheet.x, sheet.y]
	if info.pages > 1:
		where = (
			TranslationServer.translate("%d, %d on page %d") % [sheet.x, sheet.y, info.page + 1]
		)
	if not info.has("frame"):
		return where
	var frame: Vector2i = info.frame
	var color: Color = info.color
	return (
		TranslationServer.translate("%d, %d in the frame (%s)") % [frame.x, frame.y, where]
		+ " · "
		+ TranslationServer.translate("#%s, alpha %d") % [color.to_html(false), color.a8]
	)


## Draws the lines between the pixels of the frames at [param coords] in one batch
static func draw(canvas: SpritesheetPreview, coords: Array[Vector2i], visible_rect: Rect2) -> void:
	var points := get_lines(canvas, coords, visible_rect)
	if not points.is_empty():
		var color := canvas.grid_color
		canvas.draw_multiline(points, Color(color, color.a * OPACITY))


## The lines between the pixels of the frames at [param coords], as pairs of points: only
## in [param visible_rect], so zoomed in on a big sheet, only what is seen of it gets lines
static func get_lines(
	canvas: SpritesheetPreview, coords: Array[Vector2i], visible_rect: Rect2
) -> PackedVector2Array:
	var points := PackedVector2Array()
	# Frames that look the same can share a place when packed
	var done: Dictionary[Rect2i, bool] = {}
	for coord in coords:
		var view := get_frame_view(canvas, coord)
		if view.is_empty() or done.has(view.rect):
			continue
		done[view.rect] = true
		_add_lines(points, view, visible_rect)
	return points


## Lines across the visible part of a frame, from [method get_frame_view], where its pixels
## start
static func _add_lines(points: PackedVector2Array, view: Dictionary, visible_rect: Rect2) -> void:
	var rect: Rect2i = view.rect
	var shown := Rect2(rect).intersection(visible_rect)
	if not shown.has_area():
		return
	var origin := Vector2(rect.position)
	var from := Vector2i((shown.position - origin).floor())
	var to := Vector2i((shown.end - origin).ceil())
	var src: Rect2i = view.src
	for axis in 2:
		# Turned frames have the frame's rows across and its columns down, bottom up
		var frame_axis: int = 1 - axis if view.rotated else axis
		var size: int = view.size[frame_axis]
		var scaled: int = view.scaled[frame_axis]
		var start: int = src.position[frame_axis]
		var direction := 1
		if view.rotated and axis == 0:
			start += src.size[frame_axis] - 1
			direction = -1
		var across := 1 - axis
		for i in range(from[axis], to[axis] + 1):
			# Between two scaled pixels that show the same pixel of the frame
			if (
				size != scaled
				and i > 0
				and i < rect.size[axis]
				and (
					_to_frame_pixel(start + direction * i, size, scaled)
					== _to_frame_pixel(start + direction * (i - 1), size, scaled)
				)
			):
				continue
			var a := Vector2.ZERO
			a[axis] = origin[axis] + i
			a[across] = shown.position[across]
			var b := a
			b[across] = shown.end[across]
			points.append(a)
			points.append(b)


## The pixel of the scaled frame shown at [param local] in the frame's rect
static func _to_scaled(view: Dictionary, local: Vector2i) -> Vector2i:
	var src: Rect2i = view.src
	if view.rotated:
		# Stored turned clockwise: the frame's left column is the top row
		local = Vector2i(local.y, src.size.y - 1 - local.x)
	return src.position + local


## The pixel of a frame [param size] pixels long shown at [param scaled] of it scaled to
## [param scaled_size]: the one under the middle of that pixel, as Nearest picks it
static func _to_frame_pixel(scaled: int, size: int, scaled_size: int) -> int:
	return (scaled * 2 + 1) * size / (scaled_size * 2)


## The colour shown at [param scaled] of the scaled frame, which is [param frame] of the
## frame. While frames are scaled in the background, the frame is shown stretched.
static func _get_color(
	sheet: Spritesheet, coord: Vector2i, scaled: Vector2i, frame: Vector2i
) -> Color:
	if sheet.scaled_frames.is_ready(coord) or not sheet.scaled_frames.is_preparing():
		return sheet.get_frame_image(coord).get_pixelv(scaled)
	return sheet.frames[coord].get_pixelv(frame)
