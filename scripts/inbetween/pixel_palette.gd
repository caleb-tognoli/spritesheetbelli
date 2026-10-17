class_name PixelPalette
extends RefCounted
## A few colours standing for the many of painted sprites, with soft edges and smooth
## shading, so their parts can be told apart like pixel art's, see [PartMorph]. Only red,
## green and blue count: a soft edge goes with the colour it fades out of.


## How many colours pixels shown in [param colors] have, up to [param most] + 1
static func count(colors: PackedInt32Array, most: int) -> int:
	var seen := {}
	for color in colors:
		if color != 0:
			seen[color >> 8] = true
			if seen.size() > most:
				break
	return seen.size()


## [param first] and [param second] (see [method PixelCanvas.colors]) with every shown
## pixel's colour replaced by the nearest of [param size] colours picked for both together,
## so a colour in one is the same colour in the other: [code][first, second][/code]
static func reduce(
	first: PackedInt32Array, second: PackedInt32Array, size: int
) -> Array[PackedInt32Array]:
	# Every colour once, with how many pixels have it
	var weights := {}
	for colors: PackedInt32Array in [first, second]:
		for color: int in colors:
			if color != 0:
				var rgb := color >> 8 & 0xffffff
				weights[rgb] = weights.get(rgb, 0) + 1
	var points: Array[Vector3] = []
	var counts: Array[int] = []
	for rgb: int in weights:
		points.append(Vector3(rgb >> 16 & 255, rgb >> 8 & 255, rgb & 255))
		counts.append(weights[rgb])
	var centers := _pick_centers(points, counts, size)
	# A few rounds of moving each centre to the middle of the colours nearest it
	for _round in ROUNDS:
		var totals: Array[Vector3] = []
		var sums: Array[int] = []
		for center in centers:
			totals.append(Vector3.ZERO)
			sums.append(0)
		for i in points.size():
			var nearest := _nearest(centers, points[i])
			totals[nearest] += points[i] * counts[i]
			sums[nearest] += counts[i]
		for c in centers.size():
			if sums[c] > 0:
				centers[c] = totals[c] / sums[c]
	var mapped := {}
	for i in points.size():
		var center := centers[_nearest(centers, points[i])]
		var rgb := int(points[i].x) << 16 | int(points[i].y) << 8 | int(points[i].z)
		# Never 0, which is transparent
		mapped[rgb] = (
			(roundi(center.x) << 24 | roundi(center.y) << 16 | roundi(center.z) << 8) | 255
		)
	var reduced: Array[PackedInt32Array] = []
	for colors: PackedInt32Array in [first, second]:
		var out := PackedInt32Array()
		out.resize(colors.size())
		for p in colors.size():
			out[p] = mapped[colors[p] >> 8 & 0xffffff] if colors[p] != 0 else 0
		reduced.append(out)
	return reduced


## Rounds of refining the colours picked, see [method reduce]
const ROUNDS := 8


## [param size] starting colours among [param points]: the most common, then each the
## colour farthest from those picked, weighed a little by how common it is
static func _pick_centers(points: Array[Vector3], counts: Array[int], size: int) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	if points.is_empty():
		return centers
	var first := 0
	for i in points.size():
		if counts[i] > counts[first]:
			first = i
	centers.append(points[first])
	var nearest_distance := PackedFloat32Array()
	nearest_distance.resize(points.size())
	for i in points.size():
		nearest_distance[i] = points[i].distance_squared_to(points[first])
	while centers.size() < mini(size, points.size()):
		var best := 0
		var best_value := -1.0
		for i in points.size():
			var value := nearest_distance[i] * sqrt(float(counts[i]))
			if value > best_value:
				best = i
				best_value = value
		if best_value <= 0.0:
			break
		centers.append(points[best])
		for i in points.size():
			nearest_distance[i] = minf(
				nearest_distance[i], points[i].distance_squared_to(points[best])
			)
	return centers


static func _nearest(centers: Array[Vector3], point: Vector3) -> int:
	var best := 0
	var best_distance := INF
	for c in centers.size():
		var distance := centers[c].distance_squared_to(point)
		if distance < best_distance:
			best = c
			best_distance = distance
	return best
