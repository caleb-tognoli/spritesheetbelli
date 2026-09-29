class_name ExportTarget
extends RefCounted
## One export of a project: what it writes, as [ExportOptions] of its own, and where. A
## project's targets are kept in its sheet's export settings under [constant KEY], see
## [method list]; exporting again writes every one.

## The key of [member Spritesheet.export_settings] holding the targets
const KEY := "targets"

## Everything but the sheet's spacing and padding, which the sheet's layout has
var options: ExportOptions
## The file written, or the folder of sprites: absolute, or empty until one is picked.
## Always empty in a browser, where exports are downloaded instead.
var path := ""


## A target of [param sheet] with [param settings] (from [method to_dictionary]). What
## isn't set is the default, apart from the spacing and padding of the sheet.
static func create(sheet: Spritesheet, settings := {}) -> ExportTarget:
	var target := ExportTarget.new()
	target.options = ExportOptions.from_settings()
	target.options.use_defaults_of(sheet)
	var own := settings.duplicate()
	var layout := {}
	for key in Document.LAYOUT_EXPORT_KEYS:
		own.erase(key)
		if sheet.export_settings.has(key):
			layout[key] = sheet.export_settings[key]
	own.erase(KEY)
	own.erase("path")
	target.options.apply(layout)
	target.options.apply(own)
	if settings.get("path") is String:
		target.path = settings.path
	return target


## The targets saved with [param sheet], in order
static func list(sheet: Spritesheet) -> Array[ExportTarget]:
	var targets: Array[ExportTarget] = []
	var saved: Variant = sheet.export_settings.get(KEY)
	if not saved is Array:
		return targets
	for settings: Variant in saved:
		if settings is Dictionary:
			targets.append(create(sheet, settings))
	return targets


## The export settings of [param sheet] with [param targets] as its targets
static func settings_with(sheet: Spritesheet, targets: Array[ExportTarget]) -> Dictionary:
	var settings := sheet.export_settings.duplicate()
	settings.erase(KEY)
	if not targets.is_empty():
		settings[KEY] = targets.map(
			func(target: ExportTarget) -> Dictionary: return target.to_dictionary()
		)
	return settings


## The values of the target that aren't the defaults, with its type and path always
func to_dictionary() -> Dictionary:
	var settings := options.to_dictionary()
	for key in Document.LAYOUT_EXPORT_KEYS:
		settings.erase(key)
	settings.erase(KEY)
	settings.erase("path")
	settings.target = options.target
	if path:
		settings.path = path
	return settings


## A copy of the target, for [param sheet]
func copy(sheet: Spritesheet) -> ExportTarget:
	return create(sheet, to_dictionary())


## What the target writes, in a few words: "PNG", "Sprites", "GIFs" or the name of its data
## format
func get_format_name() -> String:
	var name := options.image_format.to_upper()
	match options.target:
		ExportOptions.Target.SPRITES:
			name = TranslationServer.translate("Sprites")
		ExportOptions.Target.DATA:
			name = AtlasFormats.get_format_name(options.grid_data)
		ExportOptions.Target.ATLAS:
			name = (
				TranslationServer.translate("%s atlas")
				% AtlasFormats.get_format_name(options.atlas_data)
			)
		ExportOptions.Target.GIF:
			name = "GIF"
			if options.gif_every_animation:
				name = TranslationServer.translate("GIFs")
		ExportOptions.Target.STRIPS:
			name = TranslationServer.translate("GameMaker strips")
		ExportOptions.Target.CUSTOM:
			name = options.custom_template.strip_edges().get_file()
			if name.is_empty():
				name = TranslationServer.translate("Custom template")
	return name


## [param file] fitted to what [param export] writes: with the extension of the file
## written, in place of the one of an image or GIF export of another kind, and without it
## for a folder of sprites. Like [method SpritesheetExporter.with_extension], other
## extensions are part of the name.
static func fit_path(file: String, export: ExportOptions) -> String:
	if file.is_empty():
		return file
	var extension := export.get_file_extension()
	var written := file.get_extension().to_lower()
	var exported := written in SpritesheetExporter.IMAGE_EXTENSIONS or written == "gif"
	if not extension:
		return file.get_basename() if exported else file
	if SpritesheetExporter.has_extension(file, extension):
		return file
	return SpritesheetExporter.with_extension(file.get_basename() if exported else file, extension)


## [param settings] (a sheet's export settings) with the paths of its targets relative to
## [param folder], for saving a project there
static func paths_to_relative(settings: Dictionary, folder: String) -> Dictionary:
	return _map_paths(
		settings, func(file: String) -> String: return FrameSource.relative_path(file, folder)
	)


## [param settings] read from a project saved in [param folder], with the paths of its
## targets absolute again
static func paths_to_absolute(settings: Dictionary, folder: String) -> Dictionary:
	return _map_paths(
		settings,
		func(file: String) -> String:
			if file.is_absolute_path() or folder.is_empty():
				return file
			return folder.path_join(file).simplify_path()
	)


static func _map_paths(settings: Dictionary, change: Callable) -> Dictionary:
	if not settings.get(KEY) is Array:
		return settings
	var result := settings.duplicate()
	var targets := []
	for target: Variant in settings[KEY]:
		if target is Dictionary and target.get("path") is String and target.path:
			target = target.duplicate()
			target.path = change.call(target.path)
		targets.append(target)
	result[KEY] = targets
	return result
