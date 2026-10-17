class_name MeshDrawing
extends RefCounted
## A [KeyMesh]'s key drawn in frames, see [method KeyMesh.draw_from] and
## [method KeyMesh.drawn]

## Pixels moved by whole pixels take the move most of those up to this many pixels
## round have, of the moves within a pixel of theirs, theirs counting this much more
const ALIKE_REACH := 2
const OWN_MOVE := 0.3

## The key, [member _scale] times bigger than worked out; its pixels placed in the
## triangles
var _data := PackedByteArray()
var _scale := 1
var _points: MeshTools.Located
## Pixels of the key shown off the triangles and the nearest pixel on them, in pairs
var _strays := PackedInt32Array()


## [param mesh]'s frames drawn from [param full_data], the key drawn [param scale] times
## bigger than worked out, on a canvas that much bigger
func _init(mesh: KeyMesh, full_data: PackedByteArray, scale: int) -> void:
	_data = full_data
	_scale = scale
	_points = mesh.locate(MeshTools.shown_points(full_data, mesh.width * scale, 1), scale)
	_find_strays(mesh.width * scale, mesh.height * scale)


## The key [param t] of the way to the other key, see [method KeyMesh.drawn]; given
## [param mesh] (the one it was made for) rather than keeping it, which would keep both
func drawn(
	mesh: KeyMesh, t: float, pin_from: PackedVector2Array, pin_to: PackedVector2Array
) -> PackedByteArray:
	var full_data := _data
	var scale := _scale
	var width := mesh.width
	var big_width := width * scale
	var big_height := mesh.height * scale
	var positions := mesh.pinned(mesh.at(t), t, pin_from, pin_to)
	for i in positions.size():
		positions[i] *= scale
	var located := _points
	var count := located.pixels.size()
	var landed := located.at(positions, mesh.triangles)
	# Whole-pixel moves, then each the move most of its neighbours moving alike have
	var moves := PackedVector2Array()
	moves.resize(count)
	var move_at := {}
	for s in count:
		var move := (landed[s] - located.points[s]).round()
		moves[s] = move
		move_at[located.pixels[s]] = s
	var chosen := PackedVector2Array()
	chosen.resize(count)
	for s in count:
		var p := located.pixels[s]
		var px := p % big_width
		var py := p / big_width
		var own := moves[s]
		var tally := {}
		for dy in range(-ALIKE_REACH, ALIKE_REACH + 1):
			for dx in range(-ALIKE_REACH, ALIKE_REACH + 1):
				var qx := px + dx
				var qy := py + dy
				if qx < 0 or qy < 0 or qx >= big_width or qy >= big_height:
					continue
				var other: int = move_at.get(qy * big_width + qx, -1)
				if other < 0:
					continue
				var move := moves[other]
				if absf(move.x - own.x) > 1.0 or absf(move.y - own.y) > 1.0:
					continue
				tally[move] = tally.get(move, 0.0) + 1.0
		tally[own] = tally.get(own, 0.0) + OWN_MOVE
		var best := own
		var most := -1.0
		for move: Vector2 in tally:
			if tally[move] > most:
				most = tally[move]
				best = move
		chosen[s] = best
	# Pixels off the triangles, like a faint glow, move with the nearest pixel on them
	var pixels := located.pixels.duplicate()
	for k in range(0, _strays.size(), 2):
		var s: int = move_at[_strays[k + 1]]
		pixels.append(_strays[k])
		chosen.append(chosen[s])
		var apart := Vector2(
			_strays[k] % big_width - _strays[k + 1] % big_width,
			_strays[k] / big_width - _strays[k + 1] / big_width
		)
		landed.append(landed[s] + apart)
	var out := PixelCanvas.blank(big_width * big_height)
	var front := PackedFloat32Array()
	front.resize(big_width * big_height)
	front.fill(-INF)
	var depth := mesh.depth
	for s in pixels.size():
		var p := pixels[s]
		var dest := Vector2i(p % big_width, p / big_width) + Vector2i(chosen[s])
		if dest.x < 0 or dest.y < 0 or dest.x >= big_width or dest.y >= big_height:
			continue
		var small := (p / big_width / scale) * width + (p % big_width) / scale
		var rank := depth[small] if small < depth.size() else 0
		var key := rank * 100.0 - landed[s].distance_to(Vector2(dest) + Vector2(0.5, 0.5))
		var q := dest.y * big_width + dest.x
		if key < front[q]:
			continue
		front[q] = key
		for c in 4:
			out[q * 4 + c] = full_data[p * 4 + c]
	# Gaps a pixel across filled from the triangles drawn over
	var covered := PackedByteArray()
	covered.resize(big_width * big_height)
	for p in covered.size():
		covered[p] = 1 if out[p * 4 + 3] > 0 else 0
	var closed := MeshTools.closed(covered, big_width, big_height)
	var grown := PackedByteArray()
	var over := MeshTools.drawn_over(mesh, positions, full_data, scale, grown)
	var over_shown := PackedByteArray()
	over_shown.resize(covered.size())
	for p in covered.size():
		over_shown[p] = 1 if over[p * 4 + 3] > 0 else 0
	var over_closed := MeshTools.closed(over_shown, big_width, big_height)
	for p in covered.size():
		# Grown much, smooth from the triangles drawn over, but for pinholes in them
		var smooth := grown[p] == 1 and (over_shown[p] == 1 or over_closed[p] == 0)
		if smooth or (covered[p] == 0 and closed[p] == 1 and over_shown[p] == 1):
			for c in 4:
				out[p * 4 + c] = over[p * 4 + c]
	return out


## The pixels of the key (a canvas [param big_width] × [param big_height]) shown but off
## the triangles, each with the nearest pixel on them, see [member _strays]
func _find_strays(big_width: int, big_height: int) -> void:
	_strays = PackedInt32Array()
	var on := PackedByteArray()
	on.resize(big_width * big_height)
	for p in _points.pixels:
		on[p] = 1
	var nearest: PackedInt32Array = PixelCanvas.distances(on, big_width, big_height, 1)[1]
	for p in on.size():
		if on[p] == 0 and _data[p * 4 + 3] > 0 and nearest[p] >= 0:
			_strays.append_array([p, nearest[p]])
