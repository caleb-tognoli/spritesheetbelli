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
