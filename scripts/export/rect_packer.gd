class_name RectPacker
## Places rectangles on pages with the MaxRects algorithm: every page keeps the largest
## free rectangles left, and each rectangle goes where [enum AtlasSettings.Heuristic] says.
## Pages are filled in order; a rectangle that fits on no page starts a new one.
## Everything is deterministic: the same sizes and settings always give the same places.


## A page being filled
class Bin:
	var size: Vector2i
	var free: Array[Rect2i] = []
	var used: Array[Rect2i] = []

	func _init(bin_size: Vector2i) -> void:
		size = bin_size
		free.append(Rect2i(Vector2i.ZERO, size))

	## Takes [param rect] out of the free space
	func occupy(rect: Rect2i) -> void:
		rect = rect.intersection(Rect2i(Vector2i.ZERO, size))
		if not rect.has_area():
			return
		free = RectPacker.split_free_rects(free, rect)
		used.append(rect)

	## The best free place for a rectangle of [param rect_size], turned when that's
	## allowed and better. Returns [code]{"rect": Rect2i, "rotated": bool}[/code] or empty.
	func find(
		rect_size: Vector2i, rotate_ok: bool, heuristic: AtlasSettings.Heuristic
	) -> Dictionary:
		var best := {}
		var best_score := Vector2i.ZERO
		var turns: Array[bool] = [false]
		if rotate_ok and rect_size.x != rect_size.y:
			turns.append(true)
		for space in free:
			for turned in turns:
				var placed := Vector2i(rect_size.y, rect_size.x) if turned else rect_size
				if placed.x > space.size.x or placed.y > space.size.y:
					continue
				var score := _score(space, placed, heuristic)
				if best.is_empty() or score < best_score:
					best = {"rect": Rect2i(space.position, placed), "rotated": turned}
					best_score = score
		return best

	## Lower is better
	func _score(space: Rect2i, placed: Vector2i, heuristic: AtlasSettings.Heuristic) -> Vector2i:
		var leftover := space.size - placed
		var short_side := mini(leftover.x, leftover.y)
		var long_side := maxi(leftover.x, leftover.y)
		match heuristic:
			AtlasSettings.Heuristic.BEST_LONG_SIDE:
				return Vector2i(long_side, short_side)
			AtlasSettings.Heuristic.BEST_AREA:
				return Vector2i(space.get_area() - placed.x * placed.y, short_side)
			AtlasSettings.Heuristic.BOTTOM_LEFT:
				return Vector2i(space.position.y + placed.y, space.position.x)
			AtlasSettings.Heuristic.CONTACT:
				return Vector2i(-_contact(Rect2i(space.position, placed)), space.position.y)
		return Vector2i(short_side, long_side)

	## How much of the edge of [param rect] touches the page's edges or used rectangles
	func _contact(rect: Rect2i) -> int:
		var contact := 0
		if rect.position.x == 0 or rect.end.x == size.x:
			contact += rect.size.y
		if rect.position.y == 0 or rect.end.y == size.y:
			contact += rect.size.x
		for other in used:
			if other.position.x == rect.end.x or other.end.x == rect.position.x:
				var top := maxi(rect.position.y, other.position.y)
				contact += maxi(0, mini(rect.end.y, other.end.y) - top)
			if other.position.y == rect.end.y or other.end.y == rect.position.y:
				var left := maxi(rect.position.x, other.position.x)
				contact += maxi(0, mini(rect.end.x, other.end.x) - left)
		return contact


## Places rectangles of [param sizes] (the frames' own pixels) on pages, with the space
## [param settings] asks for around them. [param occupied] are places already taken, as
## [code]{"page": int, "rect": Rect2i}[/code] with the frame's own pixels; with them, every
## page is as big as allowed, else a few page widths are tried and the tightest is kept.
## Returns [code]{"placements": Array[Dictionary], "pages": int, "oversize": Array[int]}[/code]
## with [code]{"page": int, "position": Vector2i, "rotated": bool}[/code] for each size in
## order. Rectangles too big for a page get a page of their own and are listed in oversize.
static func pack(
	sizes: Array[Vector2i], settings: AtlasSettings, occupied: Array[Dictionary] = []
) -> Dictionary:
	var margin := settings.get_margin()
	var page_space := settings.max_size - settings.padding * 2 + settings.spacing
	var largest := Vector2i.ONE * maxi(1, page_space)
	if not occupied.is_empty() or sizes.is_empty():
		return _pack_on(sizes, settings, occupied, largest)
	var widest := 0
	var area := 0
	for size in sizes:
		var footprint := size + Vector2i.ONE * margin
		if footprint.x <= largest.x and footprint.y <= largest.y:
			widest = maxi(widest, footprint.x)
		elif footprint.y <= largest.x and footprint.x <= largest.y and settings.allow_rotation:
			widest = maxi(widest, footprint.y)
		area += footprint.x * footprint.y
	# A few widths around a square; more attempts rarely save much space
	var square := ceili(sqrt(area))
	var widths: Array[int] = []
	for factor: float in [1.0, 1.15, 1.35, 1.6, 2.0]:
		var width := clampi(ceili(square * factor), maxi(widest, 1), largest.x)
		if width not in widths:
			widths.append(width)
	if largest.x not in widths:
		widths.append(largest.x)
	var best := {}
	var best_score := Vector2i.ZERO
	for width in widths:
		var result := _pack_on(sizes, settings, occupied, Vector2i(width, largest.y))
		var used_area := 0
		for page_rects: Array[Rect2i] in rects_by_page(sizes, result.placements, result.pages):
			var page := page_size(page_rects, settings)
			used_area += page.x * page.y
		var score := Vector2i(result.pages, used_area)
		if best.is_empty() or score < best_score:
			best = result
			best_score = score
	return best


## The frames' rectangles on each page, from [method pack]'s placements
static func rects_by_page(
	sizes: Array[Vector2i], placements: Array[Dictionary], page_count: int
) -> Array[Array]:
	var pages: Array[Array] = []
	for page in page_count:
		pages.append([] as Array[Rect2i])
	for i in placements.size():
		var placement := placements[i]
		var size := sizes[i]
		if placement.rotated:
			size = Vector2i(size.y, size.x)
		pages[placement.page].append(Rect2i(placement.position, size))
	return pages


## How big a page holding frames at [param rects] is, with the padding, power-of-two and
## square size [param settings] ask for
static func page_size(rects: Array[Rect2i], settings: AtlasSettings) -> Vector2i:
	var size := Vector2i.ONE
	for rect in rects:
		size = size.max(rect.end + Vector2i.ONE * (settings.extrude + settings.padding))
	if settings.square:
		size = Vector2i.ONE * maxi(size.x, size.y)
	if settings.power_of_two:
		size = Vector2i(nearest_po2(size.x), nearest_po2(size.y))
	return size


static func _pack_on(
	sizes: Array[Vector2i], settings: AtlasSettings, occupied: Array[Dictionary], bin_size: Vector2i
) -> Dictionary:
	var margin := Vector2i.ONE * settings.get_margin()
	var inset := Vector2i.ONE * (settings.padding + settings.extrude)
	var bins: Array[Bin] = []
	for taken in occupied:
		while bins.size() <= int(taken.page):
			bins.append(Bin.new(bin_size))
		var rect: Rect2i = taken.rect
		bins[taken.page].occupy(Rect2i(rect.position - inset, rect.size + margin))
	# Biggest first; the index keeps equal sizes in their order
	var order := range(sizes.size())
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var long_a := maxi(sizes[a].x, sizes[a].y)
			var long_b := maxi(sizes[b].x, sizes[b].y)
			if long_a != long_b:
				return long_a > long_b
			var area_a := sizes[a].x * sizes[a].y
			var area_b := sizes[b].x * sizes[b].y
			return area_a > area_b if area_a != area_b else a < b
	)
	var placements: Array[Dictionary] = []
	placements.resize(sizes.size())
	var oversize: Array[int] = []
	var own_pages: Array[Bin] = []  # Pages of frames too big for any page
	for index: int in order:
		var footprint: Vector2i = sizes[index] + margin
		var found := {}
		var page := 0
		while page < bins.size():
			found = bins[page].find(footprint, settings.allow_rotation, settings.heuristic)
			if not found.is_empty():
				break
			page += 1
		if found.is_empty():
			var fresh := Bin.new(bin_size)
			found = fresh.find(footprint, settings.allow_rotation, settings.heuristic)
			if found.is_empty():
				# Too big for any page: a page of its own, after the others
				oversize.append(index)
				fresh = Bin.new(footprint)
				found = {"rect": Rect2i(Vector2i.ZERO, footprint), "rotated": false}
				own_pages.append(fresh)
				page = -own_pages.size()
			else:
				bins.append(fresh)
				page = bins.size() - 1
		if page >= 0:
			bins[page].occupy(found.rect)
		placements[index] = {
			"page": page,
			"position": found.rect.position + inset,
			"rotated": found.rotated,
		}
	# Pages of oversize frames go last
	for placement in placements:
		if placement.page < 0:
			placement.page = bins.size() - placement.page - 1
	return {"placements": placements, "pages": bins.size() + own_pages.size(), "oversize": oversize}


## Cuts [param placed] out of the free rectangles, keeping only the largest ones
static func split_free_rects(free: Array[Rect2i], placed: Rect2i) -> Array[Rect2i]:
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
