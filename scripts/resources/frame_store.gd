class_name FrameStore
extends Resource
## The frames of a [Spritesheet] by grid coordinate, with what each cell holds besides its
## frame: an origin, a link to a file, a pivot and a place in the packed layout. Everything
## a cell holds moves along with its frame. Changes are batched into one
## [signal updated] each; [Spritesheet] has everything else.

signal updated

const NO_CELL := Vector2i(-1, -1)
## What a cell can hold besides its frame, see [method get_cell_data]
const CELL_DATA_KEYS: Array[String] = ["origin", "source", "pivot", "placement"]

## Frame images at their original size, by grid coordinate. Read only.
var frames: Dictionary[Vector2i, Image]:
	get:
		return _frames
## Where linked frames came from, by grid coordinate, see [FrameSource]. Read only:
## frames are linked with [method Spritesheet.set_frame].
var frame_sources: Dictionary[Vector2i, Dictionary]:
	get:
		return _sources
## Where frames are in the packed layout, by grid coordinate, see [PackedLayout]. Read only.
var placements: Dictionary[Vector2i, Dictionary]:
	get:
		return _placements
## The frames with the sheet's scale applied, kept for reuse
var scaled_frames: ScaledFrames
## What packing found out about the frames, kept for reuse
var pack_cache := PackedLayout.Cache.new()

var _frames: Dictionary[Vector2i, Image] = {}
## Unscaled origins of frames that aren't centred, see [method Spritesheet.get_frame_origin]
var _origins: Dictionary[Vector2i, Vector2i] = {}
## Where linked frames came from, see [FrameSource]. Never changed in place, only replaced.
var _sources: Dictionary[Vector2i, Dictionary] = {}
## Pivots of frames that have one, in unscaled pixels from the frame's top-left corner
var _pivots: Dictionary[Vector2i, Vector2] = {}
## Where frames are in the packed layout. Never changed in place, only replaced.
var _placements: Dictionary[Vector2i, Dictionary] = {}
## Whether frames may need packing again
var _layout_dirty := false
var _batch_depth := 0
var _batch_changed := false


func _init() -> void:
	scaled_frames = ScaledFrames.new(self)


func is_empty() -> bool:
	return _frames.is_empty()


func has_frame(coord: Vector2i) -> bool:
	return _frames.has(coord)


## The frame image with [member frame_scale] applied, at its own size
func get_frame_image(coord: Vector2i) -> Image:
	return scaled_frames.get_image(coord)


## Whether the frame has a pivot of its own
func has_pivot(coord: Vector2i) -> bool:
	return _pivots.has(coord)


## The frame's pivot in unscaled pixels from its top-left corner: its own, or its centre
func get_pivot(coord: Vector2i) -> Vector2:
	if _pivots.has(coord):
		return _pivots[coord]
	var source: Image = _frames.get(coord)
	return Vector2(source.get_size()) / 2.0 if source else Vector2.ZERO


## Everything a cell holds: [code]{"image": Image}[/code], plus "origin", "source",
## "pivot" and "placement" when it has them. Empty for a cell without a frame.
func get_cell_data(coord: Vector2i) -> Dictionary:
	if not _frames.has(coord):
		return {}
	var data := {"image": _frames[coord]}
	var values := _cell_dicts()
	for i in CELL_DATA_KEYS.size():
		if values[i].has(coord):
			data[CELL_DATA_KEYS[i]] = values[i][coord]
	return data


## Gives frames a pivot in unscaled pixels from their top-left corners, or takes it away
## for [code]null[/code]
func set_pivots(coords: Array[Vector2i], pivot: Variant) -> void:
	var changed := false
	for coord in coords:
		if has_frame(coord) and _pivots.get(coord) != pivot:
			_set_or_erase(_pivots, coord, pivot)
			changed = true
	if changed:
		_changed()


## Renames a frame. Frames can share an image, so the frame gets a copy with the new name.
func rename_frame(coord: Vector2i, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if not has_frame(coord) or _frames[coord].resource_name == new_name:
		return
	var old: Image = _frames[coord]
	var img: Image = old.duplicate()
	img.resource_name = new_name
	scaled_frames.alias(old, img)
	_frames[coord] = img
	_changed()


## Changes where frames are in the packed layout without packing the rest again: each
## coordinate in [param changes] gets its place (see [PackedLayout]), or none for null
func set_placements(changes: Dictionary) -> void:
	var changed := false
	for coord: Vector2i in changes:
		if has_frame(coord) and _placements.get(coord) != changes[coord]:
			_set_or_erase(_placements, coord, changes[coord])
			changed = true
	if changed:
		_changed(false)


#region Batching


## Groups several changes into a single [signal updated]
func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _batch_changed:
		_batch_changed = false
		_notify()


## Runs [param callable] as a single change
func batch(callable: Callable) -> Variant:
	begin_batch()
	var result: Variant = callable.call()
	end_batch()
	return result


## Call after every change. Changes that don't [param affect_layout] don't pack frames again.
func _changed(affect_layout := true) -> void:
	_layout_dirty = _layout_dirty or affect_layout
	if _batch_depth > 0:
		_batch_changed = true
	else:
		_notify()


## Tells about the changes
func _notify() -> void:
	_layout_dirty = false
	updated.emit()


#endregion


## Sets [param key] to [param value], or erases it for [code]null[/code]
static func _set_or_erase(dictionary: Dictionary, key: Variant, value: Variant) -> void:
	if value == null:
		dictionary.erase(key)
	else:
		dictionary[key] = value


## What cells hold besides their frames, in the order of [constant CELL_DATA_KEYS]
func _cell_dicts() -> Array[Dictionary]:
	return [_origins, _sources, _pivots, _placements]


## Clears what a cell holds besides its frame
func _erase_cell_data(coord: Vector2i) -> void:
	for values in _cell_dicts():
		values.erase(coord)


## A copy of what every cell holds besides its frame, for [method _restore_cell_data]
func _save_cell_data() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	for values in _cell_dicts():
		saved.append(values.duplicate())
	return saved


## Gives [param coord] what [param from] held in [param saved]
func _restore_cell_data(coord: Vector2i, saved: Array[Dictionary], from: Vector2i) -> void:
	var targets := _cell_dicts()
	for i in targets.size():
		_set_or_erase(targets[i], coord, saved[i].get(from))


## Moves what each cell holds to the cell [param map] returns, or drops it for NO_CELL
func _remap_cell_data(map: Callable) -> void:
	var saved := _save_cell_data()
	var targets := _cell_dicts()
	for i in targets.size():
		targets[i].clear()
		for cell: Vector2i in saved[i]:
			var moved: Vector2i = map.call(cell)
			if moved != NO_CELL:
				targets[i][moved] = saved[i][cell]
