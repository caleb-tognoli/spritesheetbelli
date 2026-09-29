class_name AtlasPacker
## Exports frames packed tightly into atlas pages, with a data file for game engines (see
## [AtlasFormats]). A sheet in the packed layout is exported as it's laid out; a grid sheet
## is packed on the way, see [PackedLayout].

## The biggest page Godot can save
const MAX_SIZE := 16384


## Where a frame is in the atlas
class Region:
	var coord: Vector2i
	var page := 0
	## Where the frame is on its page, as stored: turned frames are as wide as they're tall
	var rect: Rect2i
	## Stored turned 90°
	var rotated := false
	## Where the packed pixels are in the untrimmed frame (or its cell)
	var source_rect: Rect2i
	## Size of the untrimmed frame (or its cell)
	var source_size: Vector2i
	## The frame's pivot, from 0 to 1 across the untrimmed frame (or its cell)
	var pivot := Vector2(0.5, 0.5)

	## Makes the region [param scale] times bigger, for a page as many times bigger
	func scale_by(scale: int) -> void:
		rect = Rect2i(rect.position * scale, rect.size * scale)
		source_rect = Rect2i(source_rect.position * scale, source_rect.size * scale)
		source_size *= scale


## [param sheet] itself when it's packed, else a packed copy of it for exporting. Formats
## that can't describe turned frames get none.
static func get_packed(sheet: Spritesheet, options: ExportOptions) -> Spritesheet:
	if sheet.layout == Spritesheet.Layout.PACKED:
		return sheet
	var settings := sheet.atlas_settings
	settings.pack_mode = AtlasSettings.PackMode.AUTO
	settings.spacing = options.spacing
	settings.extrude = options.extrude
	# Grid sheets used to be packed on one page as big as possible
	if not sheet.atlas_settings.to_dictionary().has("max_size"):
		settings.max_size = MAX_SIZE
	if not AtlasFormats.can_rotate(options.get_atlas_data()):
		settings.allow_rotation = false
	var state := sheet.get_state()
	state.placements = {}
	var packed := Spritesheet.new()
	packed.set_state(state)
	packed.begin_batch()
	packed.set_atlas_settings(settings)
	packed.set_layout(Spritesheet.Layout.PACKED)
	packed.end_batch()
	return packed


## Where every frame of a packed sheet is, in reading order, with the size of its cell or
## its own as [param frame_size] says
static func get_regions(
	packed: Spritesheet, frame_size := ExportOptions.FrameSize.CELL
) -> Array[Region]:
	var settings := packed.atlas_settings
	var regions: Array[Region] = []
	for coord in packed.get_sorted_coords():
		var place: Dictionary = packed.placements.get(coord, {})
		if place.is_empty():
			continue
		var region := Region.new()
		region.coord = coord
		region.page = place.page
		region.rect = PackedLayout.get_rect(packed, coord)
		region.rotated = place.rotated
		var src: Rect2i = place.src
		var frame_scale := packed.frame_scale
		var pivot := packed.get_pivot(coord) * frame_scale
		if frame_size == ExportOptions.FrameSize.CELL:
			var in_cell := packed.get_frame_rect_in_cell(coord).position
			region.source_rect = Rect2i(in_cell + src.position, src.size)
			region.source_size = packed.sprite_size
			pivot += Vector2(in_cell)
		else:
			region.source_rect = src
			region.source_size = packed.scaled_frames.scaled_size(packed.frames[coord].get_size())
		region.pivot = settings.default_pivot
		if packed.has_pivot(coord):
			region.pivot = pivot / Vector2(region.source_size.max(Vector2i.ONE))
		regions.append(region)
	return regions


## Packs every frame of [param sheet] on one page. Returns
## [code]{"image": Image, "regions": Array[Region]}[/code] with a region for every frame,
## or an empty image and no regions when the frames don't fit on one page.
static func pack(sheet: Spritesheet, spacing := 0, extrude := 0) -> Dictionary:
	var options := ExportOptions.new()
	options.spacing = spacing
	options.extrude = extrude
	var packed := get_packed(sheet, options)
	var pages := PackedLayout.render_pages(packed)
	if pages.size() != 1:
		return {"image": Image.create_empty(1, 1, false, Image.FORMAT_RGBA8), "regions": []}
	return {"image": pages[0], "regions": get_regions(packed)}


## Packs [param sheet] as [param options] say (or takes its packed layout) and writes the
## pages to [param path], numbered when there are more, with the data file next to them.
## At a [member ExportOptions.scale] other than 1, it's the same atlas that many times
## bigger: the frames are where they'd be at 1, so the scales line up.
## Returns [code]{"error": Error, "message": String, "path": String, "json_path": String,
## "paths": PackedStringArray, "frames": int, "size": Vector2i, "pages": int}[/code] with
## the first page and data file and every file written. The error is ERR_OUT_OF_MEMORY
## when a page would be too big, and ERR_UNAVAILABLE when the format's template can't be
## used or can't describe how the frames are packed, with a message saying why.
static func write(
	sheet: Spritesheet, options: ExportOptions, path: String, index_start := 0
) -> Dictionary:
	var format := options.get_atlas_data()
	if AtlasFormats.get_error(format):
		return {"error": ERR_UNAVAILABLE, "message": AtlasFormats.get_error(format)}
	var packed := get_packed(sheet, options)
	var regions := get_regions(packed, options.atlas_frame_size)
	if options.scale != 1:
		for region in regions:
			region.scale_by(options.scale)
	var sizes := PackedLayout.get_page_sizes(packed, options.scale)
	# Pages are PNGs: "hero.png" gives hero.png and hero.json, "hero.json" hero.json.png
	var base := SpritesheetExporter.without_extension(path, "png")
	var retina_path := options.get_retina_path(path)
	var retina_base := SpritesheetExporter.without_extension(retina_path, "png")
	var result := {
		"error": OK,
		"message": "",
		"path": base + ".png",
		"json_path": base + "." + AtlasFormats.get_extension(format),
		"paths": PackedStringArray(),
		"frames": regions.size(),
		"size": sizes[0] if sizes else Vector2i.ZERO,
		"pages": sizes.size(),
	}
	for size in sizes:
		if size.x > MAX_SIZE or size.y > MAX_SIZE:
			result.error = ERR_OUT_OF_MEMORY
			return result
	if not AtlasFormats.can_rotate(format):
		for region in regions:
			if region.rotated:
				result.error = ERR_UNAVAILABLE
				result.message = (
					"%s can't describe turned frames. Pack without turning them."
					% AtlasFormats.get_format_name(format)
				)
				return result
	var images := PackedLayout.render_pages(
		packed, AtlasFormats.is_counter_clockwise(format), options.scale
	)
	# Numbered before the scale's suffix: hero_0@2x.png
	var suffix := options.get_scale_suffix(options.scale)
	var page_paths := SpritesheetExporter.get_page_paths(base + ".png", images.size(), suffix)
	var retinas := SpritesheetExporter.get_page_paths(
		retina_base + ".png", images.size(), options.get_scale_suffix(2)
	)
	var pages: Array[Dictionary] = []
	for page in images.size():
		result.error = images[page].save_png(page_paths[page])
		if result.error != OK:
			return result
		result.paths.append(page_paths[page])
		pages.append({"file": page_paths[page].get_file(), "size": images[page].get_size()})
		if retina_path:
			pages[-1].retina_image = retinas[page].get_file()
	if pages:
		result.path = result.paths[0]
	var frames := AtlasFormats.get_frames(packed, regions, options, index_start)
	var written := AtlasFormats.write(
		packed, format, frames, pages, base, options.animation_fps, suffix
	)
	result.error = written.error
	result.paths.append_array(written.paths)
	if written.paths:
		result.json_path = written.paths[0]
	return result
