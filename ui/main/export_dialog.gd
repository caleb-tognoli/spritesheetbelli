class_name ExportDialog
extends ConfirmationDialog
## Asks what to export and shows only the settings that matter for it. The choices are
## saved with the project; confirming emits [signal export_requested] to pick where.

signal export_requested

const T := ExportOptions.Target
const TARGETS := [
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
		"icon": preload("res://assets/icons/Folder.svg"),
		"about": "Every frame as its own PNG, in a folder.",
	},
	{
		"target": T.GODOT,
		"name": "Godot SpriteFrames",
		"icon": preload("res://assets/icons/SpriteFrames.svg"),
		"about":
		(
			"The sheet as a PNG and a SpriteFrames resource (.tres) next to it, "
			+ "ready for an AnimatedSprite2D. Each animation becomes one."
		),
	},
	{
		"target": T.JSON,
		"name": "Aseprite / TexturePacker JSON",
		"icon": preload("res://assets/icons/FileList.svg"),
		"about":
		(
			"The sheet as a PNG and a JSON file next to it with every frame and "
			+ "the animations as frame tags. Most engines and tools can read it."
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
			"One animation as a GIF, to share or put on a page. GIF has no partial "
			+ "transparency and at most 255 colours; sheets with more are reduced."
		),
	},
]
const PATTERN_HELP := (
	"Tokens: {index} {row} {column} {row_name} {frame} {name}\n"
	+ "Add :3 to pad numbers, e.g. {index:3} gives 007"
)
## What a sheet in the packed layout can be exported as
const PACKED_TARGETS: Array[ExportOptions.Target] = [
	ExportOptions.Target.IMAGE,
	ExportOptions.Target.ATLAS,
	ExportOptions.Target.SPRITES,
	ExportOptions.Target.GIF,
]
const LABEL_WIDTH := 170

var targets := ItemList.new()
var about := Label.new()
var image_format := OptionButton.new()
var jpg_quality := SpinBox.new()
var jpg_background := ColorPickerButton.new()
var background_picker := ColorPickerButton.new()
var pattern := LineEdit.new()
var pattern_example := Label.new()
var only_selected := CheckBox.new()
var existing := OptionButton.new()
var animation_fps := SpinBox.new()
var frame_size := OptionButton.new()
var atlas_data := OptionButton.new()
var gif_animation := OptionButton.new()
var gif_scale := SpinBox.new()
var output_info := Label.new()

var _settings := _grid()
## Controls of each row, with the targets they're shown for
var _rows: Array[Dictionary] = []
var _pattern_label: Label
var _fps_label: Label
var _updating := false


func _init() -> void:
	title = "Export"
	ok_button_text = "Export…"
	# Big enough for every export type, so it doesn't change size when switching
	min_size = Vector2i(760, 470)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	add_child(layout)

	targets.custom_minimum_size = Vector2(250, 280)
	targets.fixed_icon_size = Vector2i(16, 16)
	for entry: Dictionary in TARGETS:
		targets.add_item(entry.name, entry.icon)
	layout.add_child(targets)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	layout.add_child(right)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapped label needs a width, or it's measured one word per line
	about.custom_minimum_size = Vector2(380, 0)
	about.theme_type_variation = &"StatusLabel"
	right.add_child(about)
	right.add_child(_settings)

	for format: String in ExportOptions.IMAGE_FORMATS:
		image_format.add_item(format.to_upper())
	_add_row(_settings, "Format", image_format, [T.IMAGE])
	jpg_quality.min_value = 1
	jpg_quality.max_value = 100
	jpg_quality.suffix = "%"
	_add_row(_settings, "JPG quality", jpg_quality, [T.IMAGE], "jpg")
	jpg_background.edit_alpha = false
	jpg_background.custom_minimum_size = Vector2(60, 0)
	jpg_background.tooltip_text = "JPG has no transparency, so transparent areas get this colour"
	_add_row(_settings, "Fill transparency with", jpg_background, [T.IMAGE], "jpg")

	background_picker.tooltip_text = (
		"A colour behind the sprites. Fully transparent (the default) leaves the "
		+ "background transparent."
	)
	background_picker.custom_minimum_size = Vector2(60, 0)
	_add_row(_settings, "Background", background_picker, [T.IMAGE, T.GODOT, T.JSON, T.GIF])
	gif_animation.tooltip_text = "Which animation the GIF plays"
	_add_row(_settings, "Animation", gif_animation, [T.GIF])
	gif_scale.min_value = 1
	gif_scale.max_value = 16
	gif_scale.suffix = "×"
	gif_scale.tooltip_text = "Makes the GIF bigger, keeping pixels sharp"
	_add_row(_settings, "Scale", gif_scale, [T.GIF])
	for format: String in AtlasFormats.FORMATS:
		atlas_data.add_item(AtlasFormats.FORMATS[format].name)
	atlas_data.tooltip_text = "The file next to the atlas that says where each frame is"
	_add_row(_settings, "Data file", atlas_data, [T.ATLAS])
	frame_size.add_item("Their cell", ExportOptions.FrameSize.CELL)
	frame_size.add_item("Their own", ExportOptions.FrameSize.FRAME)
	frame_size.tooltip_text = (
		"The size the data file gives each frame, which engines line frames up by.\n"
		+ "Their cell: the frames of an animation line up like in the grid, even when "
		+ "trimmed or of different sizes.\n"
		+ "Their own: each frame is as big as it is, for sprites that have nothing to do "
		+ "with each other."
	)
	_add_row(_settings, "Frame size in data", frame_size, [T.ATLAS])

	animation_fps.min_value = 1
	animation_fps.max_value = 120
	animation_fps.step = 0.5
	animation_fps.suffix = "fps"
	animation_fps.tooltip_text = "Frames per second of the animations"
	_fps_label = _add_row(_settings, "Animation speed", animation_fps, [T.GODOT, T.JSON, T.GIF])

	pattern.custom_minimum_size = Vector2(200, 0)
	pattern.placeholder_text = "{index}"
	pattern.tooltip_text = PATTERN_HELP
	_pattern_label = _add_row(_settings, "File names", pattern, [T.SPRITES, T.JSON, T.ATLAS])
	pattern_example.theme_type_variation = &"StatusLabel"
	_add_row(_settings, "", pattern_example, [T.SPRITES, T.JSON, T.ATLAS])
	only_selected.text = "Only selected frames"
	_add_row(_settings, "", only_selected, [T.SPRITES])
	for label: String in ["Add a number", "Overwrite it", "Skip the sprite"]:
		existing.add_item(label)
	_add_row(_settings, "When a file exists", existing, [T.SPRITES])

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	output_info.theme_type_variation = &"StatusLabel"
	right.add_child(output_info)

	targets.item_selected.connect(_changed.unbind(1))
	image_format.item_selected.connect(_changed.unbind(1))
	background_picker.color_changed.connect(_changed.unbind(1))
	pattern.text_changed.connect(_changed.unbind(1))
	only_selected.toggled.connect(_changed.unbind(1))
	existing.item_selected.connect(_changed.unbind(1))
	frame_size.item_selected.connect(_changed.unbind(1))
	gif_animation.item_selected.connect(_changed.unbind(1))
	atlas_data.item_selected.connect(_changed.unbind(1))
	for spin: SpinBox in [jpg_quality, animation_fps, gif_scale]:
		spin.value_changed.connect(_changed.unbind(1))
	jpg_background.color_changed.connect(_changed.unbind(1))
	confirmed.connect(_on_confirmed)


func _ready() -> void:
	about_to_popup.connect(refresh)
	for spin: SpinBox in [jpg_quality, animation_fps, gif_scale]:
		spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		SpinScroll.enable(spin)


## Shows the sheet's export settings
func refresh() -> void:
	_updating = true
	var options := ExportOptions.from_sheet(Global.spritesheet)
	# A packed sheet is exported as it's packed, not as a grid
	var packed := _is_packed()
	for i in TARGETS.size():
		var grid_only: bool = TARGETS[i].target not in PACKED_TARGETS
		targets.set_item_disabled(i, packed and grid_only)
		targets.set_item_tooltip(i, tr("Only in the grid layout") if packed and grid_only else "")
	# Packed sheets are usually exported as atlases, until another export is picked
	var chosen: bool = Global.spritesheet.export_settings.has("target")
	if packed and (options.target not in PACKED_TARGETS or not chosen):
		options.target = T.ATLAS
	targets.select(_target_index(options.target))
	targets.ensure_current_is_visible()
	image_format.select(ExportOptions.IMAGE_FORMATS.find(options.image_format))
	jpg_quality.set_value_no_signal(roundi(options.jpg_quality * 100))
	jpg_background.color = options.opaque_background
	background_picker.color = options.background
	pattern.text = options.sprite_name_pattern
	only_selected.button_pressed = options.only_selected
	existing.select(options.existing_files)
	animation_fps.set_value_no_signal(options.animation_fps)
	frame_size.select(frame_size.get_item_index(options.atlas_frame_size))
	gif_animation.clear()
	gif_animation.add_item("All frames")
	for animation in Global.spritesheet.animations:
		gif_animation.add_item(animation.name)
		if animation.name == options.gif_animation:
			gif_animation.select(gif_animation.item_count - 1)
	gif_scale.set_value_no_signal(options.gif_scale)
	atlas_data.select(AtlasFormats.FORMATS.keys().find(options.atlas_data))
	_updating = false
	_update_labels(options)


## Selects what to export
func select_target(target: ExportOptions.Target) -> void:
	targets.select(_target_index(target))
	_changed()


## The options as set in the dialog
func get_options() -> ExportOptions:
	return _options()


func _changed() -> void:
	if not _updating:
		_update_labels(_options())


func _options() -> ExportOptions:
	var options := ExportOptions.from_sheet(Global.spritesheet)
	var selected := targets.get_selected_items()
	if not selected.is_empty():
		options.target = TARGETS[selected[0]].target
	options.image_format = ExportOptions.IMAGE_FORMATS[maxi(image_format.selected, 0)]
	options.jpg_quality = jpg_quality.value / 100.0
	options.opaque_background = jpg_background.color
	options.background = background_picker.color
	options.sprite_name_pattern = pattern.text if pattern.text.strip_edges() else "{index}"
	options.only_selected = only_selected.button_pressed
	options.existing_files = existing.selected as ExportOptions.Existing
	options.animation_fps = animation_fps.value
	options.atlas_frame_size = frame_size.get_selected_id() as ExportOptions.FrameSize
	options.gif_animation = (
		gif_animation.get_item_text(gif_animation.selected) if gif_animation.selected > 0 else ""
	)
	options.gif_scale = int(gif_scale.value)
	options.atlas_data = AtlasFormats.FORMATS.keys()[maxi(atlas_data.selected, 0)]
	return options


## Saves the choices with the sheet (one undoable step) and the JPG ones as settings
func _on_confirmed() -> void:
	var options := _options()
	Settings.set_value(&"jpg_quality", options.jpg_quality)
	Settings.set_value(&"jpg_background", options.opaque_background)
	var sheet := Global.spritesheet
	var settings := options.to_dictionary()
	# Kept even when it's the default, so the choice is remembered
	settings.target = options.target
	if settings != sheet.export_settings:
		Global.document.perform("Export settings", sheet.set_export_settings.bind(settings))
	export_requested.emit()


func _update_labels(options: ExportOptions) -> void:
	about.text = TARGETS[_target_index(options.target)].about
	_update_visibility(options)

	var sheet := Global.spritesheet
	var coords := sheet.get_sorted_coords()
	pattern_example.text = ""
	if not coords.is_empty():
		var example := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern,
			sheet,
			coords[mini(1, coords.size() - 1)],
			Settings.get_value(&"index_start")
		)
		pattern_example.text = tr("For example: %s.png") % example

	match options.target:
		T.SPRITES:
			output_info.text = (
				tr("%d images of %d×%d px")
				% [sheet.frames.size(), sheet.sprite_size.x, sheet.sprite_size.y]
			)
		T.ATLAS:
			output_info.text = _atlas_info(options)
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
	for row in _rows:
		var shown: bool = options.target in row.targets
		if row.format and options.image_format != row.format:
			shown = false
		for control: Control in row.controls:
			control.visible = shown
	_pattern_label.text = "File names" if options.target == T.SPRITES else "Frame names"
	# Animations have their own speed; this one is for animations made from rows, and
	# for a GIF of every frame
	var own_speed := options.target == T.GIF and options.gif_animation != ""
	if not Global.spritesheet.animations.is_empty() and options.target != T.GIF or own_speed:
		_fps_label.visible = false
		animation_fps.visible = false


## Adds a labelled control shown only for [param for_targets] and, when given, only for
## the image [param format]
func _add_row(
	grid: GridContainer, text: String, control: Control, for_targets: Array, format := ""
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
			}
		)
	)
	return label


## What a packed atlas export will write, or why it can't
func _atlas_info(options: ExportOptions) -> String:
	var sheet := Global.spritesheet
	if not _is_packed():
		return tr("The size is found when packing")
	if not AtlasFormats.can_rotate(options.atlas_data):
		for place: Dictionary in sheet.placements.values():
			if place.rotated:
				return tr("This format can't describe turned frames. Pack without turning them.")
	var sizes := PackedLayout.get_page_sizes(sheet)
	if sizes.is_empty():
		return ""
	if sizes.size() == 1:
		return tr("Atlas size: %d×%d px") % [sizes[0].x, sizes[0].y]
	return tr("%d pages, the first %d×%d px") % [sizes.size(), sizes[0].x, sizes[0].y]


static func _is_packed() -> bool:
	return Global.spritesheet.layout == Spritesheet.Layout.PACKED


static func _target_index(target: ExportOptions.Target) -> int:
	for i in TARGETS.size():
		if TARGETS[i].target == target:
			return i
	return 0


static func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	return grid
