class_name Spritesheet
extends FrameStore
## A grid of frames.
##
## Frames are stored at their original size and are only padded to [member sprite_size]
## when drawn or exported. Every frame is placed around the same point of its cell: centred
## on it, or at an origin of its own (see [method get_frame_origin]), so the frames of an
## animation stay aligned when some are trimmed or nudged.
## Frame images are never modified in place: every edit replaces
## the image, so state snapshots ([method get_state]) can share them cheaply.
## All changes go through the methods below, which emit [signal updated] once each.
## Frames can be linked to the files they came from, see [FrameSource].
## Besides the grid, frames can be laid out packed tightly, see [PackedLayout].
## Frames and what their cells hold are stored by [FrameStore].

## Packing had to do something the user should know about, like moving a pinned frame
signal layout_warning(message: String)

enum AddMode {
	FIRST_FREE,  ## Fill the first free, unlocked cell
	APPEND,  ## After the last frame
	NEW_ROW,  ## At the start of a new row below every frame
}
## How [method FrameEdits.align] lines frames up
enum Alignment { CENTER, BOTTOM, TOP, LEFT, RIGHT }
## How frames are laid out: in the cells of the grid, or packed tightly on pages
enum Layout { GRID, PACKED }

var grid_size: Vector2i:
	get:
		return _grid_size
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
var layout: Layout:
	get:
		return _layout
## How frames are packed, a copy. Changes go through [method set_atlas_settings].
var atlas_settings: AtlasSettings:
	get:
		return AtlasSettings.from_dictionary(_atlas)

var _grid_size := Vector2i.ZERO
var _locked: Array[Vector2i] = []
var _scale := Vector2.ONE
var _scale_filter := Image.INTERPOLATE_NEAREST
var _row_names: Dictionary[int, String] = {}
var _export_settings := {}
var _animations: Array[Dictionary] = []
var _sprite_size := Vector2i.ZERO
## The top-left of every cell, relative to the point frames are placed around
var _cell_origin := Vector2i.ZERO
var _layout := Layout.GRID
## The values of [AtlasSettings] that aren't the defaults
var _atlas := {}


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


## Puts a frame with everything it holds (see [method get_cell_data]) at [param coord]
func set_cell(coord: Vector2i, data: Dictionary) -> void:
	var img: Image = data.get("image")
	if img == null or img.is_empty() or coord.x < 0 or coord.y < 0:
		return
	begin_batch()
	set_frame(coord, img, data.get("source", {}), data.get("origin"))
	_set_or_erase(_pivots, coord, data.get("pivot"))
	_set_or_erase(_placements, coord, data.get("placement"))
	end_batch()


## Adds frames with what they hold (see [method get_cell_data]) to free cells in order,
## like [method add_frames], and returns where each one went
func add_cells(cells: Array[Dictionary], mode := AddMode.FIRST_FREE) -> Array[Vector2i]:
	var images: Array[Image] = []
	for data in cells:
		images.append(data.get("image"))
	begin_batch()
	var coords := add_frames(images, mode)
	var i := 0
	for data in cells:
		var img: Image = data.get("image")
		if img != null and not img.is_empty():
			set_cell(coords[i], data)
			i += 1
	end_batch()
	return coords


#region Batching


## Tells about the changes, packing frames again first in the packed layout
func _notify() -> void:
	_update_sprite_size()
	if _layout == Layout.PACKED and _layout_dirty:
		var arranged := PackedLayout.arrange(self)
		if arranged:
			_placements.assign(arranged.placements)
			for message: String in arranged.warnings:
				layout_warning.emit(message)
	super()


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
		"sources": _sources.duplicate(),
		"pivots": _pivots.duplicate(),
		"placements": _placements.duplicate(),
		"layout": _layout,
		"atlas": _atlas.duplicate(),
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
	_sources.assign(state.get("sources", {}))
	_pivots.assign(state.get("pivots", {}))
	_placements.assign(state.get("placements", {}))
	_layout = state.get("layout", Layout.GRID)
	_atlas = state.get("atlas", {}).duplicate()
	_sprite_size = state.get("sprite_size", Vector2i.ZERO)
	_cell_origin = state.get("cell_origin", Vector2i.ZERO)
	# The places come with the state, so frames aren't packed again
	_layout_dirty = false
	pack_cache.signature = 0
	_changed(false)


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
			_erase_cell_data(coord)
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


## Adds [param imgs] to free cells in order and returns where each one went. Each image
## can come with the [FrameSource] it was loaded from, at the same index in [param sources].
func add_frames(
	imgs: Array[Image], mode := AddMode.FIRST_FREE, sources: Array[Dictionary] = []
) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	begin_batch()
	var next_new_row := Vector2i(-1, -1)
	for i in imgs.size():
		var img := imgs[i]
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
		set_frame(coord, img, sources[i] if i < sources.size() else {})
		coords.append(coord)
	end_batch()
	return coords


## Puts [param img] at [param coord], replacing any frame there and growing the grid if
## needed, at [param origin] (centred for null) and linked to [param source]
func set_frame(coord: Vector2i, img: Image, source := {}, origin: Variant = null) -> void:
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
	_set_or_erase(_origins, coord, origin)
	if source:
		_sources[coord] = source
	else:
		_sources.erase(coord)
	_changed()


func remove_frames(coords: Array[Vector2i]) -> void:
	var removed := false
	for coord in coords:
		removed = _frames.erase(coord) or removed
		_erase_cell_data(coord)
	if removed:
		_changed()


## Moves a frame to another cell. An existing frame there is swapped, or replaced when copying.
func move_frame(from: Vector2i, to: Vector2i, copy := false) -> void:
	if from == to or not has_frame(from) or to.x < 0 or to.y < 0:
		return
	var img: Image = _frames[from]
	var other: Image = _frames.get(to)
	var saved := _save_cell_data()
	begin_batch()
	if not copy:
		_frames.erase(from)
		_erase_cell_data(from)
		if other:
			_frames[from] = other
			_restore_cell_data(from, saved, to)
	set_frame(to, img)
	_restore_cell_data(to, saved, from)
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
	var saved := _save_cell_data()
	var displaced: Array[Image] = []
	var displaced_cells: Array[Vector2i] = []
	for target in targets:
		if has_frame(target) and not moving.has(target):
			displaced.append(_frames[target])
			displaced_cells.append(target)
	if not copy:
		for coord in moving:
			_frames.erase(coord)
			_erase_cell_data(coord)
	for coord in moving:
		set_frame(coord + offset, moving[coord])
		_restore_cell_data(coord + offset, saved, coord)
	# Frames that were in the way go to the cells that were freed
	if not copy:
		var freed: Array[Vector2i] = []
		for coord in moving:
			if not has_frame(coord):
				freed.append(coord)
		for i in mini(displaced.size(), freed.size()):
			_frames[freed[i]] = displaced[i]
			_restore_cell_data(freed[i], saved, displaced_cells[i])
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
	_remap_cells(
		func(cell: Vector2i) -> Vector2i:
			return coord_of(index_of(cell) + 1) if index_of(cell) >= start else cell
	)
	_grid_size.y = maxi(_grid_size.y, get_first_free_row())
	_locked.assign(_locked.filter(func(c: Vector2i) -> bool: return not _frames.has(c)))
	_changed()


## Removes the cell at [param coord] and its frame, shifting later frames back
func remove_cell(coord: Vector2i) -> void:
	var start := index_of(coord)
	_remap_cells(
		func(cell: Vector2i) -> Vector2i:
			var index := index_of(cell)
			if index == start:
				return NO_CELL
			return coord_of(index - 1) if index > start else cell
	)
	_changed()


## Inserts an empty row at [param row], moving it and the rows below down
func insert_row(row: int) -> void:
	if row < 0 or row > _grid_size.y or _grid_size.x == 0:
		return
	_move_rows(func(y: int) -> int: return y + 1 if y >= row else y)
	_grid_size.y += 1
	_changed()


## Removes [param row] with its frames, moving the rows below up
func remove_row(row: int) -> void:
	if row < 0 or row >= _grid_size.y:
		return
	_move_rows(
		func(y: int) -> int:
			if y == row:
				return -1
			return y - 1 if y > row else y
	)
	_grid_size.y -= 1
	if _grid_size.y == 0:
		_grid_size = Vector2i.ZERO
	_changed()


## Swaps [param row] with the row [param by] rows away, inside the grid
func move_row(row: int, by: int) -> void:
	var target := row + by
	if by == 0 or row < 0 or row >= _grid_size.y or target < 0 or target >= _grid_size.y:
		return
	_move_rows(
		func(y: int) -> int:
			if y == row:
				return target
			return row if y == target else y
	)
	_changed()


## Moves everything in each row to the row [param map] returns for it, or drops it for -1
func _move_rows(map: Callable) -> void:
	var cell_map := func(cell: Vector2i) -> Vector2i:
		var y: int = map.call(cell.y)
		return NO_CELL if y < 0 else Vector2i(cell.x, y)
	_remap_cells(cell_map)
	var locked: Array[Vector2i] = []
	for cell in _locked:
		var moved: Vector2i = cell_map.call(cell)
		if moved != NO_CELL:
			locked.append(moved)
	_locked = locked
	var moved_names: Dictionary[int, String] = {}
	for row in _row_names:
		var moved: int = map.call(row)
		if moved >= 0:
			moved_names[moved] = _row_names[row]
	_row_names = moved_names


## Moves every frame, with what its cell holds and the animations showing it, to the cell
## [param map] returns for it, or drops it for NO_CELL
func _remap_cells(map: Callable) -> void:
	var moved_frames: Dictionary[Vector2i, Image] = {}
	for cell in _frames:
		var moved: Vector2i = map.call(cell)
		if moved != NO_CELL:
			moved_frames[moved] = _frames[cell]
	_frames = moved_frames
	_remap_cell_data(map)
	_remap_animation_cells(map)


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
		var durations: Array[float] = []
		var old_durations: Array = data.get("durations", [])
		for i: int in data.cells.size():
			var mapped: Vector2i = map.call(data.cells[i])
			if mapped != NO_CELL:
				cells.append(mapped)
				durations.append(old_durations[i] if i < old_durations.size() else 1.0)
		data.cells = cells
		if data.has("durations"):
			data.durations = durations


#endregion

#region Editing frames


## Replaces each frame in [param coords] with [code]edit.call(image_copy)[/code].
## [param move] gives frames that aren't centred a new origin: it's called with the old
## origin, the old size and the new image. With [param move_centred], centred frames are
## moved too and get an origin of their own. [param op] describes the edit, so it's made
## again when a linked frame is reloaded, see [FrameEdits].
## Pivots stay on the same point of the cell, unless [param turn_pivot] says where they go:
## it's called with the pivot and the old size, and returns the pivot in the new image.
func edit_frames(
	coords: Array[Vector2i],
	edit: Callable,
	move := Callable(),
	move_centred := false,
	op := {},
	turn_pivot := Callable()
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
			var old_position := _placed_rect(coord, Vector2.ONE).position
			if move.is_valid() and (move_centred or _origins.has(coord)):
				var origin: Vector2i = move.call(get_frame_origin(coord), old.get_size(), img)
				_origins[coord] = origin
			_frames[coord] = img
			if _pivots.has(coord):
				if turn_pivot.is_valid():
					_pivots[coord] = turn_pivot.call(_pivots[coord], old.get_size())
				else:
					var moved_by := _placed_rect(coord, Vector2.ONE).position - old_position
					_pivots[coord] -= Vector2(moved_by)
			_record_op(coord, op)
			edited = true
	if edited:
		_changed()


## Places the frame at [param coord] at [param origin], see [method get_frame_origin]. An
## origin that centres the frame takes its own origin away.
func set_frame_origin(coord: Vector2i, origin: Vector2i) -> void:
	if not has_frame(coord):
		return
	var centred := origin == -_half_up(_frames[coord].get_size())
	if (centred and not _origins.has(coord)) or _origins.get(coord) == origin:
		return
	_record_move(coord, origin - get_frame_origin(coord))
	_set_or_erase(_origins, coord, null if centred else origin)
	_changed()


## Moves frames inside their cells by [param offset] unscaled pixels
func nudge_frames(coords: Array[Vector2i], offset: Vector2i) -> void:
	if offset == Vector2i.ZERO:
		return
	var moved := false
	for coord in coords:
		if has_frame(coord):
			_origins[coord] = get_frame_origin(coord) + offset
			_record_move(coord, offset)
			moved = true
	if moved:
		_changed()


## Replaces the image of an existing frame, linking it to [param source]
func replace_frame(coord: Vector2i, img: Image, source := {}) -> void:
	if has_frame(coord):
		set_frame(coord, img, source)


func set_frame_scale(new_scale: Vector2, filter := _scale_filter) -> void:
	new_scale = new_scale.max(Vector2(0.01, 0.01))
	if new_scale.is_equal_approx(_scale) and filter == _scale_filter:
		return
	_scale = new_scale
	_scale_filter = filter
	# Places are measured in scaled pixels: pack everything but pinned frames again
	for coord: Vector2i in _placements.keys():
		if not _placements[coord].get("pinned", false):
			_placements.erase(coord)
	_changed()


## Scales frames so that the cell size becomes [param size]
func resize_sprites(size: Vector2i, filter := _scale_filter) -> void:
	var base := get_base_sprite_size()
	if base.x <= 0 or base.y <= 0 or size.x <= 0 or size.y <= 0:
		return
	set_frame_scale(Vector2(size) / Vector2(base), filter)


## Adds an edit to the frame's source, so it's made again when the frame is reloaded
func _record_op(coord: Vector2i, op: Dictionary) -> void:
	if not op.is_empty() and _sources.has(coord):
		_sources[coord] = FrameSource.with_op(_sources[coord], op)


## Moves inside the cell are kept as offsets, so they still apply to a redrawn frame of
## another size, and edits made after them (like a flip) move them along
func _record_move(coord: Vector2i, offset: Vector2i) -> void:
	if offset != Vector2i.ZERO:
		_record_op(coord, {"op": "move", "by": [offset.x, offset.y]})


#endregion

#region Packed layout


func set_layout(value: Layout) -> void:
	if value != _layout:
		_layout = value
		_changed()


func set_atlas_settings(settings: AtlasSettings) -> void:
	var values := settings.to_dictionary()
	if values != _atlas:
		_atlas = values
		_changed()


#endregion

#region Output


## The whole spritesheet as one image
func get_image(options := ExportOptions.new()) -> Image:
	return SpritesheetExporter.build_image(self, options)


#endregion


## The cell size without [member frame_scale]
func get_base_sprite_size() -> Vector2i:
	return _frame_bounds(Vector2.ONE).size


## Half of [param size], rounded up: centring leaves the odd pixel on the right and bottom
static func _half_up(size: Vector2i) -> Vector2i:
	return (size + Vector2i.ONE) / 2


## The frame at [param at_scale], relative to the point every frame is placed around
func _placed_rect(coord: Vector2i, at_scale: Vector2) -> Rect2i:
	var size := _frames[coord].get_size()
	if at_scale != Vector2.ONE:
		size = Vector2i((Vector2(size) * at_scale).round()).max(Vector2i.ONE)
	if not _origins.has(coord):
		return Rect2i(-_half_up(size), size)
	return Rect2i(Vector2i((Vector2(_origins[coord]) * at_scale).round()), size)


## The smallest rectangle holding every frame at [param at_scale], placed around the
## same point
func _frame_bounds(at_scale: Vector2) -> Rect2i:
	return _bounds_of(_frames.keys(), at_scale)


## The smallest rectangle holding the frames at [param coords], or an empty one
func _bounds_of(coords: Array, at_scale: Vector2) -> Rect2i:
	var bounds := Rect2i()
	for coord: Vector2i in coords:
		var rect := _placed_rect(coord, at_scale)
		bounds = rect if bounds.size == Vector2i.ZERO else bounds.merge(rect)
	return bounds


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
	scaled_frames.prune()
	var alive := {}
	for img: Image in _frames.values():
		alive[img] = true
	pack_cache.prune(alive)
