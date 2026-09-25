class_name Spritesheet
extends Resource
## A grid of frames.
##
## Frames are stored at their original size and are only padded to [member sprite_size]
## when drawn or exported. Every frame is placed around the same point of its cell: centred
## on it, or at an origin of its own (see [method get_frame_origin]), so the frames of an
## animation stay aligned when some are trimmed or nudged.
## Frame images are never modified in place: every edit replaces
## the image, so state snapshots ([method get_state]) can share them cheaply.
## All changes go through the methods below, which emit [signal updated] once each.

signal updated

const NO_CELL := Vector2i(-1, -1)

enum AddMode {
	FIRST_FREE,  ## Fill the first free, unlocked cell
	APPEND,  ## After the last frame
	NEW_ROW,  ## At the start of a new row below every frame
}
## How [method align_frames] lines frames up
enum Alignment { CENTER, BOTTOM, TOP, LEFT, RIGHT }

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
## Named animations, in the order they were made. Read only: changes go through
## [method add_animation], [method set_animation] and [method remove_animation].
var animations: Array[SheetAnimation]:
	get:
		var result: Array[SheetAnimation] = []
		for data in _animations:
			result.append(SheetAnimation.from_dictionary(data))
		return result
## How this sheet is exported, see [ExportOptions]. Read only.
var export_settings: Dictionary:
	get:
		return _export_settings

var _grid_size := Vector2i.ZERO
var _frames: Dictionary[Vector2i, Image] = {}
var _locked: Array[Vector2i] = []
var _scale := Vector2.ONE
var _scale_filter := Image.INTERPOLATE_NEAREST
var _row_names: Dictionary[int, String] = {}
var _export_settings := {}
var _animations: Array[Dictionary] = []
## Unscaled origins of frames that aren't centred, see [method get_frame_origin]
var _origins: Dictionary[Vector2i, Vector2i] = {}
var _sprite_size := Vector2i.ZERO
## The top-left of every cell, relative to the point frames are placed around
var _cell_origin := Vector2i.ZERO
## Scaled frames by scale and filter. The previous scale is kept too, so undoing a resize
## doesn't scale everything again.
var _scaled_caches: Dictionary[Vector3, Dictionary] = {}
var _preparing := 0
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
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return coords


## The frame image with [member frame_scale] applied, at its own size
func get_frame_image(coord: Vector2i) -> Image:
	var source: Image = _frames.get(coord)
	if source == null:
		return null
	if _scale == Vector2.ONE:
		return source
	var cache := _scaled_cache()
	if not cache.has(source):
		var img := source.duplicate()
		var new_size := _scaled_size(source.get_size())
		img.resize(new_size.x, new_size.y, _scale_filter)
		cache[source] = img
	return cache[source]


## Whether the frame at [param coord] is already scaled, so getting it is quick
func is_frame_scaled(coord: Vector2i) -> bool:
	return _scale == Vector2.ONE or not _frames.has(coord) or _scaled_cache().has(_frames[coord])


## Every scaled image kept for reuse, as a set
func get_cached_scaled_images() -> Dictionary:
	var images := {}
	for cache: Dictionary in _scaled_caches.values():
		for img: Image in cache.values():
			images[img] = true
	return images


## Whether [method prepare_scaled_images] is running
func is_preparing_scaled_images() -> bool:
	return _preparing > 0


## Roughly how many pixels still have to be scaled, to tell if it will take a while
func get_pending_scale_work() -> int:
	if _scale == Vector2.ONE:
		return 0
	var cache := _scaled_cache()
	var work := 0
	for source: Image in _frames.values():
		if not cache.has(source):
			var scaled := _scaled_size(source.get_size())
			work += scaled.x * scaled.y + source.get_width() * source.get_height()
	return work


## Scales every frame that isn't scaled yet, on worker threads. If the scale changes in
## the meantime, the results are dropped.
func prepare_scaled_images(on_progress := Callable()) -> void:
	if _scale == Vector2.ONE:
		return
	var key := _cache_key()
	var cache := _scaled_cache()
	var sources: Array[Image] = []
	var sizes: Array[Vector2i] = []
	for source: Image in _frames.values():
		if not cache.has(source) and source not in sources:
			sources.append(source)
			sizes.append(_scaled_size(source.get_size()))
	var filter := _scale_filter
	_preparing += 1
	var results := await Parallel.map(
		sources.size(),
		func(i: int) -> Image:
			var img := sources[i].duplicate() as Image
			img.resize(sizes[i].x, sizes[i].y, filter)
			return img,
		on_progress
	)
	_preparing -= 1
	if _cache_key() != key:
		return
	cache = _scaled_cache()
	for i in sources.size():
		if not cache.has(sources[i]):
			cache[sources[i]] = results[i]


## The scaled frame in a transparent cell of [member sprite_size]
func get_cell_image(coord: Vector2i) -> Image:
	var img := get_frame_image(coord)
	if img == null or img.get_size() == _sprite_size:
		return img
	var cell := Image.create_empty(_sprite_size.x, _sprite_size.y, false, Image.FORMAT_RGBA8)
	var position := get_frame_rect_in_cell(coord).position
	cell.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), position)
	return cell


## Where the scaled frame sits inside its cell
func get_frame_rect_in_cell(coord: Vector2i) -> Rect2i:
	if not _frames.has(coord):
		return Rect2i()
	var rect := _placed_rect(coord, _scale)
	return Rect2i(rect.position - _cell_origin, rect.size)


## Where the top-left corner of the frame is, in unscaled pixels, relative to the point
## every frame is placed around. Frames without an origin of their own are centred on it.
func get_frame_origin(coord: Vector2i) -> Vector2i:
	if _origins.has(coord):
		return _origins[coord]
	var source: Image = _frames.get(coord)
	return -_half_up(source.get_size()) if source else Vector2i.ZERO


## Whether the frame has been moved away from the centre of its cell
func has_frame_origin(coord: Vector2i) -> bool:
	return _origins.has(coord)


## Origins of frames that aren't centred. Read only.
func get_frame_origins() -> Dictionary[Vector2i, Vector2i]:
	return _origins


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
		"animations": _animations.duplicate(true),
		"export": _export_settings.duplicate(),
		"origins": _origins.duplicate(),
		"sprite_size": _sprite_size,
		"cell_origin": _cell_origin,
	}


func set_state(state: Dictionary) -> void:
	_grid_size = state.get("grid_size", Vector2i.ZERO)
	_frames.assign(state.get("frames", {}))
	_locked.assign(state.get("locked", []))
	_scale = state.get("scale", Vector2.ONE)
	_scale_filter = state.get("scale_filter", Image.INTERPOLATE_NEAREST)
	_row_names.assign(state.get("row_names", {}))
	_animations.assign(state.get("animations", []).duplicate(true))
	_export_settings = state.get("export", {}).duplicate()
	_origins.assign(state.get("origins", {}))
	_sprite_size = state.get("sprite_size", Vector2i.ZERO)
	_cell_origin = state.get("cell_origin", Vector2i.ZERO)
	_changed()


static func states_equal(a: Dictionary, b: Dictionary) -> bool:
	for key: String in a:
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
			_origins.erase(coord)
	_locked.assign(_locked.filter(is_inside))
	for row: int in _row_names.keys():
		if row >= size.y:
			_row_names.erase(row)
	_remap_animation_cells(
		func(cell: Vector2i) -> Vector2i: return cell if is_inside(cell) else NO_CELL
	)
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


func set_export_settings(settings: Dictionary) -> void:
	if settings == _export_settings:
		return
	_export_settings = settings.duplicate()
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
		var name := img.resource_name
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resource_name = name
	_locked.erase(coord)
	_grid_size = _grid_size.max(coord + Vector2i.ONE)
	_frames[coord] = img
	_origins.erase(coord)
	_changed()


func remove_frames(coords: Array[Vector2i]) -> void:
	var removed := false
	for coord in coords:
		removed = _frames.erase(coord) or removed
		_origins.erase(coord)
	if removed:
		_changed()


## Moves a frame to another cell. An existing frame there is swapped, or replaced when copying.
func move_frame(from: Vector2i, to: Vector2i, copy := false) -> void:
	if from == to or not has_frame(from) or to.x < 0 or to.y < 0:
		return
	var img: Image = _frames[from]
	var other: Image = _frames.get(to)
	var origins := _origins.duplicate()
	begin_batch()
	if not copy:
		_frames.erase(from)
		_origins.erase(from)
		if other:
			_frames[from] = other
			_set_origin(from, origins.get(to))
	set_frame(to, img)
	_set_origin(to, origins.get(from))
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
	var origins := _origins.duplicate()
	var displaced: Array[Image] = []
	var displaced_cells: Array[Vector2i] = []
	for target in targets:
		if has_frame(target) and not moving.has(target):
			displaced.append(_frames[target])
			displaced_cells.append(target)
	if not copy:
		for coord in moving:
			_frames.erase(coord)
			_origins.erase(coord)
	for coord in moving:
		set_frame(coord + offset, moving[coord])
		_set_origin(coord + offset, origins.get(coord))
	# Frames that were in the way go to the cells that were freed
	if not copy:
		var freed: Array[Vector2i] = []
		for coord in moving:
			if not has_frame(coord):
				freed.append(coord)
		for i in mini(displaced.size(), freed.size()):
			_frames[freed[i]] = displaced[i]
			_set_origin(freed[i], origins.get(displaced_cells[i]))
		# Animations follow their frames
		var moved := {}
		for coord in moving:
			moved[coord] = coord + offset
		for i in mini(displaced_cells.size(), freed.size()):
			moved[displaced_cells[i]] = freed[i]
		_remap_animation_cells(func(cell: Vector2i) -> Vector2i: return moved.get(cell, cell))
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
	var shifted_origins: Dictionary[Vector2i, Vector2i] = {}
	for c in _origins:
		shifted_origins[coord_of(index_of(c) + 1) if index_of(c) >= start else c] = _origins[c]
	_origins = shifted_origins
	_remap_animation_cells(
		func(cell: Vector2i) -> Vector2i:
			return coord_of(index_of(cell) + 1) if index_of(cell) >= start else cell
	)
	_grid_size.y = maxi(_grid_size.y, get_first_free_row())
	_locked.assign(_locked.filter(func(c: Vector2i) -> bool: return not _frames.has(c)))
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
	var shifted_origins: Dictionary[Vector2i, Vector2i] = {}
	for c in _origins:
		var index := index_of(c)
		if index != start:
			shifted_origins[coord_of(index - 1) if index > start else c] = _origins[c]
	_origins = shifted_origins
	_remap_animation_cells(
		func(cell: Vector2i) -> Vector2i:
			var index := index_of(cell)
			if index == start:
				return NO_CELL
			return coord_of(index - 1) if index > start else cell
	)
	_changed()


#endregion

#region Animations


## Adds an animation and returns its index
func add_animation(animation: SheetAnimation) -> int:
	_animations.append(animation.to_dictionary())
	_changed()
	return _animations.size() - 1


func set_animation(index: int, animation: SheetAnimation) -> void:
	if index < 0 or index >= _animations.size():
		return
	var data := animation.to_dictionary()
	if data == _animations[index]:
		return
	_animations[index] = data
	_changed()


func remove_animation(index: int) -> void:
	if index < 0 or index >= _animations.size():
		return
	_animations.remove_at(index)
	_changed()


## A name not used by any animation, based on [param base]
func get_unique_animation_name(base := "animation") -> String:
	var used := {}
	for data in _animations:
		used[data.name] = true
	if not used.has(base):
		return base
	var number := 2
	while used.has("%s%d" % [base, number]):
		number += 1
	return "%s%d" % [base, number]


## Changes the cells of every animation with [param map], which returns a new cell or
## NO_CELL to drop it
func _remap_animation_cells(map: Callable) -> void:
	for data in _animations:
		var cells: Array[Vector2i] = []
		for cell: Vector2i in data.cells:
			var mapped: Vector2i = map.call(cell)
			if mapped != NO_CELL:
				cells.append(mapped)
		data.cells = cells


#endregion

#region Editing frames


## Replaces each frame in [param coords] with [code]edit.call(image_copy)[/code].
## [param move] gives frames that aren't centred a new origin: it's called with the old
## origin, the old size and the new image. With [param move_centred], centred frames are
## moved too and get an origin of their own.
func edit_frames(
	coords: Array[Vector2i], edit: Callable, move := Callable(), move_centred := false
) -> void:
	var edited := false
	for coord in coords:
		if not has_frame(coord):
			continue
		var old: Image = _frames[coord]
		var img: Image = old.duplicate()
		var result: Variant = edit.call(img)
		if result is Image:
			img = result
		if img != null and not img.is_empty():
			# duplicate() doesn't copy the name
			img.resource_name = old.resource_name
			if move.is_valid() and (move_centred or _origins.has(coord)):
				var origin: Vector2i = move.call(get_frame_origin(coord), old.get_size(), img)
				_origins[coord] = origin
			_frames[coord] = img
			edited = true
	if edited:
		_changed()


## Mirrors frames, and where they are in their cells
func flip_frames(coords: Array[Vector2i], horizontal: bool) -> void:
	edit_frames(
		coords,
		func(img: Image) -> void:
			if horizontal:
				img.flip_x()
			else:
				img.flip_y(),
		func(origin: Vector2i, size: Vector2i, _img: Image) -> Vector2i:
			if horizontal:
				return Vector2i(-origin.x - size.x, origin.y)
			return Vector2i(origin.x, -origin.y - size.y)
	)


## Turns frames, and where they are in their cells
func rotate_frames(coords: Array[Vector2i], clockwise: bool) -> void:
	edit_frames(
		coords,
		func(img: Image) -> void: img.rotate_90(CLOCKWISE if clockwise else COUNTERCLOCKWISE),
		func(origin: Vector2i, size: Vector2i, _img: Image) -> Vector2i:
			if clockwise:
				return Vector2i(-origin.y - size.y, origin.x)
			return Vector2i(origin.y, -origin.x - size.x)
	)


## Crops transparent borders. The pixels that are left stay where they were in the cell,
## so trimming every frame of an animation shrinks the cells without making it jump.
func trim_frames(coords: Array[Vector2i]) -> void:
	var cropped_at := {}
	edit_frames(
		coords,
		func(img: Image) -> Image:
			var used := img.get_used_rect()
			if used.size == Vector2i.ZERO or used.size == img.get_size():
				return img
			var trimmed := img.get_region(used)
			cropped_at[trimmed] = used.position
			return trimmed,
		func(origin: Vector2i, _size: Vector2i, img: Image) -> Vector2i:
			return origin + cropped_at.get(img, Vector2i.ZERO),
		true
	)


## Places the frame at [param coord] at [param origin], see [method get_frame_origin]
func set_frame_origin(coord: Vector2i, origin: Vector2i) -> void:
	if has_frame(coord) and _origins.get(coord) != origin:
		_origins[coord] = origin
		_changed()


## Moves frames inside their cells by [param offset] unscaled pixels
func nudge_frames(coords: Array[Vector2i], offset: Vector2i) -> void:
	if offset == Vector2i.ZERO:
		return
	var moved := false
	for coord in coords:
		if has_frame(coord):
			_origins[coord] = get_frame_origin(coord) + offset
			moved = true
	if moved:
		_changed()


## Lines frames up inside their cells. [constant Alignment.CENTER] centres them again;
## the other alignments put that edge of every frame on one line and centre the other way.
func align_frames(coords: Array[Vector2i], alignment: Alignment) -> void:
	var changed := false
	for coord in coords:
		if not has_frame(coord):
			continue
		if alignment == Alignment.CENTER:
			changed = _origins.erase(coord) or changed
			continue
		var size := _frames[coord].get_size()
		var origin := -_half_up(size)
		match alignment:
			Alignment.BOTTOM:
				origin.y = -size.y
			Alignment.TOP:
				origin.y = 0
			Alignment.LEFT:
				origin.x = 0
			Alignment.RIGHT:
				origin.x = -size.x
		if _origins.get(coord) != origin:
			_origins[coord] = origin
			changed = true
	if changed:
		_changed()


## Makes pixels close to [param color] transparent
func color_key_frames(coords: Array[Vector2i], color: Color, tolerance := 0.1) -> void:
	edit_frames(coords, func(img: Image) -> void: ImageUtils.color_key(img, color, tolerance))


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
	_changed()


## Scales frames so that the cell size becomes [param size]
func resize_sprites(size: Vector2i, filter := _scale_filter) -> void:
	var base := get_base_sprite_size()
	if base.x <= 0 or base.y <= 0 or size.x <= 0 or size.y <= 0:
		return
	set_frame_scale(Vector2(size) / Vector2(base), filter)


#endregion

#region Output


## The whole spritesheet as one image
func get_image(options := ExportOptions.new()) -> Image:
	return SpritesheetExporter.build_image(self, options)


#endregion


## The cell size without [member frame_scale]
func get_base_sprite_size() -> Vector2i:
	return _frame_bounds(Vector2.ONE).size


func _cache_key() -> Vector3:
	return Vector3(_scale.x, _scale.y, _scale_filter)


func _scaled_cache() -> Dictionary:
	var key := _cache_key()
	if _scaled_caches.has(key):
		# Most recently used last
		var cache: Dictionary = _scaled_caches[key]
		_scaled_caches.erase(key)
		_scaled_caches[key] = cache
		return cache
	_scaled_caches[key] = {}
	while _scaled_caches.size() > 2:
		_scaled_caches.erase(_scaled_caches.keys()[0])
	return _scaled_caches[key]


func _scaled_size(size: Vector2i) -> Vector2i:
	return Vector2i((Vector2(size) * _scale).round()).max(Vector2i.ONE)


## Half of [param size], rounded up: centring leaves the odd pixel on the right and bottom
static func _half_up(size: Vector2i) -> Vector2i:
	return (size + Vector2i.ONE) / 2


## The frame at [param frame_scale], relative to the point every frame is placed around
func _placed_rect(coord: Vector2i, frame_scale: Vector2) -> Rect2i:
	var size := _frames[coord].get_size()
	if frame_scale != Vector2.ONE:
		size = Vector2i((Vector2(size) * frame_scale).round()).max(Vector2i.ONE)
	if not _origins.has(coord):
		return Rect2i(-_half_up(size), size)
	return Rect2i(Vector2i((Vector2(_origins[coord]) * frame_scale).round()), size)


## The smallest rectangle holding every frame at [param frame_scale], placed around the
## same point
func _frame_bounds(frame_scale: Vector2) -> Rect2i:
	var bounds := Rect2i()
	for coord in _frames:
		var rect := _placed_rect(coord, frame_scale)
		bounds = rect if bounds.size == Vector2i.ZERO else bounds.merge(rect)
	return bounds


## Sets or clears ([code]null[/code]) the origin of the frame at [param coord]
func _set_origin(coord: Vector2i, origin: Variant) -> void:
	if origin is Vector2i:
		_origins[coord] = origin
	else:
		_origins.erase(coord)


## The cells are the smallest rectangle that holds every frame around the same point
func _update_sprite_size() -> void:
	if _frames.is_empty():
		if _grid_size == Vector2i.ZERO:
			_sprite_size = Vector2i.ZERO
			_cell_origin = Vector2i.ZERO
		return
	var bounds := _frame_bounds(_scale)
	_sprite_size = bounds.size
	_cell_origin = bounds.position
	# Drop cached scaled images of frames that are gone
	var alive := {}
	for img: Image in _frames.values():
		alive[img] = true
	for cache: Dictionary in _scaled_caches.values():
		for source: Image in cache.keys():
			if not alive.has(source):
				cache.erase(source)
