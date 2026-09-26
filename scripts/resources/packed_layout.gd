class_name PackedLayout
## Where the frames of a [Spritesheet] are in its packed layout, an alternative to the grid:
## every frame (without its transparent borders) has a place on a page of the atlas.
##
## A place is [code]{"page": int, "position": Vector2i, "src": Rect2i, "rotated": bool,
## "pinned": bool}[/code]: the frame's pixels in [code]src[/code] (of the scaled frame) are
## at [code]position[/code] on the page, turned 90° clockwise when rotated. Pinned frames
## are only moved by hand.
##
## The sheet calls [method arrange] after every change: with
## [enum AtlasSettings.PackMode] KEEP, frames stay where they are and only new frames, or
## frames that no longer fit their place, are packed in the free space; with AUTO,
## everything but pinned frames is packed again. Frames with the same pixels share a place.


## What packing found out about frames, kept for reuse while their images don't change
class Cache:
	## Used rectangles of frame images
	var _used: Dictionary[Image, Rect2i] = {}
	## Hashes of regions of frame images, by image and region
	var _hashes: Dictionary[Image, Dictionary] = {}
	## What the last packing was made from, to skip packing the same again
	var signature := 0

	func get_used_rect(img: Image) -> Rect2i:
		if not _used.has(img):
			var used := img.get_used_rect()
			_used[img] = used if used.has_area() else Rect2i(0, 0, 1, 1)
		return _used[img]

	func get_hash(img: Image, region: Rect2i) -> int:
		if not _hashes.has(img):
			_hashes[img] = {}
		var hashes: Dictionary = _hashes[img]
		if not hashes.has(region):
			hashes[region] = hash([region.size, img.get_region(region).get_data()])
		return hashes[region]

	## Forgets images that aren't in [param alive], a set
	func prune(alive: Dictionary) -> void:
		for img: Image in _used.keys():
			if not alive.has(img):
				_used.erase(img)
		for img: Image in _hashes.keys():
			if not alive.has(img):
				_hashes.erase(img)


## Where every frame goes after a change. Returns [code]{"placements": Dictionary,
## "warnings": PackedStringArray}[/code], or an empty dictionary when nothing changed.
static func arrange(sheet: Spritesheet, repack := false, include_pinned := false) -> Dictionary:
	var settings := sheet.atlas_settings
	var old := sheet.placements
	var groups := _group_frames(sheet, settings, old)
	var keep_all := settings.pack_mode == AtlasSettings.PackMode.KEEP and not repack
	var signature := 0
	if not keep_all and not repack:
		signature = _signature(settings, groups)
		if signature == sheet.pack_cache.signature and _all_placed(sheet, old):
			return {}
	var warnings := PackedStringArray()
	var accepted: Dictionary[Vector2i, Dictionary] = {}  # Leader of each group to its place
	var taken: Array[Dictionary] = []  # Places of accepted groups, for the packer
	var waiting: Array[Dictionary] = []  # Groups that need a place

	# Pinned groups first, so the others make room for them
	var ordered: Array[Dictionary] = []
	ordered.append_array(groups.filter(func(g: Dictionary) -> bool: return g.pinned))
	ordered.append_array(groups.filter(func(g: Dictionary) -> bool: return not g.pinned))
	for group in ordered:
		var place: Dictionary = group.place
		var keep: bool = (
			not place.is_empty() and ((group.pinned and not include_pinned) or keep_all)
		)
		if keep:
			var rect := placed_rect(place.position, group.src.size, place.rotated)
			if _fits(rect, place.page, settings, taken):
				accepted[group.leader] = place
				taken.append({"page": place.page, "rect": rect})
				continue
			if group.pinned:
				group.pinned = false
				warnings.append(_warning("%s no longer fits where it was pinned.", group))
		waiting.append(group)

	if not waiting.is_empty():
		var sizes: Array[Vector2i] = []
		for group in waiting:
			sizes.append(group.src.size)
		var packing := RectPacker.pack(sizes, settings, taken)
		for i in waiting.size():
			var found: Dictionary = packing.placements[i]
			accepted[waiting[i].leader] = {
				"page": found.page, "position": found.position, "rotated": found.rotated
			}
		for index: int in packing.oversize:
			warnings.append(_warning("%s is bigger than a page.", waiting[index]))

	var result := _placements_of(groups, accepted, include_pinned)
	sheet.pack_cache.signature = signature if not repack else 0
	return {"placements": result, "warnings": warnings}


## Lays [param sheet] out packed with [param places] (by coordinate, as read from a packed
## sheet), keeping them where they are: frames stay put, report their own size, and pages
## can be as big as [param page_size].
static func adopt(sheet: Spritesheet, places: Dictionary, page_size: Vector2i) -> void:
	var settings := sheet.atlas_settings
	settings.pack_mode = AtlasSettings.PackMode.KEEP
	settings.spacing = 0
	settings.padding = 0
	settings.extrude = 0
	settings.max_size = clampi(
		nearest_po2(maxi(page_size.x, page_size.y)), 256, AtlasPacker.MAX_SIZE
	)
	settings.allow_rotation = places.values().any(
		func(place: Dictionary) -> bool: return place.rotated
	)
	# Data files read give each frame its own size, so exporting again does too
	var export := ExportOptions.new()
	export.apply(sheet.export_settings)
	export.atlas_frame_size = ExportOptions.FrameSize.FRAME
	sheet.begin_batch()
	sheet.set_export_settings(export.to_dictionary())
	sheet.set_atlas_settings(settings)
	sheet.set_placements(places)
	sheet.set_layout(Spritesheet.Layout.PACKED)
	sheet.end_batch()


## A place for a frame read from a packed sheet: [param src] of the frame is at
## [param position] of [param page]
static func new_place(page: int, position: Vector2i, src: Rect2i, rotated := false) -> Dictionary:
	return {"page": page, "position": position, "src": src, "rotated": rotated, "pinned": false}


## Where [param coords] would be after moving them by [param offset] onto [param page], or
## an empty dictionary when they wouldn't fit there. Frames sharing a place with a moved
## frame move with it. Moved frames are pinned.
static func moved(
	sheet: Spritesheet, coords: Array[Vector2i], page: int, offset: Vector2i
) -> Dictionary:
	var settings := sheet.atlas_settings
	var placements := sheet.placements
	var moving := {}  # Places that move, as [page, position]
	for coord in coords:
		if placements.has(coord):
			moving[_place_key(placements[coord])] = true
	if moving.is_empty():
		return {}
	var taken: Array[Dictionary] = []
	var seen := {}
	for coord in placements:
		var key := _place_key(placements[coord])
		if not moving.has(key) and not seen.has(key):
			seen[key] = true
			taken.append({"page": placements[coord].page, "rect": get_rect(sheet, coord)})
	var changes: Dictionary[Vector2i, Dictionary] = {}
	var moved_rects: Dictionary = {}
	for coord in placements:
		var place: Dictionary = placements[coord]
		var key := _place_key(place)
		if not moving.has(key):
			continue
		var target := place.duplicate()
		target.page = page
		target.position = place.position + offset
		target.pinned = true
		var rect := get_rect(sheet, coord)
		rect.position = target.position
		if not moved_rects.has(key):
			if not _fits(rect, page, settings, taken):
				return {}
			taken.append({"page": page, "rect": rect})
			moved_rects[key] = true
		changes[coord] = target
	return changes


## Pins or unpins frames, with the frames that share their place: a place stays pinned
## while any of its frames is. See [method Spritesheet.set_pinned].
static func pin_changes(sheet: Spritesheet, coords: Array[Vector2i], pin: bool) -> Dictionary:
	var placements := sheet.placements
	var keys := {}
	for coord in coords:
		if placements.has(coord):
			keys[_place_key(placements[coord])] = true
	var changes: Dictionary[Vector2i, Dictionary] = {}
	for coord in placements:
		var place: Dictionary = placements[coord]
		if keys.has(_place_key(place)) and bool(place.get("pinned", false)) != pin:
			var changed := place.duplicate()
			changed.pinned = pin
			changes[coord] = changed
	return changes


## The frame's rectangle on its page
static func get_rect(sheet: Spritesheet, coord: Vector2i) -> Rect2i:
	var place: Dictionary = sheet.placements.get(coord, {})
	if place.is_empty():
		return Rect2i()
	return placed_rect(place.position, place.src.size, place.rotated)


## Where a place (see [PackedLayout]) puts its frame on the page
static func get_rect_of(place: Dictionary) -> Rect2i:
	return placed_rect(place.position, place.src.size, place.rotated)


static func placed_rect(position: Vector2i, size: Vector2i, rotated: bool) -> Rect2i:
	return Rect2i(position, Vector2i(size.y, size.x) if rotated else size)


static func get_page_count(sheet: Spritesheet) -> int:
	var count := 0
	for place: Dictionary in sheet.placements.values():
		count = maxi(count, int(place.page) + 1)
	return count


## Rectangles of the frames on each page, each shared place once
static func get_page_rects(sheet: Spritesheet) -> Array[Array]:
	var pages: Array[Array] = []
	for page in get_page_count(sheet):
		pages.append([] as Array[Rect2i])
	for coord in sheet.placements:
		var rect := get_rect(sheet, coord)
		var rects: Array[Rect2i] = pages[sheet.placements[coord].page]
		if rect not in rects:
			rects.append(rect)
	return pages


static func get_page_sizes(sheet: Spritesheet) -> Array[Vector2i]:
	var settings := sheet.atlas_settings
	var sizes: Array[Vector2i] = []
	for rects: Array[Rect2i] in get_page_rects(sheet):
		sizes.append(RectPacker.page_size(rects, settings))
	return sizes


## How much of the pages the frames fill, from 0 to 1
static func get_occupancy(sheet: Spritesheet) -> float:
	var used := 0
	var total := 0
	var settings := sheet.atlas_settings
	for rects: Array[Rect2i] in get_page_rects(sheet):
		var size := RectPacker.page_size(rects, settings)
		total += size.x * size.y
		for rect in rects:
			used += rect.get_area()
	return float(used) / total if total > 0 else 0.0


## "2 pages of up to 1024×512 px, 81% filled"
static func describe(sheet: Spritesheet) -> String:
	var sizes := PackedLayout.get_page_sizes(sheet)
	if sizes.is_empty():
		return ""
	var biggest := Vector2i.ZERO
	for size in sizes:
		biggest = biggest.max(size)
	var filled := roundi(PackedLayout.get_occupancy(sheet) * 100)
	if sizes.size() == 1:
		return (
			TranslationServer.translate("1 page of %d×%d px, %d%% filled")
			% [biggest.x, biggest.y, filled]
		)
	return (
		TranslationServer.translate("%d pages of up to %d×%d px, %d%% filled")
		% [sizes.size(), biggest.x, biggest.y, filled]
	)


## The pages as images, with every frame at its place. Turned frames are turned
## clockwise, or [param counter_clockwise] for engines that expect that.
static func render_pages(sheet: Spritesheet, counter_clockwise := false) -> Array[Image]:
	var settings := sheet.atlas_settings
	var images: Array[Image] = []
	for size in get_page_sizes(sheet):
		images.append(Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8))
	var drawn := {}
	for coord in sheet.get_sorted_coords():
		var place: Dictionary = sheet.placements.get(coord, {})
		if place.is_empty() or drawn.has(_place_key(place)):
			continue
		drawn[_place_key(place)] = true
		var pixels := sheet.get_frame_image(coord).get_region(place.src)
		if place.rotated:
			pixels.rotate_90(COUNTERCLOCKWISE if counter_clockwise else CLOCKWISE)
		var page: Image = images[place.page]
		var rect := Rect2i(place.position, pixels.get_size())
		page.blit_rect(pixels, Rect2i(Vector2i.ZERO, rect.size), rect.position)
		if settings.extrude > 0:
			SpritesheetExporter.extrude_edges(page, rect, settings.extrude)
	return images


## The part of the scaled frame that is packed: without its transparent borders when
## trimming
static func get_source_rect(sheet: Spritesheet, coord: Vector2i, trim := true) -> Rect2i:
	var img: Image = sheet.frames[coord]
	var scale := sheet.frame_scale
	var scaled := sheet.scaled_frames.scaled_size(img.get_size())
	if not trim:
		return Rect2i(Vector2i.ZERO, scaled)
	var used := sheet.pack_cache.get_used_rect(img)
	if scale == Vector2.ONE:
		return used
	var start := Vector2i((Vector2(used.position) * scale).floor())
	var end := Vector2i((Vector2(used.end) * scale).ceil())
	if sheet.scale_filter != Image.INTERPOLATE_NEAREST:
		# Smooth filters spread pixels a little
		start -= Vector2i.ONE
		end += Vector2i.ONE
	var bounds := Rect2i(Vector2i.ZERO, scaled)
	var rect := Rect2i(start, end - start).intersection(bounds)
	return rect if rect.has_area() else bounds


static func _warning(message: String, group: Dictionary) -> String:
	return TranslationServer.translate(message) % group.name


## Frames grouped by what they show, each group with the frame that leads it, the part of
## the frames that is packed, and the place the group had
static func _group_frames(
	sheet: Spritesheet, settings: AtlasSettings, old: Dictionary
) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var by_key := {}
	for coord in sheet.get_sorted_coords():
		var src := get_source_rect(sheet, coord, settings.trim)
		var place: Dictionary = old.get(coord, {})
		# A place that holds more than the frame's pixels (like one read from a data file)
		# is kept as it is
		if not place.is_empty():
			var bounds := Rect2i(
				Vector2i.ZERO, sheet.scaled_frames.scaled_size(sheet.frames[coord].get_size())
			)
			var kept: Rect2i = place.src
			if bounds.encloses(kept) and kept.encloses(src):
				src = kept
		var key: Variant = coord
		if settings.dedupe:
			key = _pixels_key(sheet, coord, src)
			# Frames that look the same but already have places of their own keep them
			if by_key.has(key) and place and by_key[key].place:
				if _place_key(place) != _place_key(by_key[key].place):
					key = [key, coord]
		var pinned := bool(place.get("pinned", false))
		if by_key.has(key):
			var joined: Dictionary = by_key[key]
			joined.members.append(coord)
			joined.sources[coord] = src
			# A pinned member's place wins, else the first one with a place
			if place and ((pinned and not joined.pinned) or joined.place.is_empty()):
				joined.place = place
				joined.pinned = joined.pinned or pinned
			continue
		var group := {
			"leader": coord,
			"name": _frame_name(sheet, coord),
			"members": [coord],
			"sources": {coord: src},
			"src": src,
			"place": place,
			"pinned": pinned,
		}
		by_key[key] = group
		groups.append(group)
	return groups


## Identical for frames that show the same pixels at the same size
static func _pixels_key(sheet: Spritesheet, coord: Vector2i, src: Rect2i) -> int:
	var img: Image = sheet.frames[coord]
	if sheet.frame_scale == Vector2.ONE:
		return sheet.pack_cache.get_hash(img, src)
	# Scaled frames only match when the whole images do
	var whole := Rect2i(Vector2i.ZERO, img.get_size())
	return hash([sheet.pack_cache.get_hash(img, whole), src, sheet.frame_scale])


static func _frame_name(sheet: Spritesheet, coord: Vector2i) -> String:
	var frame_name := sheet.frames[coord].resource_name.get_basename()
	if frame_name:
		return frame_name
	return TranslationServer.translate("Sprite %d") % sheet.index_of(coord)


## Whether a frame at [param rect] is inside the page and clear of [param taken] places
static func _fits(
	rect: Rect2i, page: int, settings: AtlasSettings, taken: Array[Dictionary]
) -> bool:
	if page < 0:
		return false
	var margin := Vector2i.ONE * settings.get_margin()
	var inset := Vector2i.ONE * (settings.padding + settings.extrude)
	var footprint := Rect2i(rect.position - Vector2i.ONE * settings.extrude, rect.size + margin)
	if rect.position.x < inset.x or rect.position.y < inset.y:
		return false
	var limit := settings.max_size - settings.padding + settings.spacing
	if footprint.end.x > limit or footprint.end.y > limit:
		return false
	for other in taken:
		if other.page != page:
			continue
		var other_rect: Rect2i = other.rect
		var other_footprint := Rect2i(
			other_rect.position - Vector2i.ONE * settings.extrude, other_rect.size + margin
		)
		if footprint.intersects(other_footprint):
			return false
	return true


## Places of every frame from the places of the groups, with pages that ended up empty
## taken out
static func _placements_of(
	groups: Array[Dictionary], accepted: Dictionary, include_pinned: bool
) -> Dictionary[Vector2i, Dictionary]:
	var used_pages := {}
	for place: Dictionary in accepted.values():
		used_pages[place.page] = true
	var pages := used_pages.keys()
	pages.sort()
	var result: Dictionary[Vector2i, Dictionary] = {}
	for group in groups:
		var place: Dictionary = accepted[group.leader]
		var pin: bool = group.pinned and not include_pinned
		for coord: Vector2i in group.members:
			result[coord] = {
				"page": pages.find(place.page),
				"position": place.position,
				"src": group.sources[coord],
				"rotated": place.rotated,
				"pinned": pin,
			}
	return result


## What a packing is made from: the settings, and the frames with their pinned places
static func _signature(settings: AtlasSettings, groups: Array[Dictionary]) -> int:
	var parts: Array = [settings.to_dictionary()]
	for group in groups:
		parts.append([group.members, group.sources, group.place if group.pinned else null])
	return hash(parts)


static func _all_placed(sheet: Spritesheet, placements: Dictionary) -> bool:
	for coord in sheet.frames:
		if not placements.has(coord):
			return false
	return true


static func _place_key(place: Dictionary) -> Array:
	return [place.page, place.position]
