class_name AtlasPacker
## Packs trimmed frames tightly into one texture atlas with the MaxRects algorithm.
## Frames with the same pixels are packed once and share their place in the atlas.

const MAX_SIZE := 16384


class Region:
	## Where the trimmed frame is in the atlas
	var rect: Rect2i
	## Where the trimmed pixels were inside the full cell
	var source_rect: Rect2i
	## Size of the full cell before trimming
	var source_size: Vector2i
	var coord: Vector2i


## Packs every frame of [param sheet]. With [param power_of_two], the atlas is as wide
## and tall as powers of two, which some older engines and GPUs need. Returns
## [code]{"image": Image, "regions": Array[Region]}[/code] with a region for every frame,
## or an empty image and no regions when the frames don't fit.
static func pack(
	sheet: Spritesheet, spacing := 0, extrude := 0, power_of_two := false
) -> Dictionary:
	var images: Array[Image] = []  # Trimmed pixels, each only once
	var by_hash := {}  # Indices into images by the hash of their pixels
	var items: Array[Dictionary] = []  # Every frame, with the index of its pixels
	for coord in sheet.get_sorted_coords():
		var cell := sheet.get_cell_image(coord)
		var used := cell.get_used_rect()
		if used.size == Vector2i.ZERO:
			used = Rect2i(0, 0, 1, 1)
		var pixels := _find_or_add(images, by_hash, cell.get_region(used))
		items.append({"coord": coord, "pixels": pixels, "source_rect": used})

	var settings := AtlasSettings.new()
	settings.max_size = MAX_SIZE
	settings.spacing = spacing
	settings.extrude = extrude
	settings.power_of_two = power_of_two
	var sizes: Array[Vector2i] = []
	for img in images:
		sizes.append(img.get_size())
	var packing := RectPacker.pack(sizes, settings)
	if packing.pages != 1:
		return {"image": Image.create_empty(1, 1, false, Image.FORMAT_RGBA8), "regions": []}
	var page_rects: Array = RectPacker.rects_by_page(sizes, packing.placements, 1)[0]
	var atlas_size := RectPacker.page_size(page_rects, settings)
	var atlas := Image.create_empty(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	var rects: Array[Rect2i] = []
	for i in images.size():
		var rect := Rect2i(packing.placements[i].position, images[i].get_size())
		atlas.blit_rect(images[i], Rect2i(Vector2i.ZERO, rect.size), rect.position)
		if extrude > 0:
			SpritesheetExporter.extrude_edges(atlas, rect, extrude)
		rects.append(rect)
	var regions: Array[Region] = []
	for item in items:
		var region := Region.new()
		region.coord = item.coord
		region.rect = rects[item.pixels]
		region.source_rect = item.source_rect
		region.source_size = sheet.sprite_size
		regions.append(region)
	return {"image": atlas, "regions": regions}


## The index of an image in [param images] with the same pixels as [param img], adding
## it when there's none. [param by_hash] groups the indices by the pixels' hash.
static func _find_or_add(images: Array[Image], by_hash: Dictionary, img: Image) -> int:
	var data := img.get_data()
	var key := hash([img.get_size(), data])
	for index: int in by_hash.get(key, []):
		if images[index].get_size() == img.get_size() and images[index].get_data() == data:
			return index
	if not by_hash.has(key):
		by_hash[key] = []
	by_hash[key].append(images.size())
	images.append(img)
	return images.size() - 1


## Packs [param sheet] as [param options] say and writes the atlas PNG to [param path]
## with a JSON file next to it. Returns [code]{"error": Error, "path": String,
## "json_path": String, "frames": int, "size": Vector2i}[/code]; the error is
## ERR_OUT_OF_MEMORY when the frames don't fit.
static func write(
	sheet: Spritesheet, options: ExportOptions, path: String, index_start := 0
) -> Dictionary:
	var packed := pack(sheet, options.spacing, options.extrude, options.power_of_two)
	var image: Image = packed.image
	path = path.get_basename() + ".png"
	var result := {
		"error": OK,
		"path": path,
		"json_path": path.get_basename() + "." + options.atlas_data,
		"frames": packed.regions.size(),
		"size": image.get_size(),
	}
	if packed.regions.is_empty():
		result.error = ERR_OUT_OF_MEMORY
		return result
	var frames := Metadata.atlas_frames(sheet, packed.regions, options, index_start)
	result.error = image.save_png(path)
	if result.error != OK:
		return result
	var file := FileAccess.open(result.json_path, FileAccess.WRITE)
	if file == null:
		result.error = FileAccess.get_open_error()
		return result
	if options.atlas_data == "atlas":
		file.store_string(Metadata.libgdx_atlas(frames, path.get_file(), image.get_size()))
	else:
		file.store_string(
			Metadata.sheet_json(
				sheet, frames, path.get_file(), image.get_size(), options.animation_fps
			)
		)
	file.close()
	return result
