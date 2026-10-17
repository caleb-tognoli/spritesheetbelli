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
	for i in diagonal.size():
		diagonal[i] += other.diagonal[i] * amount
	for e in sides.size():
		sides[e] += other.sides[e] * amount


func add_diagonal(amount: float) -> void:
	diagonal_extra = amount
	for i in diagonal.size():
		diagonal[i] += amount


## Solves for [param x] (starting from what's there) where the matrix times it is
## [param right], by conjugate gradients scaled by the diagonal, at most [param steps]
## steps, until what's left is [param close] of [param right]
func solve(x: PackedVector2Array, right: PackedVector2Array, steps: int, close: float) -> void:
	var n := diagonal.size()
	var residual := times(x)
	var scaled := PackedVector2Array()
	scaled.resize(n)
	var along := Vector2.ZERO
	var size := 1e-12
	for i in n:
		residual[i] = right[i] - residual[i]
		scaled[i] = residual[i] / diagonal[i]
		along += residual[i] * scaled[i]
		size += right[i].length_squared()
	var direction := scaled.duplicate()
	for _step in steps:
		var left := 0.0
		for i in n:
			left += residual[i].length_squared()
		if left <= close * close * size:
			break
		var pushed := times(direction)
		var curve := Vector2.ZERO
		for i in n:
			curve += direction[i] * pushed[i]
		var step := Vector2(along.x / maxf(curve.x, 1e-30), along.y / maxf(curve.y, 1e-30))
		var next := Vector2.ZERO
		for i in n:
			x[i] += direction[i] * step
			residual[i] -= pushed[i] * step
			scaled[i] = residual[i] / diagonal[i]
			next += residual[i] * scaled[i]
		var keep := Vector2(next.x / maxf(along.x, 1e-30), next.y / maxf(along.y, 1e-30))
		for i in n:
			direction[i] = scaled[i] + direction[i] * keep
		along = next


## The matrix times [param values]
func times(values: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(values.size())
	for i in values.size():
		result[i] = values[i] * diagonal[i]
	for e in sides.size():
		var a := _from[e]
		var b := _to[e]
		result[a] += values[b] * sides[e]
		result[b] += values[a] * sides[e]
	return result
