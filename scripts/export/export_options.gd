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
	GIF,  ## One animation as an animated GIF
	## A data file from [member custom_template], next to the spritesheet image or the pages
	## of a packed atlas, see [method packs]
	CUSTOM,
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
]

## Whether the settings applied had a pattern, which is then kept even when it's the default
var _name_pattern_set := false


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
		Target.SPRITES:
			return ""
		Target.GIF:
			return "gif"
	return "png"


## The animation of [param sheet] a GIF export plays, or null for every frame
func get_gif_animation(sheet: Spritesheet) -> SheetAnimation:
	for animation in sheet.animations:
		if animation.name == gif_animation:
			return animation
	return null


## The per-sheet values, for [method Spritesheet.set_export_settings]
func to_dictionary() -> Dictionary:
	var result := {}
	var defaults := ExportOptions.new()
	defaults.sprite_name_pattern = default_name_pattern
	for key in _SHEET_KEYS:
		if get(key) != defaults.get(key) or key == &"sprite_name_pattern" and _name_pattern_set:
			result[key] = get(key)
	return result
