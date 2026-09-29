class_name AtlasFormats
## The data files written next to the pages of a packed atlas, telling game engines where
## each frame is, each written from a template (see [Template] and [TemplateData]).
## Frames are described by [method get_frames]; pages are
## [code]{"file": String, "size": Vector2i}[/code].

## Every format by id: its name and the template that writes it, whose header says the
## extension of its file, whether it has a file per page and which way turned frames are
## stored
const FORMATS := {
	"json":
	{
		"name": "TexturePacker JSON (hash)",
		"template": "res://templates/texture_packer_hash.template",
	},
	"json-array":
	{
		"name": "TexturePacker JSON (array)",
		"template": "res://templates/texture_packer_array.template",
	},
	"phaser":
	{
		"name": "Phaser 3 multi-atlas JSON",
		"template": "res://templates/phaser_multi_atlas.template",
	},
	"atlas":
	{
		"name": "libGDX / Spine .atlas",
		"template": "res://templates/libgdx_atlas.template",
	},
	"sparrow":
	{
		"name": "Sparrow / Starling XML",
		"template": "res://templates/sparrow_xml.template",
	},
	"godot":
	{
		"name": "Godot SpriteFrames",
		"template": "res://templates/godot_sprite_frames.template",
	},
}

## Templates by format, read when first used
static var _templates := {}


## The template of [param format], one of [constant FORMATS], or else of "json"
static func get_template(format: String) -> Template:
	if not FORMATS.has(format):
		format = "json"
	if not _templates.has(format):
		_templates[format] = Template.load_file(FORMATS[format].template)
	return _templates[format]


static func get_extension(format: String) -> String:
	return get_template(format).header.get("extension", "json")


static func has_file_per_page(format: String) -> bool:
	return get_template(format).header.get("per_page", false)


static func can_rotate(format: String) -> bool:
	return get_template(format).header.get("rotation", "clockwise") != "none"


## Whether engines reading [param format] expect turned frames turned counter-clockwise
static func is_counter_clockwise(format: String) -> bool:
	return get_template(format).header.get("rotation", "clockwise") == "counter-clockwise"


## The data file of [param format] filled with [param data] from [TemplateData]. A
## template that goes wrong is reported, and [member Template.error] says how.
static func render(format: String, data: Dictionary) -> String:
	var template := get_template(format)
	var text := template.render(data)
	if template.error:
		push_error("%s: %s" % [FORMATS.get(format, FORMATS.json).template, template.error])
	return text


## The frames of a packed atlas in reading order, from its regions (see
## [method AtlasPacker.get_regions]), with unique names from the sprite name pattern and
## how long each is shown with [param fps]
static func get_frames(
	sheet: Spritesheet, regions: Array, options: ExportOptions, index_start := 0
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var used := {}
	var durations := Metadata.frame_durations(sheet, options.animation_fps)
	for region: AtlasPacker.Region in regions:
		var name := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern, sheet, region.coord, index_start
		)
		var unique := name
		var number := 2
		while used.has(unique):
			unique = "%s_%d" % [name, number]
			number += 1
		used[unique] = true
		var frame := {
			"name": unique + ".png",
			"coord": region.coord,
			"page": region.page,
			"rect": region.rect,
			"rotated": region.rotated,
			"source_rect": region.source_rect,
			"source_size": region.source_size,
			"pivot": region.pivot,
		}
		if durations.has(frames.size()):
			frame.duration = durations[frames.size()]
		elif options.animation_fps > 0:
			frame.duration = roundi(1000.0 / options.animation_fps)
		frames.append(frame)
	return frames


## Writes the data file (or one per page) for [param frames] on [param pages], named after
## [param base_path] without an extension. Returns [code]{"error": Error, "paths":
## PackedStringArray}[/code].
static func write(
	sheet: Spritesheet,
	format: String,
	frames: Array[Dictionary],
	pages: Array[Dictionary],
	base_path: String,
	fps: float
) -> Dictionary:
	var result := {"error": OK, "paths": PackedStringArray()}
	if get_template(format).error:
		push_error("%s: %s" % [FORMATS[format].template, get_template(format).error])
		result.error = ERR_PARSE_ERROR
		return result
	var extension := get_extension(format)
	var data := TemplateData.build(frames, Metadata.animations(sheet, false), pages, fps)
	var texts := {}  # Text by path
	if has_file_per_page(format) and pages.size() > 1:
		var files := PackedStringArray()
		for page in pages.size():
			files.append("%s_%d.%s" % [base_path.get_file(), page, extension])
		for page in pages.size():
			# Each page's file names the others, so opening one opens them all
			var others := files.duplicate()
			others.remove_at(page)
			var path := base_path.get_base_dir().path_join(files[page])
			texts[path] = render(format, TemplateData.for_page(data, page, others))
	elif has_file_per_page(format) and pages.size() == 1:
		texts[base_path + "." + extension] = render(format, TemplateData.for_page(data, 0, []))
	else:
		texts[base_path + "." + extension] = render(format, data)
	for path: String in texts:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			result.error = FileAccess.get_open_error()
			return result
		file.store_string(texts[path])
		file.close()
		result.paths.append(path)
	return result
