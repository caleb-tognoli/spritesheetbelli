class_name ImageLoader
## Loads images on worker threads so the window stays responsive.


## Loads [param paths] in parallel. Returns the images in the same order, with null for
## files that couldn't be loaded. [param on_progress] is called with (done, total) every frame.
static func load_all(paths: PackedStringArray, on_progress := Callable()) -> Array[Image]:
	var loaded := await Parallel.map(
		paths.size(),
		func(i: int) -> Image:
			var img := Image.load_from_file(paths[i])
			if img:
				img.resource_name = paths[i].get_file()
			return img,
		on_progress
	)
	var images: Array[Image] = []
	images.assign(loaded)
	return images


## Like [method load_all], but with every frame of animated images (GIFs): what
## [method load_file] returns for each path
static func load_all_frames(paths: PackedStringArray, on_progress := Callable()) -> Array:
	return await Parallel.map(
		paths.size(), func(i: int) -> Dictionary: return load_file(paths[i]), on_progress
	)


## The frames of the image at [param path]: one, or every frame of a GIF. Empty when it
## can't be loaded.
static func load_frames(path: String) -> Array[Image]:
	var frames: Array[Image] = []
	frames.assign(load_file(path).frames)
	return frames


## The image at [param path] as [code]{"frames": Array[Image]}[/code], without frames
## when it can't be loaded. A GIF comes with its timing, see [method GifDecoder.decode].
static func load_file(path: String) -> Dictionary:
	if GifDecoder.is_gif_path(path):
		var gif := GifDecoder.load_file(path)
		return {"frames": []} if gif.has("error") else gif
	var img := Image.load_from_file(path)
	if not img:
		return {"frames": []}
	img.resource_name = path.get_file()
	return {"frames": [img]}
