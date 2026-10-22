class_name MeshMatrix
extends RefCounted
## A symmetric matrix over the corners, its numbers off the diagonal only where corners
## are joined by a triangle side, solved by conjugate gradients

var diagonal := PackedFloat64Array()
## For each joined pair, see [KeyMesh]
var sides := PackedFloat64Array()
## What [method add_diagonal] added last
var diagonal_extra := 0.0
var _from: PackedInt32Array
var _to: PackedInt32Array


func _init(corners: int, from: PackedInt32Array, to: PackedInt32Array) -> void:
	diagonal.resize(corners)
	sides.resize(from.size())
	_from = from
	_to = to


## Adds [param other] times [param amount]
func add_scaled(other: MeshMatrix, amount: float) -> void:
	var own_diagonal := diagonal
	var own_sides := sides
	var other_diagonal := other.diagonal
	var other_sides := other.sides
	for i in own_diagonal.size():
		own_diagonal[i] += other_diagonal[i] * amount
	for e in own_sides.size():
		own_sides[e] += other_sides[e] * amount


## Adds the pixels of [param located] [param which] says (all of them in turn when empty),
## each pulled to its [param goals] by its [param pulls], to the matrix and
## [param right], with the triangles' [param corners] (three each) and the sides from each
## corner to the next round, among the joined pairs, [param corner_sides]
func add_pulls(
	corners: PackedInt32Array,
	corner_sides: PackedInt32Array,
	located: MeshTools.Located,
	which: PackedInt32Array,
	goals: PackedVector2Array,
	pulls: PackedFloat32Array,
	right: PackedVector2Array
) -> void:
	var own_diagonal := diagonal
	var own_sides := sides
	var located_triangles := located.triangles
	var located_weights := located.weights
	var all := which.is_empty()
	for e in pulls.size():
		var pull := pulls[e]
		if pull <= 0.0:
			continue
		var s := e if all else which[e]
		var goal := goals[e]
		var k := located_triangles[s] * 3
		var w := located_weights[s]
		# Each corner, and the side from it to the next round
		var i := corners[k]
		own_diagonal[i] += pull * w.x * w.x
		right[i] += goal * (pull * w.x)
		own_sides[corner_sides[k]] += pull * w.x * w.y
		i = corners[k + 1]
		own_diagonal[i] += pull * w.y * w.y
		right[i] += goal * (pull * w.y)
		own_sides[corner_sides[k + 1]] += pull * w.y * w.z
		i = corners[k + 2]
		own_diagonal[i] += pull * w.z * w.z
		right[i] += goal * (pull * w.z)
		own_sides[corner_sides[k + 2]] += pull * w.z * w.x


func add_diagonal(amount: float) -> void:
	diagonal_extra = amount
	var own_diagonal := diagonal
	for i in own_diagonal.size():
		own_diagonal[i] += amount


## Solves for [param x] (starting from what's there) where the matrix times it is
## [param right], by conjugate gradients scaled by the diagonal, at most [param steps]
## steps, until what's left is [param close] of [param right]
func solve(x: PackedVector2Array, right: PackedVector2Array, steps: int, close: float) -> void:
	if NativeKernels.kernels:
		NativeKernels.solve(self, x, right, steps, close)
		return
	var own_diagonal := diagonal
	var n := own_diagonal.size()
	var residual := times(x)
	var scaled := PackedVector2Array()
	scaled.resize(n)
	var along := Vector2.ZERO
	var size := 1e-12
	for i in n:
		residual[i] = right[i] - residual[i]
		scaled[i] = residual[i] / own_diagonal[i]
		along += residual[i] * scaled[i]
		size += right[i].length_squared()
	var direction := scaled.duplicate()
	var pushed := PackedVector2Array()
	for _step in steps:
		var left := 0.0
		for i in n:
			left += residual[i].length_squared()
		if left <= close * close * size:
			break
		times_into(direction, pushed)
		var curve := Vector2.ZERO
		for i in n:
			curve += direction[i] * pushed[i]
		var step := Vector2(along.x / maxf(curve.x, 1e-30), along.y / maxf(curve.y, 1e-30))
		var next := Vector2.ZERO
		for i in n:
			x[i] += direction[i] * step
			residual[i] -= pushed[i] * step
			scaled[i] = residual[i] / own_diagonal[i]
			next += residual[i] * scaled[i]
		var keep := Vector2(next.x / maxf(along.x, 1e-30), next.y / maxf(along.y, 1e-30))
		for i in n:
			direction[i] = scaled[i] + direction[i] * keep
		along = next


## The matrix times [param values]
func times(values: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	times_into(values, result)
	return result


## Writes the matrix times [param values] into [param result], sized to fit
func times_into(values: PackedVector2Array, result: PackedVector2Array) -> void:
	var own_diagonal := diagonal
	var own_sides := sides
	var from := _from
	var to := _to
	result.resize(values.size())
	for i in values.size():
		result[i] = values[i] * own_diagonal[i]
	for e in own_sides.size():
		var a := from[e]
		var b := to[e]
		var amount := own_sides[e]
		result[a] += values[b] * amount
		result[b] += values[a] * amount
