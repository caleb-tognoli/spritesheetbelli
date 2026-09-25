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
		"about": "The whole sheet as one PNG, JPG or WebP image.",
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
			+ "possible into a PNG, with a JSON file that says where each one is."
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
const LABEL_WIDTH := 170
const COLLAPSED_ICON := preload("res://assets/icons/GuiTreeArrowRight.svg")
const EXPANDED_ICON := preload("res://assets/icons/GuiTreeArrowDown.svg")

var targets := ItemList.new()
var about := Label.new()
var image_format := OptionButton.new()
var jpg_quality := SpinBox.new()
var jpg_background := ColorPickerButton.new()
var background_check := CheckBox.new()
var background_picker := ColorPickerButton.new()
var pattern := LineEdit.new()
var pattern_example := Label.new()
var only_selected := CheckBox.new()
var existing := OptionButton.new()
var animation_fps := SpinBox.new()
var advanced_toggle := Button.new()
var padding := SpinBox.new()
var spacing := SpinBox.new()
var extrude := SpinBox.new()
var power_of_two := CheckBox.new()
var gif_animation := OptionButton.new()
var gif_scale := SpinBox.new()
var output_info := Label.new()

var _settings := _grid()
var _advanced := _grid()
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

	var background_box := HBoxContainer.new()
	background_check.text = "Fill"
	background_check.tooltip_text = "Put a colour behind the sprites instead of transparency"
	background_picker.custom_minimum_size = Vector2(60, 0)
	background_box.add_child(background_check)
	background_box.add_child(background_picker)
	_add_row(_settings, "Background", background_box, [T.IMAGE, T.GODOT, T.JSON, T.GIF])
	gif_animation.tooltip_text = "Which animation the GIF plays"
	_add_row(_settings, "Animation", gif_animation, [T.GIF])
	gif_scale.min_value = 1
	gif_scale.max_value = 16
	gif_scale.suffix = "×"
	gif_scale.tooltip_text = "Makes the GIF bigger, keeping pixels sharp"
	_add_row(_settings, "Scale", gif_scale, [T.GIF])

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

	advanced_toggle.text = "Advanced"
	advanced_toggle.toggle_mode = true
	advanced_toggle.flat = true
	advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# No padding, so its arrow lines up with the labels
	for style: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		advanced_toggle.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	advanced_toggle.tooltip_text = "Padding, spacing and edge extrusion for game engines"
	right.add_child(advanced_toggle)
	right.add_child(_advanced)
	_add_spin(padding, "Padding", "Empty pixels around the whole sheet", [T.IMAGE, T.GODOT, T.JSON])
	_add_spin(
		spacing, "Spacing", "Empty pixels between frames", [T.IMAGE, T.GODOT, T.JSON, T.ATLAS]
	)
	_add_spin(
		extrude,
		"Extrude edges",
		(
			"Repeats each frame's edge pixels outward, so scaled or filtered sprites "
			+ "don't pick up their neighbours' colours"
		),
		[T.IMAGE, T.GODOT, T.JSON, T.ATLAS]
	)
	power_of_two.text = "Power-of-two size"
	power_of_two.tooltip_text = "Makes the atlas 256, 512, 1024… px wide and tall"
	_add_row(_advanced, "", power_of_two, [T.ATLAS])

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	output_info.theme_type_variation = &"StatusLabel"
	right.add_child(output_info)

	targets.item_selected.connect(_changed.unbind(1))
	image_format.item_selected.connect(_changed.unbind(1))
	advanced_toggle.toggled.connect(func(_on: bool) -> void: _update_visibility(_options()))
	background_check.toggled.connect(_changed.unbind(1))
	background_picker.color_changed.connect(_changed.unbind(1))
	pattern.text_changed.connect(_changed.unbind(1))
	only_selected.toggled.connect(_changed.unbind(1))
	existing.item_selected.connect(_changed.unbind(1))
	power_of_two.toggled.connect(_changed.unbind(1))
	gif_animation.item_selected.connect(_changed.unbind(1))
	for spin: SpinBox in [jpg_quality, animation_fps, padding, spacing, extrude, gif_scale]:
		spin.value_changed.connect(_changed.unbind(1))
	jpg_background.color_changed.connect(_changed.unbind(1))
	confirmed.connect(_on_confirmed)


func _ready() -> void:
	about_to_popup.connect(refresh)
	for spin: SpinBox in [jpg_quality, animation_fps, padding, spacing, extrude, gif_scale]:
		spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		SpinScroll.enable(spin)


## Shows the sheet's export settings
func refresh() -> void:
	_updating = true
	var options := ExportOptions.from_sheet(Global.spritesheet)
	targets.select(_target_index(options.target))
	targets.ensure_current_is_visible()
	image_format.select(ExportOptions.IMAGE_FORMATS.find(options.image_format))
	jpg_quality.set_value_no_signal(roundi(options.jpg_quality * 100))
	jpg_background.color = options.opaque_background
	background_check.button_pressed = options.background.a > 0
	background_picker.color = options.background if options.background.a > 0 else Color.BLACK
	pattern.text = options.sprite_name_pattern
	only_selected.button_pressed = options.only_selected
	existing.select(options.existing_files)
	animation_fps.set_value_no_signal(options.animation_fps)
	padding.set_value_no_signal(options.padding)
	spacing.set_value_no_signal(options.spacing)
	extrude.set_value_no_signal(options.extrude)
	power_of_two.set_pressed_no_signal(options.power_of_two)
	gif_animation.clear()
	gif_animation.add_item("All frames")
	for animation in Global.spritesheet.animations:
		gif_animation.add_item(animation.name)
		if animation.name == options.gif_animation:
			gif_animation.select(gif_animation.item_count - 1)
	gif_scale.set_value_no_signal(options.gif_scale)
	advanced_toggle.button_pressed = (
		options.padding or options.spacing or options.extrude or options.power_of_two
	)
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
	options.background = (
		background_picker.color if background_check.button_pressed else Color(0, 0, 0, 0)
	)
	options.sprite_name_pattern = pattern.text if pattern.text.strip_edges() else "{index}"
	options.only_selected = only_selected.button_pressed
	options.existing_files = existing.selected as ExportOptions.Existing
	options.animation_fps = animation_fps.value
	options.padding = int(padding.value)
	options.spacing = int(spacing.value)
	options.extrude = int(extrude.value)
	options.power_of_two = power_of_two.button_pressed
	options.gif_animation = (
		gif_animation.get_item_text(gif_animation.selected) if gif_animation.selected > 0 else ""
	)
	options.gif_scale = int(gif_scale.value)
	return options


## Saves the choices with the sheet (one undoable step) and the JPG ones as settings
func _on_confirmed() -> void:
	var options := _options()
	Settings.set_value(&"jpg_quality", options.jpg_quality)
	Settings.set_value(&"jpg_background", options.opaque_background)
	var sheet := Global.spritesheet
	if options.to_dictionary() != sheet.export_settings:
		Global.document.perform(
			"Export settings", sheet.set_export_settings.bind(options.to_dictionary())
		)
	export_requested.emit()


func _update_labels(options: ExportOptions) -> void:
	about.text = TARGETS[_target_index(options.target)].about
	background_picker.disabled = not background_check.button_pressed
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
			output_info.text = tr("The size is found when packing")
		T.GIF:
			var animation := options.get_gif_animation(sheet)
			var count := (
				animation.get_playback_cells(sheet).size() if animation else sheet.frames.size()
			)
			var gif_size := sheet.sprite_size * options.gif_scale
			output_info.text = tr("%d frames of %d×%d px") % [count, gif_size.x, gif_size.y]
		_:
			var image_size := SpritesheetExporter.get_image_size(sheet, options)
			output_info.text = tr("Image size: %d×%d px") % [image_size.x, image_size.y]
			var problem := ImageUtils.size_problem(image_size, options.get_file_extension())
			if problem:
				output_info.text = problem


func _update_visibility(options: ExportOptions) -> void:
	var any_advanced := false
	for row in _rows:
		var shown: bool = options.target in row.targets
		if row.format and options.image_format != row.format:
			shown = false
		if row.advanced:
			any_advanced = any_advanced or shown
			shown = shown and advanced_toggle.button_pressed
		for control: Control in row.controls:
			control.visible = shown
	_pattern_label.text = "File names" if options.target == T.SPRITES else "Frame names"
	# Animations have their own speed; this one is for animations made from rows, and
	# for a GIF of every frame
	var own_speed := options.target == T.GIF and options.gif_animation != ""
	if not Global.spritesheet.animations.is_empty() and options.target != T.GIF or own_speed:
		_fps_label.visible = false
		animation_fps.visible = false
	advanced_toggle.visible = any_advanced
	advanced_toggle.icon = EXPANDED_ICON if advanced_toggle.button_pressed else COLLAPSED_ICON


## Adds a labelled control shown only for [param for_targets] and, when given, only for
## the image [param format]
func _add_row(
	grid: GridContainer, text: String, control: Control, for_targets: Array, format := ""
) -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = control.tooltip_text
	# The same label width in both grids lines their controls up
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
				"advanced": grid == _advanced,
			}
		)
	)
	return label


func _add_spin(spin: SpinBox, text: String, tip: String, for_targets: Array) -> void:
	spin.max_value = 256
	spin.suffix = "px"
	spin.tooltip_text = tip
	_add_row(_advanced, text, spin, for_targets)


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
