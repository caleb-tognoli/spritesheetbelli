class_name ScaledFrames
extends RefCounted
## The frames of a [Spritesheet] with its [member Spritesheet.frame_scale] applied, kept for
## reuse. The previous scale is kept too, so undoing a resize doesn't scale everything
## again. Big sheets are scaled ahead on worker threads with [method prepare].

## Scaled images by the image they were scaled from, per scale and filter
var _caches: Dictionary[Vector3, Dictionary] = {}
var _preparing := 0
var _sheet: WeakRef


func _init(sheet: FrameStore) -> void:
	_sheet = weakref(sheet)


## The frame at [param coord] scaled, at its own size
func get_image(coord: Vector2i) -> Image:
	var sheet := _get_sheet()
	var source: Image = sheet.frames.get(coord)
	if source == null or sheet.frame_scale == Vector2.ONE:
		return source
	var cache := _current_cache()
	if not cache.has(source):
		var img := source.duplicate()
		var new_size := scaled_size(source.get_size())
		img.resize(new_size.x, new_size.y, sheet.scale_filter)
		cache[source] = img
	return cache[source]


## Whether the frame at [param coord] is already scaled, so getting it is quick
func is_ready(coord: Vector2i) -> bool:
	var sheet := _get_sheet()
	return (
		sheet.frame_scale == Vector2.ONE
		or not sheet.has_frame(coord)
		or _current_cache().has(sheet.frames[coord])
	)


## Every scaled image kept for reuse, as a set
func get_cached_images() -> Dictionary:
	var images := {}
	for cache: Dictionary in _caches.values():
		for img: Image in cache.values():
			images[img] = true
	return images


## Whether [method prepare] is running
func is_preparing() -> bool:
	return _preparing > 0


## Roughly how many pixels still have to be scaled, to tell if it will take a while
func get_pending_work() -> int:
	var sheet := _get_sheet()
	if sheet.frame_scale == Vector2.ONE:
		return 0
	var cache := _current_cache()
	var work := 0
	for source: Image in sheet.frames.values():
		if not cache.has(source):
			var scaled := scaled_size(source.get_size())
			work += scaled.x * scaled.y + source.get_width() * source.get_height()
	return work


## Scales every frame that isn't scaled yet, on worker threads. If the scale changes in
## the meantime, the results are dropped.
func prepare(on_progress := Callable()) -> void:
	var sheet := _get_sheet()
	if sheet.frame_scale == Vector2.ONE:
		return
	var key := _cache_key()
	var cache := _current_cache()
	var sources: Array[Image] = []
	var sizes: Array[Vector2i] = []
	for source: Image in sheet.frames.values():
		if not cache.has(source) and source not in sources:
			sources.append(source)
			sizes.append(scaled_size(source.get_size()))
	var filter := sheet.scale_filter
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
	cache = _current_cache()
	for i in sources.size():
		if not cache.has(sources[i]):
			cache[sources[i]] = results[i]


## [param size] at the sheet's scale
func scaled_size(size: Vector2i) -> Vector2i:
	return Vector2i((Vector2(size) * _get_sheet().frame_scale).round()).max(Vector2i.ONE)


## Lets [param new] use what was scaled for [param old], an image with the same pixels
func alias(old: Image, new: Image) -> void:
	for cache: Dictionary in _caches.values():
		if cache.has(old):
			cache[new] = cache[old]


## Drops scaled images of frames that are gone
func prune() -> void:
	var alive := {}
	for img: Image in _get_sheet().frames.values():
		alive[img] = true
	for cache: Dictionary in _caches.values():
		for source: Image in cache.keys():
			if not alive.has(source):
				cache.erase(source)


func _get_sheet() -> Spritesheet:
	return _sheet.get_ref()


func _cache_key() -> Vector3:
	var sheet := _get_sheet()
	return Vector3(sheet.frame_scale.x, sheet.frame_scale.y, sheet.scale_filter)


func _current_cache() -> Dictionary:
	var key := _cache_key()
	if _caches.has(key):
		# Most recently used last
		var cache: Dictionary = _caches[key]
		_caches.erase(key)
		_caches[key] = cache
		return cache
	_caches[key] = {}
	while _caches.size() > 2:
		_caches.erase(_caches.keys()[0])
	return _caches[key]
