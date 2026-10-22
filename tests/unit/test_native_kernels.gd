extends "res://tests/test_case.gd"
## The native library's in-between loops (NativeKernels) give exactly what the GDScript
## they stand in for gives, ties and all. Without the library (the web build, or when it
## wasn't built) there's nothing to compare, and these pass.

const PinsTest := preload("res://tests/unit/test_inbetween_pins.gd")

var _kernels: Object


func before_each() -> void:
	_kernels = NativeKernels.kernels


func after_each() -> void:
	NativeKernels.kernels = _kernels


## [param work] called with the library, then without it: [code][native, plain][/code]
func _both(work: Callable) -> Array:
	NativeKernels.kernels = _kernels
	var native: Variant = work.call()
	NativeKernels.kernels = null
	var plain: Variant = work.call()
	NativeKernels.kernels = _kernels
	return [native, plain]


func test_the_library_is_used_when_loaded() -> void:
	# Unless it sums otherwise than Godot, see NativeKernels._loaded
	var loaded := ClassDB.class_exists(&"InBetweenKernels")
	assert_eq(_kernels != null, loaded, "used when loaded")


## A few levels only, so many matches cost the same and ties are settled as in GDScript
static func _levels(rng: RandomNumberGenerator, count: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for i in count:
		values.append([0.0, 0.25, 0.5, 1.0][rng.randi() % 4])
	return values


static func _bits(rng: RandomNumberGenerator, count: int) -> PackedByteArray:
	var bits := PackedByteArray()
	for i in count:
		bits.append(rng.randi() % 2)
	return bits


## A round of matching made up on a canvas [param width] × [param height], pixels landing
## up to [param spread] from where they are, some off the canvas
static func _matching(
	rng: RandomNumberGenerator, width: int, height: int, reach: float, spread: float
) -> MeshMatching:
	var colors := MeshTools.Colors.new()
	colors.own = _levels(rng, width * height * 4)
	colors.other = _levels(rng, width * height * 4)
	colors.own_edges = _bits(rng, width * height)
	colors.other_edges = _bits(rng, width * height)
	var located := MeshTools.Located.new()
	var landed := PackedVector2Array()
	var turns := PackedFloat32Array()
	for t in 7:
		turns.append(rng.randf_range(-PI, PI))
	turns.append(0.0)
	turns.append(PI / 4.0)
	for p in width * height:
		if rng.randf() < 0.7:
			located.pixels.append(p)
			located.triangles.append(rng.randi() % turns.size())
			var at := Vector2(p % width + 0.5, p / width + 0.5)
			var off := Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
			# Some exactly on pixel middles or edges
			landed.append(at + (off.round() / 2.0 if rng.randf() < 0.3 else off))
	var mesh := KeyMesh.new()
	mesh.width = width
	mesh.height = height
	return MeshMatching.new(colors, located, turns, landed, reach, mesh)


func test_pixel_matches_are_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for reach: float in [1.0, 2.5, 6.0]:
		var matching := _matching(rng, 23, 17, reach, 4.0)
		var count := matching.located.pixels.size()
		for range_of: Vector2i in [Vector2i(0, count), Vector2i(5, count / 2)]:
			var result := _both(matching.pixel_matches.bind(range_of.x, range_of.y))
			assert_eq(result[0], result[1], "reach %s, pixels %s" % [reach, range_of])
		var all := _both(_all_matches.bind(matching))
		assert_eq(all[0], all[1], "all pixels, reach %s" % reach)


## [method MeshMatching.all_pixel_matches] of [param matching]: [code][goals, pulls][/code]
static func _all_matches(matching: MeshMatching) -> Array:
	var goals := PackedVector2Array()
	var pulls := PackedFloat32Array()
	goals.resize(matching.located.pixels.size())
	pulls.resize(goals.size())
	matching.all_pixel_matches(goals, pulls, 16)
	return [goals, pulls]


func test_edge_pulls_are_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for reach: float in [1.0, 3.0, 7.5]:
		var matching := _matching(rng, 29, 21, reach, 6.0)
		var count := matching.edges.size()
		for range_of: Vector2i in [Vector2i(0, count), Vector2i(3, count / 3)]:
			var result := _both(matching.edge_pulls.bind(range_of.x, range_of.y))
			assert_eq(result[0], result[1], "reach %s, edges %s" % [reach, range_of])


## Features made up for a canvas [param width] × [param height]
static func _features(rng: RandomNumberGenerator, width: int, height: int) -> KeyFeatures:
	var features := KeyFeatures.new()
	features.width = width
	features.height = height
	features.values = _levels(rng, width * height * KeyFeatures.COUNT)
	for i in range(0, features.values.size(), 3):
		features.values[i] = rng.randf_range(-1.0, 1.0)
	return features


func test_landing_sums_are_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var features := _features(rng, 19, 23)
	var other := _features(rng, 21, 17)
	for k in 40:
		var pixels := PackedInt32Array()
		for i in rng.randi_range(0, 120):
			pixels.append(rng.randi() % (19 * 23))
		var motion := Transform2D(
			rng.randf_range(-PI, PI),
			Vector2(rng.randf_range(0.5, 1.6), rng.randf_range(0.5, 1.6)),
			rng.randf_range(-0.3, 0.3),
			Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
		)
		if k % 5 == 0:
			# Whole pixels apart, landing on pixels' middles
			motion = Transform2D(0.0, Vector2(rng.randi_range(-25, 25), rng.randi_range(-25, 25)))
		var stride := 1 + k % 4
		var cap: float = [0.5, 2.0, 100.0][k % 3]
		var cost := 0.0 if k % 2 == 0 else 0.07
		var shift := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
		var work := features.landing_sum.bind(pixels, stride, motion, other, cap, cost, shift)
		var result := _both(work)
		assert_eq(result[0], result[1], "motion %s" % motion)
		var bound := float(k % 7) * 3.0
		var below := features.landing_sum_below.bind(
			pixels, stride, motion, other, cap, cost, shift, bound
		)
		result = _both(below)
		assert_eq(result[0], result[1], "below %s, motion %s" % [bound, motion])


## A key made up on a canvas [param width] × [param height]: a few blobs, some with holes,
## of a few colours and see-through levels, and a few stray pixels
static func _key(rng: RandomNumberGenerator, width: int, height: int) -> PackedByteArray:
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for k in 4:
		var middle := Vector2(rng.randf_range(0, width), rng.randf_range(0, height))
		var radius := rng.randf_range(2.0, 7.0)
		var color := Color8(
			rng.randi() % 4 * 80, 200, rng.randi() % 3 * 120, [255, 200, 128, 90][k]
		)
		for y in height:
			for x in width:
				var apart := Vector2(x + 0.5, y + 0.5).distance_to(middle)
				if apart <= radius and (k != 1 or apart > radius * 0.4):
					img.set_pixel(x, y, color)
	for k in 6:
		img.set_pixel(rng.randi() % width, rng.randi() % height, Color(1, 0, 0, rng.randf()))
	return img.get_data()


func test_distances_are_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for size: Vector2i in [Vector2i(1, 1), Vector2i(1, 9), Vector2i(13, 1), Vector2i(31, 22)]:
		var data := _key(rng, size.x, size.y)
		var mask := PixelCanvas.mask(data)
		var empty := PackedByteArray()
		empty.resize(mask.size())
		for value in 2:
			for far: int in [0, 40]:
				for of: PackedByteArray in [mask, empty]:
					var work := PixelCanvas.distances.bind(of, size.x, size.y, value, far)
					var result := _both(work)
					assert_eq(result[0], result[1], "%s, value %d, far %d" % [size, value, far])


func test_pixel_loops_are_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for size: Vector2i in [Vector2i(1, 1), Vector2i(17, 3), Vector2i(36, 28)]:
		var data := _key(rng, size.x, size.y)
		var features := _both(KeyFeatures.of.bind(data, size.x, size.y, 2.5))
		assert_eq(features[0].values, features[1].values, "features %s" % size)
		assert_eq(features[0].scale, features[1].scale, "features' scale")
		assert_eq(features[0].width, features[1].width, "features' width")
		assert_eq(features[0].height, features[1].height, "features' height")
		var colors := MeshTools.premultiplied(data)
		var edges := _both(MeshTools.edges.bind(colors, size.x, size.y, KeyMesh.EDGE_STEP))
		assert_eq(edges[0], edges[1], "edges %s" % size)


func test_tidying_up_is_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	for k in 6:
		# Keys with a transparent border, and a frame to tidy made up from bits of them
		var size := Vector2i(30, 26)
		var key := _key(rng, size.x - 4, size.y - 4)
		var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		var inner := Image.create_from_data(size.x - 4, size.y - 4, false, Image.FORMAT_RGBA8, key)
		img.blit_rect(inner, Rect2i(Vector2i.ZERO, inner.get_size()), Vector2i(2, 2))
		var data := img.get_data()
		var least_alpha: int = [1, 128][k % 2]
		var shapes := _both(PixelCleanup.shapes_of.bind(data, size.x, size.y, least_alpha))
		assert_eq(shapes[0], shapes[1], "shapes, key %d" % k)
		var wide := _both(PixelCleanup.wide_shapes_of.bind(data, size.x, size.y, least_alpha))
		assert_eq(wide[0].keys(), wide[1].keys(), "wide shapes, key %d" % k)
		var frame := data.duplicate()
		for p in range(size.x * 2, frame.size() / 4 - size.x * 2):
			if rng.randf() < 0.15:
				for c in 4:
					frame[p * 4 + c] = frame[(p + rng.randi_range(-3, 3)) * 4 + c]
		var tidied: Array[PackedByteArray] = [frame.duplicate(), frame.duplicate()]
		var smoothed: Array[PackedByteArray] = [frame.duplicate(), frame.duplicate()]
		var wide_shapes: Dictionary = wide[1] if k < 4 else {}
		for kind in 2:
			NativeKernels.kernels = _kernels if kind == 0 else null
			PixelCleanup.tidy_data(tidied[kind], size.x, size.y)
			PixelCleanup.smooth_jags(
				smoothed[kind], size.x, size.y, shapes[1], least_alpha, wide_shapes
			)
		NativeKernels.kernels = _kernels
		assert_eq(tidied[0], tidied[1], "tidied, key %d" % k)
		assert_eq(smoothed[0], smoothed[1], "smoothed, key %d" % k)


func test_warps_are_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for k in 6:
		var n := rng.randi_range(8, 30)
		var m := rng.randi_range(8, 30)
		var costs := PackedFloat32Array()
		for i in n * m:
			costs.append(rng.randf() if k % 2 == 0 else float(rng.randi() % 3) / 4.0)
		var start := rng.randi() % m
		var both := _both(ShapeBlend._warp.bind(costs, n, m, start, PackedByteArray()))
		assert_eq(both[0], both[1], "warp %d × %d from %d" % [n, m, start])
		var moves: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray()]
		for kind in 2:
			moves[kind].resize(n * m)
		NativeKernels.kernels = _kernels
		var native := ShapeBlend._warp(costs, n, m, start, moves[0])
		NativeKernels.kernels = null
		var plain := ShapeBlend._warp(costs, n, m, start, moves[1])
		NativeKernels.kernels = _kernels
		assert_eq(native, plain, "warp written")
		assert_eq(moves[0], moves[1], "moves written")


func test_sorting_orders_ties_as_godot() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	for size: int in [0, 1, 2, 5, 16, 17, 33, 100, 257, 1000]:
		var keys := PackedFloat64Array()
		for i in size:
			keys.append(rng.randi() % maxi(size / 6, 2))
		var order := range(size)
		order.sort_custom(func(x: int, y: int) -> bool: return keys[x] < keys[y])
		var native: PackedInt32Array = _kernels.call(&"sorted_by_key", keys)
		assert_eq(native, PackedInt32Array(order), "%d keys" % size)


## A key with a transparent border made up on a canvas [param width] × [param height]: a
## few rectangles of a few colours, touching or apart
static func _figure(rng: RandomNumberGenerator, width: int, height: int) -> PackedByteArray:
	var img := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var colors: Array[Color] = [Color.SEA_GREEN, Color("f2c094"), Color("3b6fd1"), Color.BLACK]
	for k in 7:
		var size := Vector2i(rng.randi_range(2, 9), rng.randi_range(2, 9))
		var at := Vector2i(
			rng.randi_range(2, width - 2 - size.x), rng.randi_range(2, height - 2 - size.y)
		)
		img.fill_rect(Rect2i(at, size), colors[k % colors.size()])
	return img.get_data()


func test_regions_are_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for k in 4:
		var data := _figure(rng, 33, 27)
		var both := _both(KeyRegions.of.bind(data, 33, PixelCanvas.colors(data)))
		if k >= 2:
			# Labels anywhere, the edges' too
			var labels := PackedInt32Array()
			for p in 33 * 27:
				labels.append(rng.randi_range(-1, 6) if rng.randf() < 0.3 else (p / 5) % 7 - 1)
			both = _both(KeyRegions.from_labels.bind(_key(rng, 33, 27), 33, labels))
		var native: KeyRegions = both[0]
		var plain: KeyRegions = both[1]
		assert_eq(native.labels, plain.labels, "labels, key %d" % k)
		assert_eq(native.pixels, plain.pixels, "pixels, key %d" % k)
		assert_eq(native.centers, plain.centers, "centers, key %d" % k)
		assert_eq(native.colors, plain.colors, "colors, key %d" % k)
		assert_eq(native.axes, plain.axes, "axes, key %d" % k)
		assert_eq(native.elongations, plain.elongations, "elongations, key %d" % k)
		assert_eq(native.borders.keys(), plain.borders.keys(), "borders' order, key %d" % k)
		assert_eq(native.borders.values(), plain.borders.values(), "borders, key %d" % k)
		assert_eq([native.width, native.height], [plain.width, plain.height], "size")


func test_shrinking_is_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for shrink: int in [2, 3, 5]:
		var data := _key(rng, 31, 22)
		var both := _both(PieceMorph._shrunk.bind(data, 31, 22, shrink))
		assert_eq(both[0], both[1], "%d times smaller" % shrink)


func test_solving_is_the_same() -> void:
	if not _kernels:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var from := PackedInt32Array()
	var to := PackedInt32Array()
	for i in 29:
		from.append(i)
		to.append(i + 1)
		from.append(i)
		to.append((i * 7 + 3) % 30)
	for k in 3:
		var matrix := MeshMatrix.new(30, from, to)
		for e in from.size():
			matrix.sides[e] = -rng.randf_range(0.1, 2.0)
			matrix.diagonal[from[e]] += 2.0
			matrix.diagonal[to[e]] += 2.0
		matrix.add_diagonal(rng.randf_range(1e-6, 0.5))
		var right := PackedVector2Array()
		var start := PackedVector2Array()
		for i in 30:
			right.append(Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9)))
			start.append(Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
		var solved: Array[PackedVector2Array] = [start.duplicate(), start.duplicate()]
		NativeKernels.kernels = _kernels
		matrix.solve(solved[0], right, 5 + k * 20, 1e-4)
		NativeKernels.kernels = null
		matrix.solve(solved[1], right, 5 + k * 20, 1e-4)
		NativeKernels.kernels = _kernels
		assert_eq(solved[0], solved[1], "solved in %d steps" % (5 + k * 20))


## The frames of in-betweens of each kind, see test_inbetween_pins.gd
static func _frames(kind: int) -> Array:
	var morph: PieceMorph = PinsTest.morphs()[kind]
	var pins: Array[Dictionary] = [{"at": Vector2(16, 12), "to": Vector2(19, 9)}]
	var frames := []
	for t: float in [0.25, 0.5, 0.75]:
		for pinned: Array[Dictionary] in [[] as Array[Dictionary], pins]:
			var frame := morph.frame(t, pinned)
			frames.append([frame.origin, (frame.image as Image).get_data()])
	return frames


func test_frames_are_the_same() -> void:
	if not _kernels:
		return
	for kind in 3:
		var both := _both(_frames.bind(kind))
		assert_eq(both[0], both[1], "frames of kind %d" % kind)


## How each region of one made-up key moves to the other, with the library or without
static func _motions(seed_value: int) -> RegionMotions:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := Vector2i(36, 30)
	var a := _figure(rng, size.x, size.y)
	var b := _figure(rng, size.x, size.y)
	var split := KeyRegions.split_colors_of(a, b)
	var a_regions := KeyRegions.of(a, size.x, split[0])
	var b_regions := KeyRegions.of(b, size.x, split[1])
	var a_features := KeyFeatures.of(a, size.x, size.y, 2.0)
	var b_features := KeyFeatures.of(b, size.x, size.y, 2.0)
	return RegionMotions.find(
		a_regions, a_features, b_regions, b_features, Vector2(1, -1), 30.0, WorkProgress.new()
	)


func test_region_motions_are_the_same() -> void:
	if not _kernels:
		return
	for seed_value in 4:
		var both := _both(_motions.bind(seed_value))
		var native: RegionMotions = both[0]
		var plain: RegionMotions = both[1]
		assert_eq(native.chosen, plain.chosen, "chosen, key %d" % seed_value)
		# Each part on its own, on the same regions
		var voters := plain._voters()
		for r in plain.regions.count():
			var searched := _both(plain._search.bind(r, voters))
			assert_eq(searched[0], searched[1], "searched, key %d region %d" % [seed_value, r])
		var candidates: Array[Transform2D] = [Transform2D(), Transform2D()]
		for r in plain.regions.count():
			candidates.append_array(plain._search(r, voters))
		var count := plain.regions.count()
		var choice := RegionChoice.new()
		choice.motions = plain
		choice.regions = plain.regions
		var best := _both(choice._own_best.bind(1, count, candidates))
		assert_eq(best[0], best[1], "own best, key %d" % seed_value)
		var keys := plain.regions.borders.keys()
		var choices: Array[Array] = []
		for r in count:
			choices.append(candidates.slice(r, r + 5))
		var tables := _both(choice._apart_tables.bind(0, keys.size(), keys, choices))
		assert_eq(tables[0], tables[1], "apart tables, key %d" % seed_value)
