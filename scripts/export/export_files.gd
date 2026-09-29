class_name ExportFiles
## The files an export writes, named the way the exporters name them, to say beforehand
## what an export will create.


## The paths an export of [param sheet] as [param options] say writes, in the order it
## writes them, when [param path] is picked: the file, with the export's extension added
## as [method SpritesheetExporter.with_extension] does, or the folder for sprites.
## [param coords] are the frames of a sprites export (every frame when empty), which is
## looked at as if the folder were empty unless [param on_disk]. [param page_count] is how
## many pages an atlas has, when known: finding out packs a sheet in the grid layout.
static func get_paths(
	sheet: Spritesheet,
	options: ExportOptions,
	path: String,
	coords: Array[Vector2i] = [],
	index_start := 0,
	on_disk := false,
	page_count := -1,
) -> PackedStringArray:
	var extension := options.get_file_extension()
	if extension:
		path = SpritesheetExporter.with_extension(path, extension)
	if options.packs(sheet):
		if page_count < 0:
			page_count = get_page_count(sheet, options)
		return get_atlas_paths(path, options.get_atlas_data(), page_count)
	match options.target:
		ExportOptions.Target.SPRITES:
			var sprites := PackedStringArray()
			var lowercase := {}
			for sprite in SpritesheetExporter.get_sprite_paths(
				sheet, path, options, coords, index_start, on_disk
			):
				# A file written over is written once
				if not lowercase.has(sprite.path.to_lower()):
					lowercase[sprite.path.to_lower()] = true
					sprites.append(sprite.path)
			return sprites
		ExportOptions.Target.GIF:
			return PackedStringArray([path])
	# A packed sheet is written as its pages
	if sheet.layout == Spritesheet.Layout.PACKED:
		return SpritesheetExporter.get_page_paths(path, PackedLayout.get_page_sizes(sheet).size())
	var paths := PackedStringArray([path])
	if options.get_image_data():
		paths.append(Metadata.get_path_for_image(path, options))
	return paths


## The pages of a packed atlas and its data files, as [method AtlasPacker.write] names
## them when [param path] is picked: pages are PNGs, numbered when there are more, and
## formats with a file per page number theirs the same way
static func get_atlas_paths(path: String, format: String, page_count: int) -> PackedStringArray:
	var base := SpritesheetExporter.without_extension(path, "png")
	var data := AtlasFormats.get_extension(format)
	var paths := PackedStringArray()
	for page in page_count:
		paths.append(base + ".png" if page_count == 1 else "%s_%d.png" % [base, page])
	if AtlasFormats.has_file_per_page(format) and page_count > 1:
		for page in page_count:
			paths.append("%s_%d.%s" % [base, page, data])
	else:
		paths.append(base + "." + data)
	return paths


## How many pages an atlas export of [param sheet] has. A sheet in the grid layout is
## packed to find out, which takes a while for big sheets.
static func get_page_count(sheet: Spritesheet, options: ExportOptions) -> int:
	return PackedLayout.get_page_sizes(AtlasPacker.get_packed(sheet, options)).size()
