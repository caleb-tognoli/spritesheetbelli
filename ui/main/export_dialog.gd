class_name ExportDialog
extends ConfirmationDialog
## Adds and edits the project's export targets (see [ExportTarget]): their list on the left,
## the one selected on the right, with only the settings that matter for its type and
## where it writes. Export writes the selected one and Export All every one. Edits are
## changes to the project, kept when closing, but not undo steps. A project without
## targets gets a new one, kept once it's changed or exported, so a one-off export is
## still a click or two.

const T := ExportOptions.Target
const FOLDER_ICON := preload("res://assets/icons/Folder.svg")
## What can be exported, in the order the Type list has them
const TYPES := [
	{
		"target": T.IMAGE,
		"name": "Spritesheet image",
		"icon": preload("res://assets/icons/Image.svg"),
		"about":
		"The whole sheet as one PNG, JPG or WebP image. Packed sheets give an image " + "per page.",
	},
	{
		"target": T.SPRITES,
		"name": "Sprites",
		"icon": FOLDER_ICON,
		"about": "Every frame as its own PNG, in a folder.",
	},
	{
		"target": T.DATA,
		"name": "Spritesheet and data file",
		"icon": preload("res://assets/icons/SpriteFrames.svg"),
		"about":
		(
			"The sheet as a PNG and a file next to it that says where each frame is, "
			+ "with the animations: a Godot SpriteFrames, TexturePacker or Aseprite JSON, "
			+ "and more."
		),
	},
	{
		"target": T.ATLAS,
		"name": "Packed atlas",
		"icon": preload("res://assets/icons/AtlasTexture.svg"),
		"about":
		(
			"Frames with their transparent borders trimmed, packed as tightly as "
			+ "possible into PNG pages, with a file that says where each one is for "
			+ "TexturePacker, Phaser, libGDX, Spine, Starling or Godot."
		),
	},
	{
		"target": T.GIF,
		"name": "Animated GIF",
		"icon": preload("res://assets/icons/Animation.svg"),
		"about":
		(
			"One animation as a GIF, or a GIF of each in a folder, to share or put on a "
			+ "page. GIF has no partial transparency and at most 255 colours; sheets with "
			+ "more are reduced."
		),
	},
	{
		"target": T.STRIPS,
		"name": "GameMaker strips",
		"icon": preload("res://assets/icons/ImageStrip.svg"),
		"about":
		(
			"Each animation as a PNG of its frames side by side, in a folder, named for "
			+ "GameMaker to cut it into frames when imported (walk_strip8.png). Frames in no "
			+ "animation are left out."
		),
	},
	{
		"target": T.CUSTOM,
		"name": "Custom template",
		"icon": preload("res://assets/icons/TextFile.svg"),
		"about":
		(
			"The sheet as a PNG and a data file written from a template of your own. "
			+ "Packed sheets, and templates only for packed atlases, give atlas pages."
		),
	},
]
## What a sheet in the packed layout can be exported as
const PACKED_TYPES: Array[ExportOptions.Target] = [
	ExportOptions.Target.IMAGE,
	ExportOptions.Target.ATLAS,
	ExportOptions.Target.SPRITES,
	ExportOptions.Target.GIF,
	ExportOptions.Target.STRIPS,
	ExportOptions.Target.CUSTOM,
]
const LABEL_WIDTH := 170
const EXPORT_ALL := &"export_all"
## Files named in the list of what an export writes, before "… 3 more"
const FILES_SHOWN := 5
## The item of [member gif_animation] for a GIF of each animation, after "All frames"
const EVERY_ANIMATION := 1

## The frames selected in the preview, for exporting only those
var get_selected_coords := func() -> Array[Vector2i]: return []
## Writes the exports
var exports: ExportController
## The project's targets, with the type's icon, where each writes and its format
var target_list := ItemList.new()
var add_target := Button.new()
var duplicate_target := Button.new()
var remove_target := Button.new()
var export_all: Button
## The type of the selected target, with [constant TYPES]' order
var type := OptionButton.new()
var about := Label.new()
## Where the selected target writes. Browsers download exports instead, so it isn't shown.
var output := OutputPathField.new()
var image_format := OptionButton.new()
var jpg_quality := SpinBox.new()
var jpg_background := ColorPickerButton.new()
var background_picker := ColorPickerButton.new()
## Says "Transparent" on [member background_picker] when it's fully transparent
var transparent_label := Label.new()
var pattern := NamePatternField.new()
var pattern_example := Label.new()
var only_selected := CheckBox.new()
var existing := OptionButton.new()
var animation_fps := SpinBox.new()
var frame_size := OptionButton.new()
## Data formats, with their ids as the items' metadata
var grid_data := OptionButton.new()
var atlas_data := OptionButton.new()
var template_file := TemplateFileField.new()
var templates_folder := Button.new()
var gif_animation := OptionButton.new()
var gif_scale := SpinBox.new()
## The settings of exports that write a file per animation
var animation_files := AnimationFilesRows.new()
## The scales exports are written at
var scale_rows := ScaleRows.new()
## Why the export can't be written, like a template that can't be used, which stops it
var template_error := Label.new()
## The files an export writes, when it writes more than one
var files_info := Label.new()
var output_info := Label.new()

var _settings := _grid()
## The targets edited, stored with the sheet when the dialog closes or exports
var _targets: Array[ExportTarget] = []
var _selected := 0
## Whether [member _targets] is the new target of a project without any, which is only
## kept once it's changed or exported
var _draft := false
## Controls of each row, with the targets they're shown for
var _rows: Array[Dictionary] = []
var _pattern_label: Label
var _output_label: Label
var _fps_label: Label
## The rows of the data format dropdowns, which custom templates don't have
var _format_rows: Array[Control] = []
var _updating := false
## Pages of an atlas of the grid, by whether frames may be turned, found by packing it
var _atlas_pages := {}


func _init() -> void:
	title = "Export"
	ok_button_text = "Export"
	cancel_button_text = "Close"
	# Exporting a target that doesn't know where to write asks first
	dialog_hide_on_ok = false
	export_all = add_button("Export All", false, EXPORT_ALL)
	export_all.tooltip_text = "Export every one in the list"
	DialogButtons.apply(self)
	# Big enough for every export type, so it doesn't change size when switching
	min_size = Vector2i(840, 500)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	add_child(layout)

	var left := VBoxContainer.new()
	layout.add_child(left)
	target_list.custom_minimum_size = Vector2(230, 280)
	target_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	target_list.fixed_icon_size = Vector2i(16, 16)
	target_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(target_list)
	var list_buttons := HBoxContainer.new()
	left.add_child(list_buttons)
	add_target.text = "Add"
	add_target.icon = preload("res://assets/icons/Add.svg")
	add_target.tooltip_text = "Add an export, to write more than one at once"
	duplicate_target.icon = preload("res://assets/icons/Duplicate.svg")
	duplicate_target.tooltip_text = "Duplicate the selected export"
	remove_target.icon = preload("res://assets/icons/Remove.svg")
	remove_target.tooltip_text = "Remove the selected export"
	for button: Button in [add_target, duplicate_target, remove_target]:
		list_buttons.add_child(button)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	layout.add_child(right)
	var head := _grid()
	right.add_child(head)
	var every_type := TYPES.map(func(entry: Dictionary) -> int: return entry.target)
	for entry: Dictionary in TYPES:
		type.add_icon_item(entry.icon, entry.name)
	type.tooltip_text = "What the export writes"
	add_row(head, "Type", type, every_type)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapped label needs a width, or it's measured one word per line
	about.custom_minimum_size = Vector2(420, 0)
	about.theme_type_variation = &"StatusLabel"
	right.add_child(about)
	right.add_child(_settings)

	output.tooltip_text = (
		"Where the export writes. The files written next to it, like data files and pages, "
		+ "are named after it."
	)
	output.line_edit.tooltip_text = output.tooltip_text
	_output_label = add_row(_settings, "Export to", output, every_type)

	for format: String in ExportOptions.IMAGE_FORMATS:
		image_format.add_item(format.to_upper())
	add_row(_settings, "Format", image_format, [T.IMAGE])
	jpg_quality.min_value = 1
	jpg_quality.max_value = 100
	jpg_quality.suffix = "%"
	add_row(_settings, "JPG quality", jpg_quality, [T.IMAGE], "jpg")
	jpg_background.edit_alpha = false
	jpg_background.custom_minimum_size = Vector2(60, 0)
	jpg_background.tooltip_text = "JPG has no transparency, so transparent areas get this colour"
	add_row(_settings, "Fill transparency with", jpg_background, [T.IMAGE], "jpg")

	background_picker.tooltip_text = (
		"A colour behind the sprites. Fully transparent (the default) leaves the "
		+ "background transparent."
	)
	background_picker.custom_minimum_size = Vector2(60, 0)
	transparent_label.text = "Transparent"
	transparent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transparent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transparent_label.add_theme_color_override("font_color", Color.WHITE)
	transparent_label.add_theme_color_override("font_outline_color", Color.BLACK)
	transparent_label.add_theme_constant_override("outline_size", 4)
	transparent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transparent_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_picker.add_child(transparent_label)
	add_row(_settings, "Background", background_picker, [T.IMAGE, T.DATA, T.GIF, T.STRIPS])
	gif_animation.tooltip_text = "Which animation the GIF plays"
	add_row(_settings, "Animation", gif_animation, [T.GIF])
	gif_scale.min_value = 1
	gif_scale.max_value = 16
	gif_scale.suffix = "×"
	gif_scale.tooltip_text = "Makes the GIF bigger, keeping pixels sharp"
	add_row(_settings, "Scale", gif_scale, [T.GIF])
	animation_files.add_to(self, _settings)
	grid_data.tooltip_text = "The file next to the image that says where each frame is"
	_format_rows.append(add_row(_settings, "Data file", grid_data, [T.DATA]))
	_format_rows.append(grid_data)
	atlas_data.tooltip_text = "The file next to the atlas that says where each frame is"
	_format_rows.append(add_row(_settings, "Data file", atlas_data, [T.ATLAS]))
	_format_rows.append(atlas_data)
	template_file.tooltip_text = (
		"The template the data file is written from. Its header says the file's " + "extension."
	)
	template_file.line_edit.tooltip_text = template_file.tooltip_text
	add_row(_settings, "Template", template_file, [T.CUSTOM])
	templates_folder.text = "Open templates folder"
	templates_folder.icon = FOLDER_ICON
	templates_folder.tooltip_text = (
		"Templates put in this folder are listed with the bundled ones, and one named like "
		+ "a bundled one replaces it. It has a copy of every bundled template to start from."
	)
	# Browsers can't open a folder of the user's
	var folder_targets := [] if WebFiles.is_web() else [T.DATA, T.ATLAS, T.CUSTOM]
	add_row(_settings, "", templates_folder, folder_targets)
	templates_folder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame_size.add_item("Their cell", ExportOptions.FrameSize.CELL)
	frame_size.add_item("Their own", ExportOptions.FrameSize.FRAME)
	frame_size.tooltip_text = (
		"The size the data file gives each frame, which engines line frames up by.\n"
		+ "Their cell: the frames of an animation line up like in the grid, even when "
		+ "trimmed or of different sizes.\n"
		+ "Their own: each frame is as big as it is, for sprites that have nothing to do "
		+ "with each other."
	)
	add_row(_settings, "Frame size in data", frame_size, [T.ATLAS])
	scale_rows.add_to(self, _settings)

	animation_fps.min_value = 1
	animation_fps.max_value = 120
	animation_fps.step = 0.5
	animation_fps.suffix = "fps"
	animation_fps.tooltip_text = "Frames per second of the animations"
	_fps_label = add_row(_settings, "Animation speed", animation_fps, [T.DATA, T.GIF])

	pattern.line_edit.custom_minimum_size = Vector2(120, 0)
	pattern.tooltip_text = "How each frame is named, with tokens such as {index} filled in"
	pattern.line_edit.tooltip_text = pattern.tooltip_text
	_pattern_label = add_row(_settings, "File names", pattern, [T.SPRITES, T.DATA, T.ATLAS])
	pattern_example.theme_type_variation = &"StatusLabel"
	pattern_example.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pattern_example.custom_minimum_size = Vector2(200, 0)
	# Sprites have the list of files instead
	add_row(_settings, "", pattern_example, [T.DATA, T.ATLAS])
	only_selected.text = "Only selected frames"
	add_row(_settings, "", only_selected, [T.SPRITES])
	for label: String in ["Add a number", "Overwrite it", "Skip the sprite"]:
		existing.add_item(label)
	add_row(_settings, "When a file exists", existing, [T.SPRITES])

	template_error.theme_type_variation = &"ErrorLabel"
	template_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	template_error.custom_minimum_size = Vector2(380, 0)
	right.add_child(template_error)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	files_info.theme_type_variation = &"StatusLabel"
	files_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	files_info.custom_minimum_size = Vector2(380, 0)
	right.add_child(files_info)
	output_info.theme_type_variation = &"StatusLabel"
	right.add_child(output_info)

	type.item_selected.connect(_changed.unbind(1))
	image_format.item_selected.connect(_changed.unbind(1))
	background_picker.color_changed.connect(_changed.unbind(1))
	pattern.text_changed.connect(_changed.unbind(1))
	only_selected.toggled.connect(_changed.unbind(1))
	existing.item_selected.connect(_changed.unbind(1))
	frame_size.item_selected.connect(_changed.unbind(1))
	gif_animation.item_selected.connect(_changed.unbind(1))
	grid_data.item_selected.connect(_changed.unbind(1))
	atlas_data.item_selected.connect(_changed.unbind(1))
	template_file.path_changed.connect(_changed.unbind(1))
	output.path_changed.connect(_changed.unbind(1))
	output.browse_pressed.connect(browse)
	animation_files.changed.connect(_changed)
	scale_rows.changed.connect(_changed)
	templates_folder.pressed.connect(open_templates_folder)
	for spin: SpinBox in [jpg_quality, animation_fps, gif_scale]:
		spin.value_changed.connect(_changed.unbind(1))
	jpg_background.color_changed.connect(_changed.unbind(1))
	target_list.item_selected.connect(select)
	add_target.pressed.connect(add)
	duplicate_target.pressed.connect(duplicate_selected)
	remove_target.pressed.connect(remove_selected)
	confirmed.connect(export_selected)
	custom_action.connect(
		func(action: StringName) -> void:
			if action == EXPORT_ALL:
				_export(_targets.duplicate())
	)
	visibility_changed.connect(
		func() -> void:
			if not visible:
				_store()
	)


func _ready() -> void:
	about_to_popup.connect(refresh)
	# The label stays next to the field when a warning shows under it
	_pattern_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pattern_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pattern_label.custom_minimum_size.y = pattern.field_row.get_combined_minimum_size().y
	for spin: SpinBox in [jpg_quality, animation_fps, gif_scale]:
		spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		SpinScroll.enable(spin)


## Shows the project's targets, or a new one when there are none, selecting the one
## selected last time
func refresh() -> void:
	_atlas_pages.clear()
	# Templates may have been put in the templates folder since
	AtlasFormats.refresh()
	# A packed sheet is exported as it's packed, not as a grid
	var packed := _is_packed()
	for i in TYPES.size():
		var grid_only: bool = TYPES[i].target not in PACKED_TYPES
		type.set_item_disabled(i, packed and grid_only)
		type.set_item_tooltip(i, tr("Only in the grid layout") if packed and grid_only else "")
	_targets = ExportTarget.list(Global.spritesheet)
	_draft = _targets.is_empty()
	if _draft:
		_targets.append(new_target())
	_fill_list()
	select(_selected)


## A target to add: like the sheet's own export settings, like how it was imported. Packed
## sheets are usually exported as atlases, until another export is picked.
static func new_target() -> ExportTarget:
	var sheet := Global.spritesheet
	var target := ExportTarget.create(sheet, ExportOptions.from_sheet(sheet).to_dictionary())
	var chosen := sheet.export_settings.has("target")
	if _is_packed() and (target.options.target not in PACKED_TYPES or not chosen):
		target.options.target = T.ATLAS
	return target


## The targets as edited
func get_targets() -> Array[ExportTarget]:
	return _targets


## The selected target
func get_target() -> ExportTarget:
	return _targets[_selected]


## Shows the target at [param index] of the list
func select(index: int) -> void:
	_selected = clampi(index, 0, _targets.size() - 1)
	target_list.select(_selected)
	target_list.ensure_current_is_visible()
	remove_target.disabled = _draft
	export_all.disabled = _targets.size() < 2
	_show(_targets[_selected])


## Adds a new target after the others and selects it
func add() -> void:
	_draft = false
	_targets.append(new_target())
	_fill_list()
	select(_targets.size() - 1)


## Adds a copy of the selected target after it, to change a little
func duplicate_selected() -> void:
	_draft = false
	_targets.insert(_selected + 1, get_target().copy(Global.spritesheet))
	_fill_list()
	select(_selected + 1)


## Removes the selected target. The last one leaves a new one in its place, kept only when
## it's changed or exported, as in a project without targets.
func remove_selected() -> void:
	_targets.remove_at(_selected)
	_draft = _targets.is_empty()
	if _draft:
		_targets.append(new_target())
	_fill_list()
	select(_selected)


## Selects what to export
func select_type(target: ExportOptions.Target) -> void:
	type.select(_type_index(target))
	_changed()


## The options of the selected target as set in the dialog
func get_options() -> ExportOptions:
	return get_target().options


## Asks where the selected target writes, then runs [param then] with the path picked
func browse(then := Callable()) -> void:
	var options := get_options()
	var folder_titles := {T.GIF: "Export GIFs", T.STRIPS: "Export Strips"}
	var folder_title: String = folder_titles.get(options.target, "Export Sprites")
	output.browse(
		ExportController.suggested_path(options), options.get_file_extension(), then, folder_title
	)


## Exports the selected target, asking where first when it doesn't know
func export_selected() -> void:
	var target := get_target()
	if ExportController.has_place(target):
		_export([target])
	else:
		browse(func(_path: String) -> void: _export([target]))


## Closes the dialog, which stores the targets, and exports those in [param list]
func _export(list: Array[ExportTarget]) -> void:
	_draft = false
	hide()
	if exports:
		await exports.export_targets(list)


## Stores the targets with the sheet (a change to save, not an undo step) and the JPG
## options as settings. A new target that wasn't changed or exported isn't kept.
func _store() -> void:
	if _targets.is_empty():
		return
	var options := get_options()
	Settings.set_value(&"jpg_quality", options.jpg_quality)
	Settings.set_value(&"jpg_background", options.opaque_background)
	var sheet := Global.spritesheet
	var kept: Array[ExportTarget] = []
	if not _draft:
		kept = _targets
	var settings := ExportTarget.settings_with(sheet, kept)
	if settings != sheet.export_settings:
		Global.document.perform("Export targets", sheet.set_export_settings.bind(settings))


## Shows the settings of [param target]
func _show(target: ExportTarget) -> void:
	_updating = true
	var options := target.options
	type.select(_type_index(options.target))
	image_format.select(ExportOptions.IMAGE_FORMATS.find(options.image_format))
	jpg_quality.set_value_no_signal(roundi(options.jpg_quality * 100))
	jpg_background.color = options.opaque_background
	background_picker.color = options.background
	pattern.text = options.sprite_name_pattern
	pattern.line_edit.placeholder_text = options.default_name_pattern
	only_selected.button_pressed = options.only_selected
	existing.select(options.existing_files)
	animation_fps.set_value_no_signal(options.animation_fps)
	frame_size.select(frame_size.get_item_index(options.atlas_frame_size))
	gif_animation.clear()
	gif_animation.add_item("All frames")
	gif_animation.add_item("Every animation")
	gif_animation.set_item_tooltip(EVERY_ANIMATION, "A GIF of each animation, in a folder")
	if options.gif_every_animation:
		gif_animation.select(EVERY_ANIMATION)
	for animation in Global.spritesheet.animations:
		gif_animation.add_item(animation.name)
		if animation.name == options.gif_animation and not options.gif_every_animation:
			gif_animation.select(gif_animation.item_count - 1)
	animation_files.show_options(options)
	scale_rows.show_options(options)
	gif_scale.set_value_no_signal(options.gif_scale)
	_fill_formats(grid_data, "grid", options.grid_data)
	_fill_formats(atlas_data, "packed", options.atlas_data)
	template_file.path = options.custom_template
	output.path = target.path
	_updating = false
	_update_labels(options)


## Takes the dialog's settings into the selected target. A type or format writing another
## kind of file changes the extension of its path.
func _changed() -> void:
	if _updating or _targets.is_empty():
		return
	var target := get_target()
	var extension := target.options.get_file_extension()
	target.options = _options()
	target.path = output.path
	if target.options.get_file_extension() != extension:
		target.path = ExportTarget.fit_path(target.path, target.options)
		if target.path != output.path:
			output.path = target.path
	_draft = false
	remove_target.disabled = false
	_update_item(_selected)
	_update_labels(target.options)


func _options() -> ExportOptions:
	var options := ExportTarget.create(Global.spritesheet).options
	options.target = TYPES[maxi(type.selected, 0)].target
	options.image_format = ExportOptions.IMAGE_FORMATS[maxi(image_format.selected, 0)]
	options.jpg_quality = jpg_quality.value / 100.0
	options.opaque_background = jpg_background.color
	options.background = background_picker.color
	# A pattern that was set is kept even when it's the default; emptied, it's the default,
	# which follows the sheet
	if pattern.text.strip_edges():
		if get_target().to_dictionary().has("sprite_name_pattern"):
			options.apply({"sprite_name_pattern": pattern.text})
		else:
			options.sprite_name_pattern = pattern.text
	options.only_selected = only_selected.button_pressed
	options.existing_files = existing.selected as ExportOptions.Existing
	options.animation_fps = animation_fps.value
	options.atlas_frame_size = frame_size.get_selected_id() as ExportOptions.FrameSize
	options.gif_every_animation = gif_animation.selected == EVERY_ANIMATION
	var named := gif_animation.selected > EVERY_ANIMATION
	options.gif_animation = gif_animation.get_item_text(gif_animation.selected) if named else ""
	animation_files.apply(options)
	scale_rows.apply(options)
	options.gif_scale = int(gif_scale.value)
	options.grid_data = _selected_format(grid_data)
	options.atlas_data = _selected_format(atlas_data)
	options.custom_template = template_file.path
	return options


## Opens the folder of the user's templates in the file manager, making it first
func open_templates_folder() -> void:
	AtlasFormats.prepare_user_dir()
	OS.shell_open(ProjectSettings.globalize_path(AtlasFormats.user_dir))


func _fill_list() -> void:
	target_list.clear()
	for i in _targets.size():
		target_list.add_item("")
		_update_item(i)


## Shows in the list where the target at [param index] writes, and what
func _update_item(index: int) -> void:
	var target := _targets[index]
	var file := get_target_file(target)
	target_list.set_item_text(index, describe_target(target))
	target_list.set_item_icon(index, get_type_icon(target.options.target))
	var full := target.path if target.path and not ExportController.in_browser else file
	target_list.set_item_tooltip(index, "%s\n%s" % [full, target.get_format_name()])


func _update_labels(options: ExportOptions) -> void:
	about.text = TYPES[_type_index(options.target)].about
	_update_visibility(options)

	var sheet := Global.spritesheet
	var index_start: int = Settings.get_value(&"index_start")
	var examples := PackedStringArray()
	for coord in SpritesheetExporter.get_example_coords(sheet):
		var example := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern, sheet, coord, index_start
		)
		if example + ".png" not in examples:
			examples.append(example + ".png")
	pattern_example.text = tr("For example: %s") % ", ".join(examples) if examples else ""
	transparent_label.visible = is_zero_approx(options.background.a)
	var files := _files(options)
	files_info.visible = files.size() > 1
	files_info.text = tr("Files: %s") % _list_files(files)
	animation_files.update(options, files)
	template_error.text = options.get_error()
	template_error.visible = template_error.text != ""
	get_ok_button().disabled = template_error.visible

	match options.target:
		T.SPRITES:
			output_info.text = (
				tr("%d images of %d×%d px")
				% [_sprite_coords(options).size(), sheet.sprite_size.x, sheet.sprite_size.y]
			)
		_ when options.packs(sheet):
			output_info.text = _atlas_info(options)
		T.GIF when options.gif_every_animation:
			var gif_size := sheet.sprite_size * options.gif_scale
			output_info.text = (tr("%d GIFs of %d×%d px") % [files.size(), gif_size.x, gif_size.y])
		T.STRIPS:
			var cell := sheet.sprite_size
			# At each scale
			var count := files.size() / options.get_scales().size()
			output_info.text = tr("%d strips of %d×%d px frames") % [count, cell.x, cell.y]
		T.GIF:
			var animation := options.get_gif_animation(sheet)
			var count := (
				animation.get_playback_cells(sheet).size() if animation else sheet.frames.size()
			)
			var gif_size := sheet.sprite_size * options.gif_scale
			output_info.text = tr("%d frames of %d×%d px") % [count, gif_size.x, gif_size.y]
		T.IMAGE when _is_packed():
			var sizes := PackedLayout.get_page_sizes(sheet)
			output_info.text = (
				tr("Image size: %d×%d px") % [sizes[0].x, sizes[0].y]
				if sizes.size() == 1
				else tr("%d images, the first %d×%d px") % [sizes.size(), sizes[0].x, sizes[0].y]
			)
		_:
			var image_size := SpritesheetExporter.get_image_size(sheet, options)
			output_info.text = tr("Image size: %d×%d px") % [image_size.x, image_size.y]
			var problem := ImageUtils.size_problem(image_size, options.get_file_extension())
			if problem:
				output_info.text = problem


func _update_visibility(options: ExportOptions) -> void:
	# A custom template has the settings of the export it's like, but its own template
	var like := [options.target]
	if options.target == T.CUSTOM:
		like.append(T.ATLAS if options.packs(Global.spritesheet) else T.DATA)
	for row in _rows:
		var shown: bool = row.targets.any(func(target: int) -> bool: return target in like)
		if row.format and options.image_format != row.format:
			shown = false
		if row.condition.is_valid() and not row.condition.call(options):
			shown = false
		for control: Control in row.controls:
			control.visible = shown
	if options.target == T.CUSTOM:
		for control in _format_rows:
			control.visible = false
	_pattern_label.text = "File names" if options.target == T.SPRITES else "Frame names"
	# Browsers download exports
	_output_label.visible = not ExportController.in_browser
	output.visible = _output_label.visible
	# Animations have their own speed; this one is for animations made from rows, and
	# for a GIF of every frame
	var own_speed := (
		options.target == T.GIF and (options.gif_animation != "" or options.gif_every_animation)
	)
	if not Global.spritesheet.animations.is_empty() and options.target != T.GIF or own_speed:
		_fps_label.visible = false
		animation_fps.visible = false


## Adds a labelled control shown only for [param for_targets] and, when given, only for
## the image [param format] and when [param condition] returns true for the options
func add_row(
	grid: GridContainer,
	text: String,
	control: Control,
	for_targets: Array,
	format := "",
	condition := Callable(),
) -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = control.tooltip_text
	label.custom_minimum_size.x = LABEL_WIDTH
	LabelLink.link(label, control)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	grid.add_child(control)
	(
		_rows
		. append(
			{
				"controls": [label, control],
				"targets": for_targets,
				"format": format,
				"condition": condition,
			}
		)
	)
	return label


## The files the selected target writes, as named when exporting to its path or else
## where it's suggested, see [method ExportController.suggested_path]
func _files(options: ExportOptions) -> PackedStringArray:
	var sheet := Global.spritesheet
	var coords := _sprite_coords(options)
	if sheet.is_empty() or options.target == T.SPRITES and coords.is_empty():
		return []
	var pages := -1
	if options.packs(sheet) and not _is_packed():
		# Packing the grid can take a while, so it's done once
		var turned := AtlasFormats.can_rotate(options.get_atlas_data())
		if not _atlas_pages.has(turned):
			_atlas_pages[turned] = ExportFiles.get_page_count(sheet, options)
		pages = _atlas_pages[turned]
	var path := ExportController.suggested_path(options)
	if output.path and not ExportController.in_browser:
		path = ExportTarget.fit_path(output.path, options)
	var index_start: int = Settings.get_value(&"index_start")
	return ExportFiles.get_paths(sheet, options, path, coords, index_start, false, pages)


## The frames a sprites export writes: the selected ones or every one
func _sprite_coords(options: ExportOptions) -> Array[Vector2i]:
	if options.only_selected:
		return get_selected_coords.call()
	return Global.spritesheet.get_sorted_coords()


## The names of [param paths]: the first few and how many more when there are many
func _list_files(paths: PackedStringArray) -> String:
	var names := PackedStringArray()
	for path in paths:
		names.append(path.get_file())
	if names.size() <= FILES_SHOWN:
		return ", ".join(names)
	var shown := names.slice(0, FILES_SHOWN - 1)
	return ", ".join(shown) + " " + tr("… %d more") % (names.size() - shown.size())


## What a packed atlas export will write, or why it can't
func _atlas_info(options: ExportOptions) -> String:
	var sheet := Global.spritesheet
	if not _is_packed():
		return tr("The size is found when packing")
	if not AtlasFormats.can_rotate(options.get_atlas_data()):
		for place: Dictionary in sheet.placements.values():
			if place.rotated:
				return tr("This format can't describe turned frames. Pack without turning them.")
	var sizes := PackedLayout.get_page_sizes(sheet)
	if sizes.is_empty():
		return ""
	if sizes.size() == 1:
		return tr("Atlas size: %d×%d px") % [sizes[0].x, sizes[0].y]
	return tr("%d pages, the first %d×%d px") % [sizes.size(), sizes[0].x, sizes[0].y]


## Lists in [param button] the formats that can describe [param layout], the user's own
## after the bundled ones, and selects [param selected]
static func _fill_formats(button: OptionButton, layout: String, selected: String) -> void:
	button.clear()
	var bundled := true
	for format in AtlasFormats.get_formats(layout):
		# The bundled ones come first
		if bundled and not AtlasFormats.is_bundled(format) and button.item_count > 0:
			button.add_separator()
		bundled = AtlasFormats.is_bundled(format)
		button.add_item(AtlasFormats.get_format_name(format))
		button.set_item_metadata(-1, format)
		if format == selected:
			button.select(button.item_count - 1)


## The id of the format selected in [param button], or else "json"
static func _selected_format(button: OptionButton) -> String:
	if button.selected < 0 or button.get_item_metadata(button.selected) == null:
		return "json"
	return button.get_item_metadata(button.selected)


static func _is_packed() -> bool:
	return Global.spritesheet.layout == Spritesheet.Layout.PACKED


## The name of the file [param target] writes, or that it has none yet
static func get_target_file(target: ExportTarget) -> String:
	if ExportController.in_browser:
		return ExportController.get_output_path(target).get_file()
	if target.path:
		return ExportTarget.fit_path(target.path, target.options).get_file()
	return TranslationServer.translate("No file picked yet")


## Where [param target] writes, and what, like "hero.png · PNG"
static func describe_target(target: ExportTarget) -> String:
	return "%s · %s" % [get_target_file(target), target.get_format_name()]


## The icon of exports of [param target]'s type
static func get_type_icon(target: ExportOptions.Target) -> Texture2D:
	return TYPES[_type_index(target)].icon


static func _type_index(target: ExportOptions.Target) -> int:
	for i in TYPES.size():
		if TYPES[i].target == target:
			return i
	return 0


static func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	return grid
