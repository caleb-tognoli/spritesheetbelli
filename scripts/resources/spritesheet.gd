class_name Spritesheet
extends Resource
## A grid of frames.
##
## Frames are stored at their original size and are only padded to [member sprite_size]
## when drawn or exported. Frame images are never modified in place: every edit replaces
## the image, so state snapshots ([method get_state]) can share them cheaply.
## All changes go through the methods below, which emit [signal updated] once each.

signal updated

enum AddMode {
	FIRST_FREE,  ## Fill the first free, unlocked cell
	APPEND,  ## After the last frame
	NEW_ROW,  ## At the start of a new row below every frame
}

var grid_size: Vector2i:
	get:
		return _grid_size
## Frame images at their original size, by grid coordinate. Read only.
var frames: Dictionary[Vector2i, Image]:
	get:
		return _frames
## Cells that are kept empty when adding frames. Read only.
var locked_coordinates: Array[Vector2i]:
	get:
		return _locked
## Size of every cell: the largest scaled frame
var sprite_size: Vector2i:
	get:
		return _sprite_size
## Scale applied to every frame, without losing quality on repeated resizes
var frame_scale: Vector2:
	get:
		return _scale
var scale_filter: Image.Interpolation:
	get:
		return _scale_filter
## Optional animation names per row
var row_names: Dictionary[int, String]:
	get:
		return _row_names

var _grid_size := Vector2i.ZERO
var _frames: Dictionary[Vector2i, Image] = {}
var _locked: Array[Vector2i] = []
var _scale := Vector2.ONE
var _scale_filter := Image.INTERPOLATE_NEAREST
var _row_names: Dictionary[int, String] = {}
var _sprite_size := Vector2i.ZERO
var _scaled_cache: Dictionary[Image, Image] = {}
var _batch_depth := 0
var _batch_changed := false


func is_empty() -> bool:
	return _frames.is_empty()


func has_frame(coord: Vector2i) -> bool:
	return _frames.has(coord)


func is_locked(coord: Vector2i) -> bool:
	return coord in _locked


func is_inside(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < _grid_size.x and coord.y < _grid_size.y


## Position of a cell when counting left to right, top to bottom
func index_of(coord: Vector2i) -> int:
	return coord.y * _grid_size.x + coord.x


func coord_of(index: int) -> Vector2i:
	if _grid_size.x <= 0:
		return Vector2i(index, 0)
	return Vector2i(index % _grid_size.x, index / _grid_size.x)


## Frame coordinates in reading order
func get_sorted_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	coords.assign(_frames.keys())
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return coords


## The frame image with [member frame_scale] applied, at its own size
func get_frame_image(coord: Vector2i) -> Image:
	var source: Image = _frames.get(coord)
	if source == null:
		return null
	if _scale == Vector2.ONE:
		return source
	if not _scaled_cache.has(source):
		var img := source.duplicate()
		var new_size := _scaled_size(source.get_size())
		img.resize(new_size.x, new_size.y, _scale_filter)
		_scaled_cache[source] = img
	return _scaled_cache[source]


## The scaled frame centred in a transparent cell of [member sprite_size]
func get_cell_image(coord: Vector2i) -> Image:
	var img := get_frame_image(coord)
	if img == null or img.get_size() == _sprite_size:
		return img
	var cell := Image.create_empty(_sprite_size.x, _sprite_size.y, false, Image.FORMAT_RGBA8)
	cell.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), (_sprite_size - img.get_size()) / 2)
	return cell


## Where the scaled frame sits inside its cell
func get_frame_rect_in_cell(coord: Vector2i) -> Rect2i:
	var img := get_frame_image(coord)
	if img == null:
		return Rect2i()
	return Rect2i((_sprite_size - img.get_size()) / 2, img.get_size())


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


func _changed() -> void:
	if _batch_depth > 0:
		_batch_changed = true
	else:
		_notify()


func _notify() -> void:
	_update_sprite_size()
	updated.emit()


#endregion

#region State


## A snapshot of everything, sharing frame images
func get_state() -> Dictionary:
	return {
		"grid_size": _grid_size,
		"frames": _frames.duplicate(),
		"locked": _locked.duplicate(),
		"scale": _scale,
		"scale_filter": _scale_filter,
		"row_names": _row_names.duplicate(),
		"sprite_size": _sprite_size,
	}


func set_state(state: Dictionary) -> void:
	_grid_size = state.get("grid_size", Vector2i.ZERO)
	_frames.assign(state.get("frames", {}))
	_locked.assign(state.get("locked", []))
	_scale = state.get("scale", Vector2.ONE)
	_scale_filter = state.get("scale_filter", Image.INTERPOLATE_NEAREST)
	_row_names.assign(state.get("row_names", {}))
	_sprite_size = state.get("sprite_size", Vector2i.ZERO)
	_scaled_cache.clear()
	_changed()


static func states_equal(a: Dictionary, b: Dictionary) -> bool:
	for key in a:
		if not b.has(key) or typeof(a[key]) != typeof(b[key]) or a[key] != b[key]:
			return false
	return a.size() == b.size()


func clear() -> void:
	set_state({})


#endregion

#region Grid


func set_grid_size(size: Vector2i) -> void:
	size = size.max(Vector2i.ZERO)
	if size.x == 0 or size.y == 0:
		size = Vector2i.ZERO
	if size == _grid_size:
		return
	_grid_size = size

	for coord: Vector2i in _frames.keys():
		if not is_inside(coord):
			_frames.erase(coord)
	_locked.assign(_locked.filter(is_inside))
	for row: int in _row_names.keys():
		if row >= size.y:
			_row_names.erase(row)
	_changed()


## Frames that would be removed by resizing the grid to [param size]
func count_frames_outside(size: Vector2i) -> int:
	var count := 0
	for coord in _frames:
		if coord.x >= size.x or coord.y >= size.y:
			count += 1
	return count


func set_locked(coord: Vector2i, locked: bool) -> void:
	if locked == is_locked(coord) or (locked and (has_frame(coord) or not is_inside(coord))):
		return
	if locked:
		_locked.append(coord)
	else:
		_locked.erase(coord)
	_changed()


## Locks every free cell inside [param rect] (the whole grid by default)
func lock_free_cells(rect := Rect2i()) -> void:
	if rect == Rect2i():
		rect = Rect2i(Vector2i.ZERO, _grid_size)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, _grid_size))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var coord := Vector2i(x, y)
			if not has_frame(coord) and not is_locked(coord):
				_locked.append(coord)
	_changed()


func set_row_name(row: int, row_name: String) -> void:
	row_name = row_name.strip_edges()
	if row_name == _row_names.get(row, ""):
		return
	if row_name.is_empty():
		_row_names.erase(row)
	else:
		_row_names[row] = row_name
	_changed()


#endregion

#region Adding and removing


func get_free_space(mode := AddMode.FIRST_FREE) -> Vector2i:
	if is_empty():
		return get_first_free_unlocked_space()
	if mode == AddMode.NEW_ROW:
		return Vector2i(0, get_first_free_row())
	if mode == AddMode.APPEND:
		return _get_space_after_last_frame()

	var first_free := get_first_free_unlocked_space()
	# Single-row spritesheets grow horizontally instead of wrapping to a new row
	if _grid_size.y == 1 and first_free.y > 0:
		return Vector2i(_grid_size.x, 0)
	return first_free


func _get_space_after_last_frame() -> Vector2i:
	var last_row := get_first_free_row() - 1
	var last_column := 0
	for coord in _frames:
		if coord.y == last_row:
			last_column = maxi(last_column, coord.x)
	if last_column + 1 < _grid_size.x:
		return get_first_free_unlocked_space(Vector2i(last_column + 1, last_row))
	if _grid_size.y == 1:
		return Vector2i(_grid_size.x, 0)
	return get_first_free_unlocked_space(Vector2i(0, last_row + 1))


func get_first_free_unlocked_space(from := Vector2i.ZERO) -> Vector2i:
	while from in _locked or from in _frames:
		if from.x < _grid_size.x - 1:
			from.x += 1
		else:
			from.y += 1
			from.x = 0
	return from


func get_first_free_row() -> int:
	var last_row := -1
	for coord in _frames:
		last_row = maxi(coord.y, last_row)
	return last_row + 1


## Adds [param imgs] to free cells in order and returns where each one went
func add_frames(imgs: Array[Image], mode := AddMode.FIRST_FREE) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	begin_batch()
	var next_new_row := Vector2i(-1, -1)
	for img in imgs:
		if img == null or img.is_empty():
			continue
		var coord: Vector2i
		if mode == AddMode.NEW_ROW:
			if next_new_row.y < 0:
				next_new_row = get_free_space(AddMode.NEW_ROW)
			coord = next_new_row
			next_new_row.x += 1
		else:
			coord = get_free_space(mode)
		set_frame(coord, img)
		coords.append(coord)
	end_batch()
	return coords


## Puts [param img] at [param coord], replacing any frame there and growing the grid if needed
func set_frame(coord: Vector2i, img: Image) -> void:
	if img == null or img.is_empty() or coord.x < 0 or coord.y < 0:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	_locked.erase(coord)
	_grid_size = _grid_size.max(coord + Vector2i.ONE)
	_frames[coord] = img
	_changed()


func remove_frames(coords: Array[Vector2i]) -> void:
	var removed := false
	for coord in coords:
		removed = _frames.erase(coord) or removed
	if removed:
		_changed()


## Moves a frame to another cell. An existing frame there is swapped, or replaced when copying.
func move_frame(from: Vector2i, to: Vector2i, copy := false) -> void:
	if from == to or not has_frame(from) or to.x < 0 or to.y < 0:
		return
	var img: Image = _frames[from]
	var other: Image = _frames.get(to)
	begin_batch()
	if not copy:
		_frames.erase(from)
		if other:
			_frames[from] = other
	set_frame(to, img)
	end_batch()


## Moves several frames by the same offset, swapping with whatever is in the way
func move_frames(coords: Array[Vector2i], offset: Vector2i, copy := false) -> Array[Vector2i]:
	var moving: Dictionary[Vector2i, Image] = {}
	var targets: Array[Vector2i] = []
	for coord in coords:
		if has_frame(coord) and (coord + offset).x >= 0 and (coord + offset).y >= 0:
			moving[coord] = _frames[coord]
			targets.append(coord + offset)
	if moving.is_empty() or offset == Vector2i.ZERO:
		return targets
	begin_batch()
	var displaced: Array[Image] = []
	for target in targets:
		if has_frame(target) and not moving.has(target):
			displaced.append(_frames[target])
	if not copy:
		for coord in moving:
			_frames.erase(coord)
	for coord in moving:
		set_frame(coord + offset, moving[coord])
	# Frames that were in the way go to the cells that were freed
	if not copy:
		var freed: Array[Vector2i] = []
		for coord in moving:
			if not has_frame(coord):
				freed.append(coord)
		for i in mini(displaced.size(), freed.size()):
			_frames[freed[i]] = displaced[i]
	end_batch()
	return targets


## Inserts an empty cell at [param coord], shifting later frames forward in reading order
func insert_empty_cell(coord: Vector2i) -> void:
	if _grid_size.x == 0:
		return
	var start := index_of(coord)
	var shifted: Dictionary[Vector2i, Image] = {}
	for c in _frames:
		var index := index_of(c)
		shifted[coord_of(index + 1) if index >= start else c] = _frames[c]
	_frames = shifted
	_grid_size.y = maxi(_grid_size.y, get_first_free_row())
	_locked.assign(_locked.filter(func(c: Vector2i): return not _frames.has(c)))
	_changed()


## Removes the cell at [param coord] and its frame, shifting later frames back
func remove_cell(coord: Vector2i) -> void:
	var start := index_of(coord)
	var shifted: Dictionary[Vector2i, Image] = {}
	for c in _frames:
		var index := index_of(c)
		if index == start:
			continue
		shifted[coord_of(index - 1) if index > start else c] = _frames[c]
	_frames = shifted
	_changed()


#endregion

#region Editing frames


## Replaces each frame in [param coords] with [code]edit.call(image_copy)[/code]
func edit_frames(coords: Array[Vector2i], edit: Callable) -> void:
	var edited := false
	for coord in coords:
		if not has_frame(coord):
			continue
		var img: Image = _frames[coord].duplicate()
		var result: Variant = edit.call(img)
		if result is Image:
			img = result
		if img != null and not img.is_empty():
			_frames[coord] = img
			edited = true
	if edited:
		_changed()


func flip_frames(coords: Array[Vector2i], horizontal: bool) -> void:
	edit_frames(
		coords,
		func(img: Image):
			if horizontal:
				img.flip_x()
			else:
				img.flip_y()
	)


func rotate_frames(coords: Array[Vector2i], clockwise: bool) -> void:
	edit_frames(
		coords, func(img: Image): img.rotate_90(CLOCKWISE if clockwise else COUNTERCLOCKWISE)
	)


## Crops transparent borders
func trim_frames(coords: Array[Vector2i]) -> void:
	edit_frames(
		coords,
		func(img: Image) -> Image:
			var used := img.get_used_rect()
			if used.size == Vector2i.ZERO or used.size == img.get_size():
				return img
			return img.get_region(used)
	)


## Makes pixels close to [param color] transparent
func color_key_frames(coords: Array[Vector2i], color: Color, tolerance := 0.1) -> void:
	edit_frames(coords, func(img: Image): ImageUtils.color_key(img, color, tolerance))


## Replaces the image of an existing frame
func replace_frame(coord: Vector2i, img: Image) -> void:
	if has_frame(coord):
		set_frame(coord, img)


func set_frame_scale(new_scale: Vector2, filter := _scale_filter) -> void:
	new_scale = new_scale.max(Vector2(0.01, 0.01))
	if new_scale.is_equal_approx(_scale) and filter == _scale_filter:
		return
	_scale = new_scale
	_scale_filter = filter
	_scaled_cache.clear()
	_changed()


## Scales frames so that the cell size becomes [param size]
func resize_sprites(size: Vector2i, filter := _scale_filter) -> void:
	var base := _base_sprite_size()
	if base.x <= 0 or base.y <= 0 or size.x <= 0 or size.y <= 0:
		return
	set_frame_scale(Vector2(size) / Vector2(base), filter)


#endregion

#region Output


## The whole spritesheet as one image
func get_image(options := ExportOptions.new()) -> Image:
	return SpritesheetExporter.build_image(self, options)


#endregion


func _base_sprite_size() -> Vector2i:
	var size := Vector2i.ZERO
	for img in _frames.values():
		size = size.max(img.get_size())
	return size


func _scaled_size(size: Vector2i) -> Vector2i:
	return Vector2i((Vector2(size) * _scale).round()).max(Vector2i.ONE)


func _update_sprite_size() -> void:
	if _frames.is_empty():
		if _grid_size == Vector2i.ZERO:
			_sprite_size = Vector2i.ZERO
		return
	var size := Vector2i.ZERO
	for img in _frames.values():
		size = size.max(_scaled_size(img.get_size()))
	_sprite_size = size
	# Drop cached scaled images of frames that are gone
	var alive := {}
	for img in _frames.values():
		alive[img] = true
	for source in _scaled_cache.keys():
		if not alive.has(source):
			_scaled_cache.erase(source)
