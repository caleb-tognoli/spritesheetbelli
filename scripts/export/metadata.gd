class_name Metadata
## Describes where frames are in an exported image, for game engines.


## JSON in the TexturePacker "hash" format, readable by most engines and tools
static func texture_packer_json(
	frames: Array[Dictionary], image_file: String, image_size: Vector2i
) -> String:
	var entries := {}
	for frame in frames:
		var rect: Rect2i = frame.rect
		var source: Rect2i = frame.get("source_rect", Rect2i(Vector2i.ZERO, rect.size))
		var source_size: Vector2i = frame.get("source_size", rect.size)
		entries[frame.name] = {
			"frame": _rect(rect),
			"rotated": false,
			"trimmed": source.size != source_size,
			"spriteSourceSize": _rect(source),
			"sourceSize": {"w": source_size.x, "h": source_size.y},
		}
	var data := {
		"frames": entries,
		"meta":
		{
			"app": "spritesheetbelli",
			"version": ProjectSettings.get_setting("application/config/version", ""),
			"image": image_file,
			"format": "RGBA8888",
			"size": {"w": image_size.x, "h": image_size.y},
			"scale": "1",
		},
	}
	return JSON.stringify(data, "\t", false)


## Frames of a packed atlas, named with the sheet's sprite name pattern
static func atlas_frames(
	sheet: Spritesheet, regions: Array, options: ExportOptions, index_start := 0
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for region: AtlasPacker.Region in regions:
		var name := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern, sheet, region.coord, index_start
		)
		(
			frames
			. append(
				{
					"name": name + ".png",
					"rect": region.rect,
					"source_rect": region.source_rect,
					"source_size": region.source_size,
				}
			)
		)
	return frames


static func _rect(rect: Rect2i) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}
