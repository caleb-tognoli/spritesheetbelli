class_name AtlasPacker
## Packs trimmed frames tightly into one texture atlas with the MaxRects algorithm.

const MAX_SIZE := 16384


class Region:
	## Where the trimmed frame is in the atlas
	var rect: Rect2i
	## Where the trimmed pixels were inside the full cell
	var source_rect: Rect2i
	## Size of the full cell before trimming
	var source_size: Vector2i
	var coord: Vector2i


## Packs every frame of [param sheet]. Returns [code]{"image": Image, "regions":
## Array[Region]}[/code], or an empty image when the frames don't fit.
static func pack(sheet: Spritesheet, spacing := 0, extrude := 0) -> Dictionary:
	var items: Array[Dictionary] = []
	for coord in sheet.get_sorted_coords():
		var cell := sheet.get_cell_image(coord)
		var used := cell.get_used_rect()
		if used.size == Vector2i.ZERO:
			used = Rect2i(0, 0, 1, 1)
		items.append({"coord": coord, "image": cell.get_region(used), "source_rect": used})

	var margin := spacing + extrude * 2
	var sizes: Array[Vector2i] = []
	for item in items:
		sizes.append(item.image.get_size() + Vector2i.ONE * margin)
	var placement := find_smallest_packing(sizes)
	if placement.is_empty():
		return {"image": Image.create_empty(1, 1, false, Image.FORMAT_RGBA8), "regions": []}

	var atlas_size: Vector2i = placement.size - Vector2i.ONE * spacing
	var atlas := Image.create_empty(
		maxi(1, atlas_size.x), maxi(1, atlas_size.y), false, Image.FORMAT_RGBA8
	)
	var regions: Array[Region] = []
	for i in items.size():
		var img: Image = items[i].image
		var region := Region.new()
		region.coord = items[i].coord
		region.rect = Rect2i(placement.positions[i] + Vector2i.ONE * extrude, img.get_size())
		region.source_rect = items[i].source_rect
		region.source_size = sheet.sprite_size
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), region.rect.position)
		if extrude > 0:
			SpritesheetExporter.extrude_edges(atlas, region.rect, extrude)
		regions.append(region)
	return {"image": atlas, "regions": regions}


## Tries several widths and keeps the packing with the smallest area.
## Returns [code]{"size": Vector2i, "positions": Array[Vector2i]}[/code] or empty.
static func find_smallest_packing(sizes: Array[Vector2i]) -> Dictionary:
	if sizes.is_empty():
		return {}
	var widest := 0
	var area := 0
	for size in sizes:
		widest = maxi(widest, size.x)
		area += size.x * size.y
	# A few widths around a square; more attempts rarely save much space
	var square := ceili(sqrt(area))
	var widths: Array[int] = [widest]
	for factor: float in [1.0, 1.15, 1.35, 1.6, 2.0]:
		var candidate := maxi(widest, ceili(square * factor))
		if candidate not in widths and candidate <= MAX_SIZE:
			widths.append(candidate)
	var best := {}
	for width in widths:
		var result := pack_rects(sizes, width)
		if result.is_empty():
			continue
		var result_area: int = result.size.x * result.size.y
		if best.is_empty() or result_area < best.size.x * best.size.y:
			best = result
	return best


## Places rectangles of [param sizes] in a strip [param width] wide, using MaxRects with
## the bottom-left rule (lowest, then leftmost), biggest first. Returns the used size and
## positions.
static func pack_rects(sizes: Array[Vector2i], width: int) -> Dictionary:
	var order := range(sizes.size())
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return maxi(sizes[a].x, sizes[a].y) > maxi(sizes[b].x, sizes[b].y)
	)
	var free: Array[Rect2i] = [Rect2i(0, 0, width, MAX_SIZE)]
	var positions: Array[Vector2i] = []
	positions.resize(sizes.size())
	var used := Vector2i.ZERO
	for index: int in order:
		var size := sizes[index]
		var best := Rect2i()
		var best_score := Vector2i(1 << 30, 1 << 30)
		for rect in free:
			if size.x <= rect.size.x and size.y <= rect.size.y:
				var score := Vector2i(rect.position.y + size.y, rect.position.x)
				if score < best_score:
					best_score = score
					best = Rect2i(rect.position, size)
		if best.size == Vector2i.ZERO:
			return {}
		positions[index] = best.position
		used = used.max(best.end)
		free = _split_free_rects(free, best)
	return {"size": used, "positions": positions}


static func _split_free_rects(free: Array[Rect2i], placed: Rect2i) -> Array[Rect2i]:
	var kept: Array[Rect2i] = []
	var split: Array[Rect2i] = []
	for rect in free:
		if not rect.intersects(placed):
			kept.append(rect)
			continue
		if placed.position.x > rect.position.x:
			split.append(
				Rect2i(rect.position, Vector2i(placed.position.x - rect.position.x, rect.size.y))
			)
		if placed.end.x < rect.end.x:
			split.append(
				Rect2i(placed.end.x, rect.position.y, rect.end.x - placed.end.x, rect.size.y)
			)
		if placed.position.y > rect.position.y:
			split.append(
				Rect2i(rect.position, Vector2i(rect.size.x, placed.position.y - rect.position.y))
			)
		if placed.end.y < rect.end.y:
			split.append(
				Rect2i(rect.position.x, placed.end.y, rect.size.x, rect.end.y - placed.end.y)
			)

	# Kept rectangles were already pruned among themselves, so only the new ones need
	# checking: drop new ones inside any other, and kept ones inside a new one.
	var new_rects: Array[Rect2i] = []
	for i in split.size():
		var inside := false
		for rect in kept:
			if rect.encloses(split[i]):
				inside = true
				break
		if not inside:
			for j in split.size():
				if i != j and split[j].encloses(split[i]) and (split[i] != split[j] or i > j):
					inside = true
					break
		if not inside:
			new_rects.append(split[i])
	var result: Array[Rect2i] = []
	for rect in kept:
		var inside := false
		for new_rect in new_rects:
			if new_rect.encloses(rect):
				inside = true
				break
		if not inside:
			result.append(rect)
	result.append_array(new_rects)
	return result
