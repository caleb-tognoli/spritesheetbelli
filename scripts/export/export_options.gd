class_name ExportOptions
extends RefCounted
## How a spritesheet is turned into images. Stored per sheet in
## [member Spritesheet.export_settings], except the JPG options which are user settings.

## What an export produces
enum Target {
	IMAGE,  ## The spritesheet as one image
	SPRITES,  ## Every frame as its own image, in a folder
	DATA,  ## The spritesheet image and a data file in [member grid_data]'s format
	ATLAS,  ## Trimmed frames packed tightly, with a data file in [member atlas_data]'s format
	GIF,  ## One animation as an animated GIF, or each in a folder
	## A data file from [member custom_template], next to the spritesheet image or the pages
	## of a packed atlas, see [method packs]
	CUSTOM,
	STRIPS,  ## Each animation as a GameMaker strip, in a folder, see [StripExporter]
}
enum Existing { ADD_NUMBER, OVERWRITE, SKIP }
## The size a packed atlas's data file gives each frame, which engines line frames up by
enum FrameSize {
	CELL,  ## Its cell, so the frames of an animation line up like in the grid
	FRAME,  ## Its own, for sprites that have nothing to do with each other
}

const IMAGE_FORMATS: Array[String] = ["png", "jpg", "webp"]

var target := Target.IMAGE
## File format of the spritesheet image when exporting only the image
var image_format := "png"

## Colour behind every frame. Formats without transparency (JPG) always use an opaque colour.
var background := Color.TRANSPARENT
## Used instead of transparency for formats that don't support it
var opaque_background := Color.WHITE
var jpg_quality := 0.9

## Pixels of empty space around the whole sheet
var padding := 0
## Pixels of empty space between cells
var spacing := 0
## Pixels by which each frame's edges are repeated outward, against texture bleeding
var extrude := 0
## The data file written next to the image of a grid sheet, a format of [AtlasFormats]
## that can describe grids
var grid_data := "json"
## The data file written next to a packed atlas, a format of [AtlasFormats] that can
## describe packed atlases
var atlas_data := "json"
var atlas_frame_size := FrameSize.CELL
## The template file of a custom template export
var custom_template := ""

## File name for exported sprites. See [method SpritesheetExporter.format_sprite_name].
var sprite_name_pattern := "{index}"
## The pattern used when none is set, which isn't stored: see [method use_defaults_of]
var default_name_pattern := "{index}"
var only_selected := false
var existing_files := Existing.ADD_NUMBER

## Frames per second of animations in data files
var animation_fps := 12.0
## The animation exported as a GIF, by name. Empty: every frame.
var gif_animation := ""
## How many times bigger GIF frames are than the sprites
var gif_scale := 1
## A GIF of each animation, in a folder, in place of the one of [member gif_animation]
var gif_every_animation := false
## File name of each GIF of [member gif_every_animation], see [AnimationFiles]
var gif_name_pattern := "{animation}"
## File name of each GameMaker strip, see [AnimationFiles]. GameMaker takes the frame
## count from the "_strip" at the end.
var strip_name_pattern := "{animation}_strip{count}"
## The sizes an image, data file, atlas or strips export is written at, whole numbers
## like "1, 2": each is the sheet that many times bigger, see [method get_scales]
var scales := "1"
## Added to the file names of every scale but 1, with {scale} filled in, see
## [method scaled_path]
var scale_suffix := "@{scale}x"
## The scale being written, one of [method get_scales]. Not stored: the exporters make
## the images, the padding, spacing and extrusion and the data files' coordinates this
## many times bigger.
var scale := 1

const _SHEET_KEYS: Array[StringName] = [
	&"target",
	&"image_format",
	&"background",
	&"padding",
	&"spacing",
	&"extrude",
	&"grid_data",
	&"atlas_data",
	&"atlas_frame_size",
	&"custom_template",
	&"sprite_name_pattern",
	&"only_selected",
	&"existing_files",
	&"animation_fps",
	&"gif_animation",
	&"gif_scale",
	&"gif_every_animation",
	&"gif_name_pattern",
	&"strip_name_pattern",
	&"scales",
	&"scale_suffix",
]
## The targets written at [member scales]
const SCALED_TARGETS: Array[Target] = [
	Target.IMAGE, Target.DATA, Target.ATLAS, Target.CUSTOM, Target.STRIPS
]
## The biggest scale
const MAX_SCALE := 16
## The tokens of [member scale_suffix], with what they give
const SCALE_TOKENS := {"scale": "The scale, like 2"}

## Whether the settings applied had a pattern, which is then kept even when it's the default
var _name_pattern_set := false
## The settings applied that aren't options, such as the project's export targets (see
## [ExportTarget]), given back as they are by [method to_dictionary]
var _kept := {}


## Options from a sheet's export settings and the user's settings
static func from_sheet(sheet: Spritesheet) -> ExportOptions:
	var options := from_settings()
	options.use_defaults_of(sheet)
	options.apply(sheet.export_settings)
	return options


## Takes the defaults that depend on [param sheet]: frames are named by animation when it
## has animations, else by number. A pattern that's set is applied after, over it.
func use_defaults_of(sheet: Spritesheet) -> void:
	var by_animation := not sheet.animations.is_empty()
	default_name_pattern = "{animation}_{animation_frame}" if by_animation else "{index}"
	sprite_name_pattern = default_name_pattern


## Options from the user's settings only
static func from_settings() -> ExportOptions:
	var options := ExportOptions.new()
	options.jpg_quality = Settings.get_value(&"jpg_quality")
	options.opaque_background = Settings.get_value(&"jpg_background")
	return options


func apply(settings: Dictionary) -> void:
	_name_pattern_set = _name_pattern_set or settings.get("sprite_name_pattern") is String
	for key: Variant in settings:
		if StringName(str(key)) not in _SHEET_KEYS:
			_kept[str(key)] = settings[key]
	for key in _SHEET_KEYS:
		if not settings.has(key):
			continue
		var value: Variant = settings[key]
		var expected := typeof(get(key))
		if typeof(value) != expected and (value is float or value is int):
			value = type_convert(value, expected)
		if typeof(value) == expected:
			set(key, value)
	if image_format not in IMAGE_FORMATS:
		image_format = "png"
	# A template taken out of the templates folder
	if not AtlasFormats.has_format(grid_data, "grid"):
		grid_data = "json"
	if not AtlasFormats.has_format(atlas_data, "packed"):
		atlas_data = "json"


## Whether the export packs the frames of [param sheet] on atlas pages: a packed atlas, or
## a custom template for a packed sheet or one that can't describe a grid
func packs(sheet: Spritesheet) -> bool:
	if target != Target.CUSTOM:
		return target == Target.ATLAS
	var packed := sheet.layout == Spritesheet.Layout.PACKED
	return packed or not AtlasFormats.can_describe(custom_template, "grid")


## The format of the data file written next to the spritesheet image (see
## [AtlasFormats]), or empty for none
func get_image_data() -> String:
	match target:
		Target.DATA:
			return grid_data
		Target.CUSTOM:
			return custom_template
	return ""


## The format of the data file of a packed atlas
func get_atlas_data() -> String:
	return custom_template if target == Target.CUSTOM else atlas_data


## What stops the export: what's wrong with its scales or the template its data file is
## written from, or empty when nothing is
func get_error() -> String:
	var scale_error := get_scale_error()
	return scale_error if scale_error else get_template_error()


## What's wrong with the template the export's data file is written from, or empty when
## there's nothing wrong or no data file
func get_template_error() -> String:
	if target == Target.CUSTOM and custom_template.strip_edges().is_empty():
		return tr("Pick a template file.")
	match target:
		Target.DATA, Target.CUSTOM:
			return AtlasFormats.get_error(get_image_data())
		Target.ATLAS:
			return AtlasFormats.get_error(atlas_data)
	return ""


## Extension of the file picked when exporting, or empty for a folder
func get_file_extension() -> String:
	match target:
		Target.IMAGE:
			return image_format
		Target.SPRITES, Target.STRIPS:
			return ""
		Target.GIF:
			return "" if gif_every_animation else "gif"
	return "png"


## The scales the export is written at, from [member scales], smallest first, each once.
## Only images, data files, atlases and strips have scales; other exports are written at
## 1.
func get_scales() -> PackedInt32Array:
	var result := PackedInt32Array()
	if target in SCALED_TARGETS:
		for part in _scale_parts():
			if part.is_valid_int() and int(part) >= 1 and int(part) <= MAX_SCALE:
				if int(part) not in result:
					result.append(int(part))
	result.sort()
	return result if result else PackedInt32Array([1])


## What's wrong with [member scales] and [member scale_suffix], or empty
func get_scale_error() -> String:
	if target not in SCALED_TARGETS:
		return ""
	for part in _scale_parts():
		if not part.is_valid_int() or int(part) < 1 or int(part) > MAX_SCALE:
			return tr("Scales are whole numbers from 1 to %d, like 1, 2.") % MAX_SCALE
	var names := {}
	for each in get_scales():
		var name := scaled_path("a.png", each)
		if names.has(name):
			return tr("The scale suffix needs {scale} to name each scale's files apart.")
		names[name] = true
	return ""


## [param path] with the suffix of [param at_scale] before its extension, when it's not 1:
## "hero.png" gives "hero@2x.png", and its data file is named after that, "hero@2x.json".
## Pages are numbered before the suffix, "hero_0@2x.png" (see
## [method SpritesheetExporter.get_page_path]), and strips have it before "_strip" (see
## [StripExporter]).
func scaled_path(path: String, at_scale: int) -> String:
	var suffix := get_scale_suffix(at_scale)
	if suffix.is_empty():
		return path
	var extension := path.get_extension()
	if extension.is_empty():
		return path + suffix
	return "%s%s.%s" % [path.get_basename(), suffix, extension]


## What the names of the files of [param at_scale] end with, before the extension:
## [member scale_suffix] with {scale} filled in, like "@2x", or empty at 1
func get_scale_suffix(at_scale: int) -> String:
	if at_scale == 1:
		return ""
	return SpritesheetExporter.fill_tokens(scale_suffix, {"scale": at_scale}, "@%dx" % at_scale)


## A copy of the options for writing [param at_scale], see [member scale]
func for_scale(at_scale: int) -> ExportOptions:
	var copy := ExportOptions.new()
	for key in _SHEET_KEYS:
		copy.set(key, get(key))
	copy.jpg_quality = jpg_quality
	copy.opaque_background = opaque_background
	copy.default_name_pattern = default_name_pattern
	copy.scale = at_scale
	return copy


## The name of the image at twice the size of the one at [param path] of this scale, for
## a page's "retina_image" in data files (see [TemplateData]), or empty when the export
## isn't written at 2 as well
func get_retina_path(path: String) -> String:
	if scale != 1 or 2 not in get_scales():
		return ""
	return scaled_path(path, 2)


func _scale_parts() -> PackedStringArray:
	var parts := PackedStringArray()
	for part in scales.replace(",", " ").split(" ", false):
		parts.append(part.strip_edges())
	return parts


## The animation of [param sheet] a GIF export plays, or null for every frame
func get_gif_animation(sheet: Spritesheet) -> SheetAnimation:
	for animation in sheet.animations:
		if animation.name == gif_animation:
			return animation
	return null


## The per-sheet values, for [method Spritesheet.set_export_settings], with the settings
## applied that aren't options
func to_dictionary() -> Dictionary:
	var result := _kept.duplicate(true)
	var defaults := ExportOptions.new()
	defaults.sprite_name_pattern = default_name_pattern
	for key in _SHEET_KEYS:
		if get(key) != defaults.get(key) or key == &"sprite_name_pattern" and _name_pattern_set:
			result[key] = get(key)
	return result
