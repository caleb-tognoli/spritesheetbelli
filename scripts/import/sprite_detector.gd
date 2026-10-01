class_name SpriteDetector
## Finds the sprites in a packed spritesheet that has no data file: every group of pixels
## surrounded by transparency is one sprite. Sprites are returned in rows, the way they're
## laid out in the image. A sheet on a solid colour has it made transparent first, see
## [SheetBackground].

## Sprites with fewer pixels than this in their rectangle are dust, not sprites
const MIN_AREA := 4


## The rectangles of the sprites in [param img], in rows from top to bottom, each from left
## to right. Parts closer than [param merge_distance] pixels, like a sword apart from the
## hand holding it, count as one sprite. Parts inside another sprite's rectangle belong to
## that sprite.
static func detect(img: Image, merge_distance := 0) -> Array[Array]:
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	var mask := BitMap.new()
	mask.create_from_image_alpha(img, 0.01)
	if merge_distance > 0:
		# Growing each part by half the distance joins parts that close
		mask.grow_mask(ceili(merge_distance / 2.0), bounds)

	var rects: Array[Rect2i] = []
	for polygon: PackedVector2Array in mask.opaque_to_polygons(bounds, 0.5):
		var outline := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			outline = outline.expand(point)
		var area := Rect2i(outline.position.floor(), outline.size.ceil()).intersection(bounds)
		if merge_distance > 0:
			# Back to the pixels themselves
			area = _visible_part(img, area)
		if area.get_area() >= MIN_AREA:
			rects.append(area)
	return group_in_rows(_drop_enclosed(rects))


## Puts rectangles that share most of their height in one row, rows from top to bottom
## and each row from left to right
static func group_in_rows(rects: Array[Rect2i]) -> Array[Array]:
	var rows: Array[Array] = []
	for row in order_in_rows(rects):
		rows.append(row.map(func(index: int) -> Rect2i: return rects[index]))
	return rows


## The indices of [param rects] the way [method group_in_rows] puts them in rows. Rectangles
## at the same place keep their order.
static func order_in_rows(rects: Array[Rect2i]) -> Array[Array]:
	var sorted := range(rects.size())
	sorted.sort_custom(
		func(a: int, b: int) -> bool:
			var y_a := rects[a].position.y
			var y_b := rects[b].position.y
			return y_a < y_b or (y_a == y_b and a < b)
	)
	var rows: Array[Array] = []
	var row_span := Vector2i.ZERO  # Top and bottom of the current row
	for index: int in sorted:
		var rect := rects[index]
		var overlap := mini(row_span.y, rect.end.y) - maxi(row_span.x, rect.position.y)
		var smaller := mini(row_span.y - row_span.x, rect.size.y)
		if rows.is_empty() or overlap * 2 < smaller:
			rows.append([])
			row_span = Vector2i(rect.position.y, rect.end.y)
		rows[-1].append(index)
		row_span = Vector2i(mini(row_span.x, rect.position.y), maxi(row_span.y, rect.end.y))
	for row in rows:
		row.sort_custom(
			func(a: int, b: int) -> bool:
				var x_a := rects[a].position.x
				var x_b := rects[b].position.x
				return x_a < x_b or (x_a == x_b and a < b)
		)
	return rows


## A spritesheet with one frame per sprite, keeping the rows of [param rows]. The frames
## are cut without the transparent borders of their rectangles, and lined up as
## [param alignment] says, e.g. at the bottom for characters (see [method FrameEdits.align]).
## With the [param path] of the image, the frames are linked to it, see [FrameSource]. With
## [param keep_layout], the sheet is packed with every sprite where it was found.
static func to_spritesheet(
	img: Image,
	rows: Array[Array],
	alignment := Spritesheet.Alignment.CENTER,
	path := "",
	keep_layout := false
) -> Spritesheet:
	# Trimmed here rather than by aligning, so the frames are linked to what they hold
	var visible_rows: Array[Array] = []
	for row in rows:
		visible_rows.append(row.map(func(rect: Rect2i) -> Rect2i: return _visible_part(img, rect)))
	rows = visible_rows
	var sheet := Spritesheet.new()
	sheet.begin_batch()
	for row in rows.size():
		for column: int in rows[row].size():
			var rect: Rect2i = rows[row][column]
			sheet.set_frame(Vector2i(column, row), img.get_region(rect))
	FrameEdits.align(sheet, sheet.get_sorted_coords(), alignment)
	# Linked once aligned, so going back to the file keeps the alignment
	if path:
		for row in rows.size():
			for column: int in rows[row].size():
				var coord := Vector2i(column, row)
				var origin: Variant = FrameSource.get_origin(sheet, coord)
				var source := FrameSource.for_region(path, rows[row][column])
				source = FrameSource.with_origin(source, origin)
				sheet.set_frame(coord, sheet.frames[coord], source, origin)
	if keep_layout:
		var places := {}
		for row in rows.size():
			for column: int in rows[row].size():
				var rect: Rect2i = rows[row][column]
				var src := Rect2i(Vector2i.ZERO, rect.size)
				places[Vector2i(column, row)] = PackedLayout.new_place(0, rect.position, src)
		PackedLayout.adopt(sheet, places, img.get_size())
	sheet.end_batch()
	return sheet


## The part of [param area] of [param img] that isn't transparent, or the whole of it when
## nothing is drawn there
static func _visible_part(img: Image, area: Rect2i) -> Rect2i:
	var used := img.get_region(area).get_used_rect()
	if not used.has_area():
		return area
	return Rect2i(area.position + used.position, used.size)


static func _drop_enclosed(rects: Array[Rect2i]) -> Array[Rect2i]:
	var kept: Array[Rect2i] = []
	for i in rects.size():
		var enclosed := false
		for j in rects.size():
			if i != j and rects[j].encloses(rects[i]) and (rects[j] != rects[i] or j < i):
				enclosed = true
				break
		if not enclosed:
			kept.append(rects[i])
	return kept
