class_name NativeKernels
extends RefCounted
## The in-betweens' hottest loops in the native library (native/src/inbetween.rs), when it's
## loaded: they give exactly what the GDScript they stand in for gives, much faster. The
## web build has no native library, and a desktop build where it failed to load works the
## same without it; the functions they stand in for call these when [member kernels] is set.

## The library's InBetweenKernels, whose functions are static; null without it, see
## [method _loaded]. Tests set it to null to compare with the GDScript.
static var kernels: Object = _loaded()


## The library's kernels, or null when it isn't loaded or works out Godot's vector sums
## otherwise than this Godot does (one built to fuse multiplications and additions would)
static func _loaded() -> Object:
	if not ClassDB.class_exists(&"InBetweenKernels"):
		return null
	var found: Object = ClassDB.instantiate(&"InBetweenKernels")
	var points := PackedVector2Array()
	var motions: Array[Transform2D] = []
	var expected := PackedFloat64Array()
	for k in 24:
		var a := Vector2(sin(k * 1.3) * 97.31 + k, cos(k * 0.7) * 53.17 - k * 0.37)
		var b := Vector2(cos(k * 2.1) * 41.9 - k, sin(k * 0.9) * 77.7 + 0.123)
		var motion := Transform2D(
			k * 0.37, Vector2(1.0 + k * 0.13, 0.7 + k * 0.05), k * 0.02, a - b
		)
		points.append_array([a, b])
		motions.append(motion)
		var moved := motion * a
		var bent := Transform2D(a, b, Vector2.ZERO) * motion.affine_inverse()
		var sums := [moved.x, moved.y, a.length_squared(), a.dot(b), a.cross(b), a.distance_to(b)]
		sums.append_array([a.distance_squared_to(b), motion.determinant()])
		sums.append_array([bent.x.x, bent.x.y, bent.y.x, bent.y.y])
		expected.append_array(sums)
	if found.call(&"engine_math", points, motions) != expected:
		print_verbose("In-betweens worked out in GDScript: the native library sums otherwise")
		return null
	return found


## [method MeshMatching.pixel_matches]
static func pixel_matches(matching: MeshMatching, start: int, end: int) -> Array:
	var size := Vector2i(matching.width, matching.height)
	var numbers := _matching_numbers(matching)
	return kernels.call(&"pixel_matches", size, _matching_arrays(matching), numbers, start, end)


## [method MeshMatching.all_pixel_matches], on threads by runs of at least [param least]
static func all_pixel_matches(
	matching: MeshMatching, goals: PackedVector2Array, pulls: PackedFloat32Array, least: int
) -> void:
	var size := Vector2i(matching.width, matching.height)
	var arrays := _matching_arrays(matching)
	var numbers := _matching_numbers(matching)
	var work := func(start: int, end: int) -> Array:
		return kernels.call(&"pixel_matches", size, arrays, numbers, start, end)
	var parts := Parallel.split(goals.size(), least, work)
	goals.clear()
	pulls.clear()
	for part: Array in parts:
		goals.append_array(part[0])
		pulls.append_array(part[1])


## [method MeshMatching.edge_pulls]
static func edge_pulls(matching: MeshMatching, start: int, end: int) -> Array:
	var size := Vector2i(matching.width, matching.height)
	var numbers := _matching_numbers(matching)
	return kernels.call(&"edge_pulls", size, _matching_arrays(matching), numbers, start, end)


## [method KeyFeatures.landing_sum], or [method KeyFeatures.landing_sum_below] given
## [param bound]
static func landing_sum(
	features: KeyFeatures,
	pixels: PackedInt32Array,
	stride: int,
	motion: Transform2D,
	other: KeyFeatures,
	cap: float,
	move_cost: float,
	shift: Vector2,
	bound := INF
) -> float:
	var other_size := Vector2i(other.width, other.height)
	return kernels.call(
		&"landing_sum",
		features.values,
		features.width,
		pixels,
		stride,
		motion,
		other.values,
		other_size,
		cap,
		move_cost,
		shift,
		bound
	)


## [method PixelCanvas.distances]
static func distances(
	mask_data: PackedByteArray, width: int, height: int, value: int, far: int
) -> Array[PackedInt32Array]:
	return kernels.call(&"distances", mask_data, width, height, value, far)


## [method KeyFeatures.of]
static func features_of(
	data: PackedByteArray, canvas_width: int, canvas_height: int, depth_scale: float
) -> KeyFeatures:
	var features := KeyFeatures.new()
	features.width = canvas_width
	features.height = canvas_height
	features.scale = depth_scale
	var weights := PackedFloat64Array(
		[KeyFeatures.SHOWN_WEIGHT, KeyFeatures.DEPTH_WEIGHT, KeyFeatures.DEPTH_REACH]
	)
	features.values = kernels.call(
		&"features_of", data, canvas_width, canvas_height, depth_scale, weights
	)
	return features


## [method MeshTools.edges]
static func edges(
	colors: PackedFloat32Array, width: int, height: int, least_step: float
) -> PackedByteArray:
	return kernels.call(&"edges", colors, width, height, least_step)


## [method ShapeBlend._warp], writing into [param moves] as it does
static func warp(
	costs: PackedFloat32Array, n: int, m: int, start: int, moves: PackedByteArray
) -> float:
	var writing := not moves.is_empty()
	var found: Array = kernels.call(&"warp", costs, n, m, start, ShapeBlend.STEP_COST, writing)
	if writing:
		moves.resize(0)
		moves.append_array(found[1])
	return found[0]


## [method RegionMotions._search_pixels]
static func search_pixels(
	motions: RegionMotions, pixels: PackedInt32Array, voters: Array
) -> Array[Transform2D]:
	var arrays := [motions.features.values, motions.other.values, voters[0], voters[1]]
	return kernels.call(&"search_pixels", pixels, arrays, _motions_numbers(motions))


## [method RegionChoice._own_best], every cost worked out
static func own_best(
	choice: RegionChoice, start: int, end: int, candidates: Array[Transform2D]
) -> Array:
	var motions := choice.motions
	var pixels := motions.regions.pixels.slice(start, end)
	var arrays := [motions.features.values, motions.other.values]
	var numbers := _motions_numbers(motions)
	return kernels.call(&"own_best", pixels, candidates, arrays, numbers)


## [method RegionChoice._apart_tables]
static func apart_tables(
	choice: RegionChoice, start: int, end: int, keys: Array, choices: Array[Array]
) -> Array:
	var regions := choice.regions
	var pairs := PackedInt32Array()
	var borders: Array[PackedVector2Array] = []
	for n in range(start, end):
		var key: Vector2i = keys[n]
		pairs.append_array([key.x, key.y])
		borders.append(regions.borders[key])
	var of_regions := [regions.pixels, regions.colors]
	var numbers := _motion_constants()
	return kernels.call(
		&"apart_tables", pairs, borders, choices, of_regions, regions.width, numbers
	)


## [method KeyRegions.from_labels]
static func regions_from_labels(
	data: PackedByteArray, canvas_width: int, region_labels: PackedInt32Array
) -> KeyRegions:
	var found: Array = kernels.call(&"regions_from_labels", data, canvas_width, region_labels)
	var regions := KeyRegions.new()
	regions.width = canvas_width
	regions.height = region_labels.size() / canvas_width
	regions.labels = region_labels
	regions.pixels = found[0]
	regions.centers = found[1]
	regions.colors = found[2]
	regions.axes = found[3]
	regions.elongations = found[4]
	var pairs: PackedInt32Array = found[5]
	var borders: Array[PackedVector2Array] = found[6]
	for k in borders.size():
		regions.borders[Vector2i(pairs[k * 2], pairs[k * 2 + 1])] = borders[k]
	return regions


## [method PieceMorph._shrunk]
static func shrunk(data: PackedByteArray, width: int, height: int, shrink: int) -> PackedByteArray:
	return kernels.call(&"shrunk", data, width, height, shrink)


## [method MeshMatrix.solve], writing into [param x] as it does
static func solve(
	matrix: MeshMatrix, x: PackedVector2Array, right: PackedVector2Array, steps: int, close: float
) -> void:
	var solved: PackedVector2Array = kernels.call(
		&"solve", matrix.diagonal, matrix.sides, matrix._from, matrix._to, x, right, steps, close
	)
	x.resize(0)
	x.append_array(solved)


## [method KeyMesh._lay], moving [member KeyMesh.target] as it does
static func lay(
	mesh: KeyMesh,
	located: MeshTools.Located,
	goals: PackedVector2Array,
	pulls: PackedFloat32Array,
	extra: PackedInt32Array,
	extra_goals: PackedVector2Array,
	extra_pulls: PackedFloat32Array,
	stiffness: float,
	rounds: int
) -> void:
	var of_mesh := [
		mesh.rest,
		mesh.target,
		mesh.triangles,
		mesh.weights,
		mesh._side_from,
		mesh._side_to,
		mesh._triangle_sides,
		mesh._laplacian.diagonal,
		mesh._laplacian.sides,
	]
	var pulled := [
		located.triangles, located.weights, goals, pulls, extra, extra_goals, extra_pulls
	]
	var numbers := PackedFloat64Array(
		[mesh._stiff_total, stiffness, rounds, KeyMesh.SOLVER_STEPS, KeyMesh.SOLVER_CLOSE]
	)
	var laid: PackedVector2Array = kernels.call(&"lay", of_mesh, pulled, numbers)
	mesh.target.resize(0)
	mesh.target.append_array(laid)


## [method MeshDrawing.drawn]
static func drawn(
	drawing: MeshDrawing,
	mesh: KeyMesh,
	t: float,
	pin_from: PackedVector2Array,
	pin_to: PackedVector2Array
) -> PackedByteArray:
	var positions := mesh.pinned(mesh.at(t), t, pin_from, pin_to)
	for i in positions.size():
		positions[i] *= drawing._scale
	var located := drawing._points
	var arrays := [
		drawing._data,
		located.points,
		located.pixels,
		located.triangles,
		located.weights,
		drawing._strays,
		mesh.depth,
		mesh.triangles,
		mesh.weights,
		mesh.rest,
	]
	var numbers := PackedFloat64Array(
		[
			drawing._scale,
			drawing._width,
			drawing._height,
			mesh.width,
			MeshDrawing.ALIKE_REACH,
			MeshDrawing.OWN_MOVE,
			KeyMesh.MAGNIFIED,
			KeyMesh.TURNED,
		]
	)
	return kernels.call(&"drawn", arrays, positions, numbers)


## [method FlowMorph._moved]
static func flow_moved(
	morph: FlowMorph,
	data: PackedByteArray,
	flow: PackedVector2Array,
	doubt: PackedFloat32Array,
	t: float
) -> PackedByteArray:
	var area := morph._keys_area
	var numbers := PackedFloat64Array(
		[morph.width, morph.height, area.position.x, area.position.y, area.end.x, area.end.y]
	)
	numbers.append_array([FlowMorph.MOST_STRETCH, FlowMorph.CLOSE])
	return kernels.call(&"flow_moved", data, flow, doubt, t, numbers)


## [method PixelCleanup.tidy_data], in place
static func tidy_data(data: PackedByteArray, width: int, height: int) -> void:
	var tidied: PackedByteArray = kernels.call(&"tidy_data", data, width, height)
	data.clear()
	data.append_array(tidied)


## [method PixelCleanup.smooth_jags], in place
static func smooth_jags(
	data: PackedByteArray,
	width: int,
	height: int,
	shapes: PackedInt32Array,
	least_alpha: int,
	wide_shapes: Dictionary
) -> void:
	var wide := PackedInt64Array(wide_shapes.keys())
	var smoothed: PackedByteArray = kernels.call(
		&"smooth_jags", data, width, height, shapes, least_alpha, wide
	)
	data.clear()
	data.append_array(smoothed)


## [method PixelCleanup.shapes_of]
static func shapes_of(
	data: PackedByteArray, width: int, height: int, least_alpha: int
) -> PackedInt32Array:
	return kernels.call(&"shapes_of", data, width, height, least_alpha)


## [method PixelCleanup.wide_shapes_of]
static func wide_shapes_of(
	data: PackedByteArray, width: int, height: int, least_alpha: int
) -> Dictionary:
	var found := {}
	for shape: int in kernels.call(&"wide_shapes_of", data, width, height, least_alpha):
		found[shape] = true
	return found


static func _motions_numbers(motions: RegionMotions) -> PackedFloat64Array:
	var numbers := PackedFloat64Array(
		[
			motions.regions.width,
			motions.features.width,
			motions.other.width,
			motions.other.height,
			motions.shift.x,
			motions.shift.y,
			motions.side,
		]
	)
	numbers.append_array(_motion_constants())
	return numbers


## RegionMotions' constants, in the order the library reads them
static func _motion_constants() -> PackedFloat64Array:
	return PackedFloat64Array(
		[
			RegionMotions.CAP,
			RegionMotions.MOVE_COST,
			RegionMotions.AREA_COST,
			RegionMotions.SAMPLES,
			RegionMotions.TURNS,
			RegionMotions.VOTED,
			RegionMotions.KEPT_PER_TURN,
			RegionMotions.APART,
			RegionMotions.KEPT,
			RegionMotions.ANCHORS,
			RegionMotions.ANCHOR_COLOR,
			RegionMotions.VOTERS,
			RegionMotions.DISTANCE_COST,
			KeyFeatures.SHOWN_WEIGHT,
			RegionChoice.OWN_CHOICES,
			RegionChoice.ALIKE,
			RegionChoice.APART_COST,
			RegionChoice.ALIKE_APART_COST,
			RegionChoice.GAP_CAP,
			RegionChoice.BORDER_POINTS,
			RegionChoice.REGION_POINTS,
		]
	)


static func _matching_arrays(matching: MeshMatching) -> Array:
	var colors := matching.colors
	return [
		colors.own,
		colors.other,
		colors.own_edges,
		matching.located.pixels,
		matching.located.triangles,
		matching.turns,
		matching.landed,
		matching.spot_x,
		matching.spot_y,
		matching.spot_least,
		matching.edges,
	]


static func _matching_numbers(matching: MeshMatching) -> PackedFloat64Array:
	return PackedFloat64Array(
		[matching.near_cost, matching.cell, KeyMesh.FLAT_PULL, KeyMesh.EDGE_PULL, KeyMesh.LIKENESS]
	)
