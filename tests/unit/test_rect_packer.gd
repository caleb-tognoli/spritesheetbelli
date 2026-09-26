extends "res://tests/test_case.gd"


static func random_sizes(count: int, seed_value: int, largest := 40) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sizes: Array[Vector2i] = []
	for i in count:
		sizes.append(Vector2i(rng.randi_range(1, largest), rng.randi_range(1, largest)))
	return sizes


static func settings_with(values: Dictionary) -> AtlasSettings:
	return AtlasSettings.from_dictionary(values)


## Every rectangle is on its page, and none of them overlap, spacing and extrusion included
func assert_valid(sizes: Array[Vector2i], result: Dictionary, settings: AtlasSettings) -> void:
	assert_eq(result.placements.size(), sizes.size(), "a place for every size")
	var pages := RectPacker.rects_by_page(sizes, result.placements, result.pages)
	var grow := Vector2i.ONE * settings.extrude
	var padding := Vector2i.ONE * settings.padding
	for page in pages.size():
		var rects: Array[Rect2i] = []
		rects.assign(pages[page])
		assert_false(rects.is_empty(), "page %d is used" % page)
		var inside := Rect2i(padding, RectPacker.page_size(rects, settings) - padding * 2)
		# What each frame takes: its extruded pixels and the spacing on its right and bottom
		var taken: Array[Rect2i] = []
		for rect in rects:
			var outer := Rect2i(rect.position - grow, rect.size + grow * 2)
			assert_true(inside.encloses(outer), "page %d: %s inside %s" % [page, outer, inside])
			taken.append(Rect2i(outer.position, outer.size + Vector2i.ONE * settings.spacing))
		for i in taken.size():
			for j in range(i + 1, taken.size()):
				assert_false(
					taken[i].intersects(taken[j]),
					"page %d: %s and %s overlap" % [page, taken[i], taken[j]]
				)


func test_every_heuristic_packs_without_overlaps() -> void:
	var sizes := random_sizes(80, 3)
	for heuristic: int in AtlasSettings.Heuristic.values():
		for rotation: bool in [false, true]:
			var settings := settings_with(
				{"heuristic": heuristic, "allow_rotation": rotation, "spacing": 2, "extrude": 1}
			)
			var result := RectPacker.pack(sizes, settings)
			assert_eq(result.pages, 1, "heuristic %d" % heuristic)
			assert_valid(sizes, result, settings)


func test_spacing_keeps_frames_apart() -> void:
	var sizes: Array[Vector2i] = [Vector2i(10, 10), Vector2i(10, 10), Vector2i(10, 10)]
	var settings := settings_with({"spacing": 3, "padding": 2})
	var result := RectPacker.pack(sizes, settings)
	var rects: Array[Rect2i] = []
	rects.assign(RectPacker.rects_by_page(sizes, result.placements, 1)[0])
	for i in rects.size():
		assert_true(rects[i].position.x >= 2 and rects[i].position.y >= 2, "padding")
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].grow(2).intersects(rects[j]), "at least 3 pixels apart")


func test_frames_go_on_more_pages_when_they_dont_fit() -> void:
	var sizes := random_sizes(40, 5, 60)
	var settings := settings_with({"max_size": 128, "spacing": 1})
	var result := RectPacker.pack(sizes, settings)
	assert_true(result.pages > 1, "%d pages" % result.pages)
	assert_valid(sizes, result, settings)
	for page_rects: Array in RectPacker.rects_by_page(sizes, result.placements, result.pages):
		var rects: Array[Rect2i] = []
		rects.assign(page_rects)
		var size := RectPacker.page_size(rects, settings)
		assert_true(size.x <= 128 and size.y <= 128, str(size))


func test_frames_too_big_get_their_own_page() -> void:
	var sizes: Array[Vector2i] = [Vector2i(10, 10), Vector2i(300, 20), Vector2i(12, 12)]
	var result := RectPacker.pack(sizes, settings_with({"max_size": 64}))
	assert_eq(result.oversize, [1] as Array[int])
	assert_eq(result.pages, 2)
	assert_eq(result.placements[1].page, 1, "after the others")
	assert_eq(result.placements[0].page, 0)
	assert_eq(result.placements[2].page, 0)


func test_turning_frames_can_save_a_page() -> void:
	# Tall strips only fit side by side on one page when some lie down
	var sizes: Array[Vector2i] = [Vector2i(60, 20), Vector2i(60, 20), Vector2i(20, 60)]
	var settings := settings_with({"max_size": 64})
	assert_eq(RectPacker.pack(sizes, settings).pages, 2, "without turning")
	settings.allow_rotation = true
	var result := RectPacker.pack(sizes, settings)
	assert_eq(result.pages, 1, "with turning")
	assert_valid(sizes, result, settings)
	var turned: Array = result.placements.filter(func(p: Dictionary) -> bool: return p.rotated)
	assert_false(turned.is_empty(), "some are turned")


func test_taken_places_are_left_alone() -> void:
	var taken: Array[Dictionary] = [
		{"page": 0, "rect": Rect2i(0, 0, 30, 30)}, {"page": 1, "rect": Rect2i(10, 10, 20, 20)}
	]
	var sizes := random_sizes(20, 9, 12)
	var settings := settings_with({"max_size": 64, "spacing": 1})
	var result := RectPacker.pack(sizes, settings, taken)
	var pages := RectPacker.rects_by_page(sizes, result.placements, result.pages)
	for page in pages.size():
		for rect: Rect2i in pages[page]:
			for other in taken:
				if other.page == page:
					assert_false(rect.intersects(other.rect.grow(1)), "%s is free" % rect)
	assert_true(pages[0].size() > 0, "fills the free space of the first page")


func test_packing_is_deterministic() -> void:
	var sizes := random_sizes(50, 11)
	var settings := settings_with({"allow_rotation": true, "max_size": 128})
	var first := RectPacker.pack(sizes, settings)
	var second := RectPacker.pack(sizes, settings)
	assert_eq(second.placements, first.placements)


func test_page_sizes() -> void:
	var rects: Array[Rect2i] = [Rect2i(2, 2, 30, 10)]
	assert_eq(RectPacker.page_size(rects, settings_with({"padding": 2})), Vector2i(34, 14))
	assert_eq(RectPacker.page_size(rects, settings_with({"square": true})), Vector2i(32, 32))
	assert_eq(
		RectPacker.page_size(rects, settings_with({"power_of_two": true, "extrude": 1})),
		Vector2i(64, 16)
	)


func test_settings_keep_only_what_changed() -> void:
	var settings := AtlasSettings.new()
	assert_eq(settings.to_dictionary(), {})
	settings.max_size = 1024
	settings.allow_rotation = true
	var copy := AtlasSettings.from_dictionary(settings.to_dictionary())
	assert_eq(copy.max_size, 1024)
	assert_true(copy.allow_rotation)
	assert_eq(AtlasSettings.from_dictionary({"max_size": 99999.0}).max_size, AtlasPacker.MAX_SIZE)
	assert_eq(AtlasSettings.from_dictionary({"heuristic": "nonsense"}).heuristic, 0, "bad values")
