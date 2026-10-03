class_name FrameEdits
## Edits to the pixels of frames: flipping, turning, trimming, removing a colour and
## outlining. Each one is described by an op, a plain dictionary kept with linked frames
## (see [FrameSource]), so it can be made again with [method apply] when they're reloaded.
## Moving a frame in its cell is the op [code]{"op": "move", "by": [x, y]}[/code].


## Mirrors frames, and where they are in their cells
static func flip(sheet: Spritesheet, coords: Array[Vector2i], horizontal: bool) -> void:
	sheet.edit_frames(
		coords,
		func(img: Image) -> void:
			if horizontal:
				img.flip_x()
			else:
				img.flip_y(),
		func(origin: Vector2i, size: Vector2i, _img: Image) -> Vector2i:
			if horizontal:
				return Vector2i(-origin.x - size.x, origin.y)
			return Vector2i(origin.x, -origin.y - size.y),
		false,
		{"op": "flip", "horizontal": horizontal},
		func(pivot: Vector2, size: Vector2i) -> Vector2:
			if horizontal:
				return Vector2(size.x - pivot.x, pivot.y)
			return Vector2(pivot.x, size.y - pivot.y)
	)


## Turns frames, and where they are in their cells
static func rotate(sheet: Spritesheet, coords: Array[Vector2i], clockwise: bool) -> void:
	sheet.edit_frames(
		coords,
		func(img: Image) -> void: img.rotate_90(CLOCKWISE if clockwise else COUNTERCLOCKWISE),
		func(origin: Vector2i, size: Vector2i, _img: Image) -> Vector2i:
			if clockwise:
				return Vector2i(-origin.y - size.y, origin.x)
			return Vector2i(origin.y, -origin.x - size.x),
		false,
		{"op": "rotate", "clockwise": clockwise},
		func(pivot: Vector2, size: Vector2i) -> Vector2:
			if clockwise:
				return Vector2(size.y - pivot.y, pivot.x)
			return Vector2(pivot.y, size.x - pivot.x)
	)


## Crops transparent borders. The pixels that are left stay where they were in the cell,
## so trimming every frame of an animation shrinks the cells without making it jump.
static func trim(sheet: Spritesheet, coords: Array[Vector2i]) -> void:
	var cropped_at := {}
	sheet.edit_frames(
		coords,
		func(img: Image) -> Image:
			var used := img.get_used_rect()
			if used.size == Vector2i.ZERO or used.size == img.get_size():
				return img
			var trimmed := img.get_region(used)
			cropped_at[trimmed] = used.position
			return trimmed,
		func(origin: Vector2i, _size: Vector2i, img: Image) -> Vector2i:
			return origin + cropped_at.get(img, Vector2i.ZERO),
		true,
		{"op": "trim"}
	)


## Makes pixels close to [param color] transparent
static func color_key(
	sheet: Spritesheet, coords: Array[Vector2i], color: Color, tolerance := 0.1
) -> void:
	sheet.edit_frames(
		coords,
		func(img: Image) -> void: ImageUtils.color_key(img, color, tolerance),
		Callable(),
		false,
		color_key_op(color, tolerance)
	)


static func color_key_op(color: Color, tolerance: float) -> Dictionary:
	return {"op": "color_key", "color": color.to_html(), "tolerance": tolerance}


## Draws an outline around the pixels of frames. The frames grow on every side, so they
## move back by the thickness to keep their pixels in place.
static func outline(
	sheet: Spritesheet, coords: Array[Vector2i], color: Color, thickness := 1, corners := false
) -> void:
	sheet.edit_frames(
		coords,
		func(img: Image) -> Image: return ImageUtils.outline(img, color, thickness, corners),
		outline_move(thickness),
		false,
		outline_op(color, thickness, corners)
	)


## Where [method outline] puts frames, see [method Spritesheet.edit_frames]
static func outline_move(thickness: int) -> Callable:
	return func(origin: Vector2i, _size: Vector2i, _img: Image) -> Vector2i:
		return origin - Vector2i.ONE * thickness


static func outline_op(color: Color, thickness: int, corners: bool) -> Dictionary:
	return {"op": "outline", "color": color.to_html(), "thickness": thickness, "corners": corners}


## Trims the frames that have transparent borders, leaving the others (and their linked
## files' edits) as they are. See [method trim].
static func trim_padded(sheet: Spritesheet, coords: Array[Vector2i]) -> void:
	var padded: Array[Vector2i] = []
	for coord in coords:
		if not sheet.has_frame(coord):
			continue
		var img: Image = sheet.frames[coord]
		var used := img.get_used_rect()
		if used.size != Vector2i.ZERO and used.size != img.get_size():
			padded.append(coord)
	if not padded.is_empty():
		trim(sheet, padded)


## Moves frames inside their cells by [param offset] unscaled pixels. Their transparent
## borders are trimmed first, so only what's drawn grows the cells when it goes past them.
static func nudge(sheet: Spritesheet, coords: Array[Vector2i], offset: Vector2i) -> void:
	if offset == Vector2i.ZERO:
		return
	sheet.begin_batch()
	trim_padded(sheet, coords)
	sheet.nudge_frames(coords, offset)
	sheet.end_batch()


## Moves each frame towards [param direction] until the edge of what's drawn facing it
## is on the next guide that way (see [method Spritesheet.get_guides]), so frames line up
## on it. Frames with no guide ahead stay where they are; those that move are trimmed
## first, like with [method nudge].
static func snap_to_guides(
	sheet: Spritesheet, coords: Array[Vector2i], direction: Vector2i
) -> void:
	var axis := Vector2.AXIS_X if direction.x != 0 else Vector2.AXIS_Y
	var towards := direction[axis]
	var guides := sheet.get_guides(axis)
	var by_offset := {}
	for coord in coords:
		if not sheet.has_frame(coord):
			continue
		var used := sheet.frames[coord].get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var drawn := Rect2i(sheet.get_frame_origin(coord) + used.position, used.size)
		var edge := drawn.end[axis] if towards > 0 else drawn.position[axis]
		# The guides are in order: the first past the edge going down or right, the last
		# before it going up or left
		var to := edge
		for guide in guides:
			if towards > 0 and guide > edge:
				to = guide
				break
			if towards < 0 and guide < edge:
				to = guide
		if to == edge:
			continue
		var offset := Vector2i.ZERO
		offset[axis] = to - edge
		if not by_offset.has(offset):
			by_offset[offset] = [] as Array[Vector2i]
		by_offset[offset].append(coord)
	if by_offset.is_empty():
		return
	sheet.begin_batch()
	for offset: Vector2i in by_offset:
		nudge(sheet, by_offset[offset], offset)
	sheet.end_batch()


## Adds transparent space around the frames, or takes it away, to make the cells
## [param size] without scaling the frames (see [method Spritesheet.set_canvas_size]). Only
## transparent pixels are cropped: shrinking trims the frames' transparent borders, and the
## cells stay big enough for what's drawn.
static func resize_canvas(sheet: Spritesheet, size: Vector2i) -> void:
	sheet.begin_batch()
	var shrinking := size.x < sheet.sprite_size.x or size.y < sheet.sprite_size.y
	sheet.set_canvas_size(size)
	if shrinking:
		trim_padded(sheet, sheet.get_sorted_coords())
	sheet.end_batch()


## [param pivot] (in unscaled pixels of the frame at [param coord]) moved inside the frame,
## its edges included
static func pivot_inside(sheet: Spritesheet, coord: Vector2i, pivot: Vector2) -> Vector2:
	if not sheet.has_frame(coord):
		return pivot
	return pivot.clamp(Vector2.ZERO, Vector2(sheet.frames[coord].get_size()))


## Puts the pivots of the frames at [param pivot], each kept inside its frame, see
## [method pivot_inside]
static func set_pivots_inside(sheet: Spritesheet, coords: Array[Vector2i], pivot: Vector2) -> void:
	var by_pivot := {}
	for coord in coords:
		var inside := pivot_inside(sheet, coord, pivot)
		if not by_pivot.has(inside):
			by_pivot[inside] = [] as Array[Vector2i]
		by_pivot[inside].append(coord)
	sheet.begin_batch()
	for inside: Vector2 in by_pivot:
		sheet.set_pivots(by_pivot[inside], inside)
	sheet.end_batch()


## Puts frames against an edge of their cells, or in the middle, without growing the
## cells. Their transparent borders are trimmed first, so it's what's drawn that lines up.
## The edges are the other frames' when the frame fits between them (so a frame moved out
## lines up with the rest again), else the whole cell's.
static func align(
	sheet: Spritesheet, coords: Array[Vector2i], alignment: Spritesheet.Alignment
) -> void:
	sheet.begin_batch()
	trim_padded(sheet, coords)
	var cell := Rect2i()
	var rest := Rect2i()
	for coord in sheet.frames:
		var rect := Rect2i(sheet.get_frame_origin(coord), sheet.frames[coord].get_size())
		cell = rect if cell.size == Vector2i.ZERO else cell.merge(rect)
		if coord not in coords:
			rest = rect if rest.size == Vector2i.ZERO else rest.merge(rect)
	for coord in coords:
		if not sheet.has_frame(coord):
			continue
		var size := sheet.frames[coord].get_size()
		var fits_x := (
			size.x <= rest.size.x
			or alignment in [Spritesheet.Alignment.TOP, Spritesheet.Alignment.BOTTOM]
		)
		var fits_y := (
			size.y <= rest.size.y
			or alignment in [Spritesheet.Alignment.LEFT, Spritesheet.Alignment.RIGHT]
		)
		var bounds := rest if fits_x and fits_y else cell
		var origin := sheet.get_frame_origin(coord)
		match alignment:
			Spritesheet.Alignment.TOP:
				origin.y = bounds.position.y
			Spritesheet.Alignment.BOTTOM:
				origin.y = bounds.end.y - size.y
			Spritesheet.Alignment.LEFT:
				origin.x = bounds.position.x
			Spritesheet.Alignment.RIGHT:
				origin.x = bounds.end.x - size.x
			Spritesheet.Alignment.CENTER:
				origin = bounds.position + (bounds.size - size) / 2
		sheet.set_frame_origin(coord, origin)
	sheet.end_batch()


## Makes the edit described by [param op] again. Edits this version doesn't know are
## skipped.
static func apply(sheet: Spritesheet, coords: Array[Vector2i], op: Dictionary) -> void:
	match op.get("op"):
		"flip":
			flip(sheet, coords, bool(op.get("horizontal", true)))
		"rotate":
			rotate(sheet, coords, bool(op.get("clockwise", true)))
		"trim":
			trim(sheet, coords)
		"color_key":
			color_key(sheet, coords, Color.html(str(op.get("color"))), op.get("tolerance", 0.1))
		"outline":
			outline(
				sheet,
				coords,
				Color.html(str(op.get("color"))),
				int(op.get("thickness", 1)),
				bool(op.get("corners", false))
			)
		"move":
			var by: Array = op.get("by", [0, 0])
			sheet.nudge_frames(coords, Vector2i(int(by[0]), int(by[1])))
