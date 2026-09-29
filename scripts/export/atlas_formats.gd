class_name AtlasFormats
## The data files written next to exported images, telling game engines where each frame
## is, each written from a template (see [Template] and [TemplateData]). Every
## [code].template[/code] file in [constant BUNDLED_DIR] or [member user_dir] is a format,
## whose id is its file name without the extension and whose header says the rest, see
## [method get_header]. Frames are described by [method get_frames] or
## [method Metadata.grid_frames]; pages are [code]{"file": String, "size": Vector2i}[/code].
##
## Where a format is asked for, the path of a template file can be given instead of an id,
## for a template of the user's own that isn't in the list.

const BUNDLED_DIR := "res://templates"
const EXTENSION := "template"
## The layouts a format can describe: a grid sheet, and a packed atlas
const LAYOUTS: Array[String] = ["grid", "packed"]
## Written in [member user_dir] when it's first opened, see [method prepare_user_dir]
const USER_README := """Data file templates for spritesheetbelli

Every .template file in this folder is a data file format. The Export dialog lists it
after the bundled ones, under the name its header gives. On the command line its id is
its file name without ".template": --metadata <id> or --atlas-data <id>.

The "bundled" folder has a copy of every bundled template to start from. It's written
again each time this folder is opened from the Export dialog, so copy a template out of
it, with a name of its own, before changing it.

A template is plain text with Mustache-like tags, filled with the frames, animations and
pages of the export. The comment at its top says the format's name, the extension of its
file, whether an atlas gets a file per page, which way turned frames are stored and which
layouts it can describe. How to write one:
%s#data-file-templates
"""

## The folder of the user's own templates, listed after the bundled ones
static var user_dir := "user://templates"

## Formats by id, in the order they're listed, found by [method refresh]:
## [code]{"name": String, "path": String, "layouts": PackedStringArray, "bundled": bool}[/code]
static var _formats := {}
## Templates by path, parsed when first used and again when the file has changed:
## [code]{"template": Template, "text": String}[/code]
static var _templates := {}


## Looks for templates again, to list the ones added to [member user_dir] or taken out.
## A user template with the id of a bundled one is left out.
static func refresh() -> void:
	_formats.clear()
	for bundled: bool in [true, false]:
		var found: Array[Dictionary] = []
		var dir := BUNDLED_DIR if bundled else user_dir
		var listed := bundled or DirAccess.dir_exists_absolute(dir)
		var files := DirAccess.get_files_at(dir) if listed else PackedStringArray()
		for file: String in files:
			if file.get_extension() != EXTENSION or _formats.has(file.get_basename()):
				continue
			var path := dir.path_join(file)
			var header := _load(path).header
			(
				found
				. append(
					{
						"id": file.get_basename(),
						"name": str(header.get("name", file.get_basename())),
						"path": path,
						"layouts": _layouts_of(header),
						"bundled": bundled,
					}
				)
			)
		found.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return a.name.naturalnocasecmp_to(b.name) < 0
		)
		for format in found:
			_formats[format.id] = format


## The ids of the formats that can describe [param layout] (see [constant LAYOUTS]), or of
## every format, the bundled ones first, each by name
static func get_formats(layout := "") -> PackedStringArray:
	if _formats.is_empty():
		refresh()
	var ids := PackedStringArray()
	for id: String in _formats:
		if not layout or layout in _formats[id].layouts:
			ids.append(id)
	return ids


## Whether [param format] is the id of a format that can describe [param layout], or of
## any format
static func has_format(format: String, layout := "") -> bool:
	return format in get_formats(layout)


static func is_bundled(format: String) -> bool:
	return has_format(format) and _formats[format].bundled


## The file of the template of [param format]: a format's id, or else the path of a
## template file
static func get_template_path(format: String) -> String:
	return _formats[format].path if has_format(format) else format


## The template of [param format], read again when its file has changed since
static func get_template(format: String) -> Template:
	return _load(get_template_path(format))


## What's wrong with the template of [param format], after its file name, or empty when
## it can be used
static func get_error(format: String) -> String:
	var path := get_template_path(format)
	if not FileAccess.file_exists(path):
		return "Could not find %s." % path
	var error := get_template(format).error
	return "%s: %s" % [path.get_file(), error] if error else ""


## The [code]key: value[/code] settings the template of [param format] starts with (see
## [member Template.header]): "name", "extension" of the file, "per_page" (true for a file
## for each page of an atlas), "rotation" (which way turned frames are stored:
## "clockwise", "counter-clockwise" or "none" when the format can't say) and "layouts"
## (the ones it can describe, see [constant LAYOUTS]). The methods below read them, with
## defaults for the ones it doesn't give.
static func get_header(format: String) -> Dictionary:
	return get_template(format).header


## The format's name, or else its file name
static func get_format_name(format: String) -> String:
	var fallback := get_template_path(format).get_file().trim_suffix("." + EXTENSION)
	return str(get_header(format).get("name", fallback))


## The extension of the format's file, or else the one in its template's file name, like
## "hero.json.template", or else "txt"
static func get_extension(format: String) -> String:
	var fallback := get_template_path(format).get_file().get_basename().get_extension()
	return str(get_header(format).get("extension", fallback if fallback else "txt"))


## Whether an atlas gets a data file for each page; not unless the header says so
static func has_file_per_page(format: String) -> bool:
	return get_header(format).get("per_page") is bool and get_header(format).per_page


## Whether the format can describe turned frames; not unless the header says which way
static func can_rotate(format: String) -> bool:
	return get_header(format).get("rotation") in ["clockwise", "counter-clockwise"]


## Whether engines reading [param format] expect turned frames turned counter-clockwise
static func is_counter_clockwise(format: String) -> bool:
	return get_header(format).get("rotation") == "counter-clockwise"


## Whether [param format] can describe [param layout], one of [constant LAYOUTS]; both
## unless the header says otherwise
static func can_describe(format: String, layout: String) -> bool:
	return layout in _layouts_of(get_header(format))


## The data file of [param format] filled with [param data] from [TemplateData]. A
## template that goes wrong is reported, and [member Template.error] says how.
static func render(format: String, data: Dictionary) -> String:
	var template := get_template(format)
	var text := template.render(data)
	if template.error:
		push_error("%s: %s" % [get_template_path(format), template.error])
	return text


## Makes [member user_dir] with a README.txt saying what it's for, and a copy of every
## bundled template to start from in its "bundled" folder, written again each time
static func prepare_user_dir() -> void:
	var copies := user_dir.path_join("bundled")
	DirAccess.make_dir_recursive_absolute(copies)
	var readme := user_dir.path_join("README.txt")
	if not FileAccess.file_exists(readme):
		_write_text(readme, USER_README % AboutDialog.REPOSITORY)
	for file in DirAccess.get_files_at(BUNDLED_DIR):
		if file.get_extension() == EXTENSION:
			var text := FileAccess.get_file_as_string(BUNDLED_DIR.path_join(file))
			_write_text(copies.path_join(file), text)


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
		var frame := {
			"name": Metadata.unique_name(name, used) + ".png",
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
## [param base_path] without an extension. Files per page are numbered before the
## [param suffix] of the scale written (see [method SpritesheetExporter.get_page_path]).
## Returns [code]{"error": Error, "paths": PackedStringArray}[/code].
static func write(
	sheet: Spritesheet,
	format: String,
	frames: Array[Dictionary],
	pages: Array[Dictionary],
	base_path: String,
	fps: float,
	suffix := "",
) -> Dictionary:
	var result := {"error": OK, "paths": PackedStringArray()}
	if get_error(format):
		push_error(get_error(format))
		result.error = ERR_PARSE_ERROR
		return result
	var extension := get_extension(format)
	var data := TemplateData.build(frames, Metadata.animations(sheet, false), pages, fps)
	var texts := {}  # Text by path
	if has_file_per_page(format) and pages.size() > 1:
		var files := PackedStringArray()
		for page in pages.size():
			var file := "%s.%s" % [base_path.get_file(), extension]
			files.append(SpritesheetExporter.get_page_path(file, page, suffix))
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


## The template in the file at [param path], read again when the file has changed
static func _load(path: String) -> Template:
	var exists := FileAccess.file_exists(path)
	var text := FileAccess.get_file_as_string(path) if exists else ""
	if not _templates.has(path) or _templates[path].text != text:
		var template := Template.parse(text) if exists else Template.load_file(path)
		_templates[path] = {"template": template, "text": text}
	return _templates[path].template


## The layouts [param header] says a template can describe, both when it doesn't say
static func _layouts_of(header: Dictionary) -> PackedStringArray:
	var layouts := PackedStringArray()
	for layout in str(header.get("layouts", "")).split(",", false):
		if layout.strip_edges() in LAYOUTS:
			layouts.append(layout.strip_edges())
	return layouts if layouts else PackedStringArray(LAYOUTS)


static func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
