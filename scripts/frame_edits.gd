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


## Puts frames against an edge of their cells, or in the middle, without growing the
## cells. The edges are the other frames' when the frame fits between them (so a frame
## moved out lines up with the rest again), else the whole cell's.
static func align(
	sheet: Spritesheet, coords: Array[Vector2i], alignment: Spritesheet.Alignment
) -> void:
	var cell := Rect2i()
	var rest := Rect2i()
	for coord in sheet.frames:
		var rect := Rect2i(sheet.get_frame_origin(coord), sheet.frames[coord].get_size())
		cell = rect if cell.size == Vector2i.ZERO else cell.merge(rect)
		if coord not in coords:
			rest = rect if rest.size == Vector2i.ZERO else rest.merge(rect)
	sheet.begin_batch()
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
