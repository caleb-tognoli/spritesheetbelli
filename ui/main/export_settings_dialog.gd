class_name ExportSettingsDialog
extends AcceptDialog
## Edits how the open spritesheet is exported. Changes are saved with the project
## and can be undone.

const PATTERN_HELP := (
	"Tokens: {index} {row} {column} {row_name} {frame} {name}\n"
	+ "Add :3 to pad numbers, e.g. {index:3} gives 007"
)

var background_check := CheckBox.new()
var background_picker := ColorPickerButton.new()
var image_size := Label.new()
var pattern := LineEdit.new()
var pattern_example := Label.new()
var only_selected := CheckBox.new()
var existing := OptionButton.new()
var metadata := OptionButton.new()
var animation_fps := SpinBox.new()
var advanced_toggle := CheckButton.new()
var padding := SpinBox.new()
var spacing := SpinBox.new()
var extrude := SpinBox.new()

var _advanced := GridContainer.new()
var _updating := false


func _init() -> void:
	title = "Export Settings"
	ok_button_text = "Close"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	box.add_child(_heading("Image"))
	var image := _grid()
	box.add_child(image)
	background_check.text = "Fill background"
	background_check.tooltip_text = "Put a colour behind the sprites instead of transparency"
	background_picker.custom_minimum_size = Vector2(60, 0)
	image.add_child(background_check)
	image.add_child(background_picker)
	image.add_child(_label("Image size"))
	image.add_child(image_size)

	box.add_child(_heading("Sprites (Export Sprites)"))
	var sprites := _grid()
	box.add_child(sprites)
	sprites.add_child(_label("File name"))
	pattern.custom_minimum_size = Vector2(220, 0)
	pattern.placeholder_text = "{index}"
	pattern.tooltip_text = PATTERN_HELP
	sprites.add_child(pattern)
	sprites.add_child(Control.new())
	pattern_example.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sprites.add_child(pattern_example)
	only_selected.text = "Only selected frames"
	sprites.add_child(only_selected)
	sprites.add_child(Control.new())
	sprites.add_child(_label("When a file exists"))
	for label: String in ["Add a number", "Overwrite it", "Skip the sprite"]:
		existing.add_item(label)
	sprites.add_child(existing)

	box.add_child(_heading("Metadata (Export Image)"))
	var meta := _grid()
	box.add_child(meta)
	meta.add_child(_label("Also write"))
	for label: String in [
		"Nothing", "JSON (TexturePacker, Aseprite tags)", "Godot SpriteFrames (.tres)"
	]:
		metadata.add_item(label)
	metadata.tooltip_text = "A file next to the image that tells game engines where each frame is"
	meta.add_child(metadata)
	meta.add_child(_label("Animation speed"))
	animation_fps.min_value = 1
	animation_fps.max_value = 120
	animation_fps.step = 0.5
	animation_fps.suffix = "fps"
	animation_fps.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	animation_fps.tooltip_text = "Frames per second. Each named row is one animation."
	meta.add_child(animation_fps)

	advanced_toggle.text = "Advanced options"
	advanced_toggle.tooltip_text = "Padding, spacing and edge extrusion for game engines"
	box.add_child(advanced_toggle)
	_advanced.columns = 2
	_advanced.visible = false
	_advanced.add_theme_constant_override("h_separation", 24)
	box.add_child(_advanced)
	_add_spin(padding, "Padding", "Empty pixels around the whole sheet")
	_add_spin(spacing, "Spacing", "Empty pixels between cells")
	_add_spin(
		extrude,
		"Extrude edges",
		(
			"Repeats each frame's edge pixels outward, so scaled or filtered sprites "
			+ "don't pick up their neighbours' colours"
		)
	)

	advanced_toggle.toggled.connect(func(on: bool) -> void: _advanced.visible = on)
	background_check.toggled.connect(_changed.unbind(1))
	background_picker.color_changed.connect(_changed.unbind(1))
	# The pattern is applied when done typing, so each key isn't an undo step
	pattern.text_changed.connect(
		func(_text: String) -> void: _update_labels(_options_from_controls())
	)
	pattern.text_submitted.connect(_changed.unbind(1))
	pattern.focus_exited.connect(_changed)
	only_selected.toggled.connect(_changed.unbind(1))
	existing.item_selected.connect(_changed.unbind(1))
	metadata.item_selected.connect(_changed.unbind(1))
	animation_fps.value_changed.connect(_changed.unbind(1))
	for spin: SpinBox in [padding, spacing, extrude]:
		spin.value_changed.connect(_changed.unbind(1))


func _ready() -> void:
	about_to_popup.connect(refresh)
	Global.spritesheet.updated.connect(
		func() -> void:
			if visible:
				refresh()
	)


## Shows the sheet's current export settings
func refresh() -> void:
	_updating = true
	var options := ExportOptions.from_sheet(Global.spritesheet)
	background_check.button_pressed = options.background.a > 0
	background_picker.color = options.background if options.background.a > 0 else Color.BLACK
	background_picker.disabled = not background_check.button_pressed
	if not pattern.has_focus():
		pattern.text = options.sprite_name_pattern
	only_selected.button_pressed = options.only_selected
	existing.select(options.existing_files)
	metadata.select(options.metadata)
	animation_fps.set_value_no_signal(options.animation_fps)
	animation_fps.editable = options.metadata != ExportOptions.MetadataFormat.NONE
	padding.set_value_no_signal(options.padding)
	spacing.set_value_no_signal(options.spacing)
	extrude.set_value_no_signal(options.extrude)
	if options.padding or options.spacing or options.extrude:
		advanced_toggle.button_pressed = true
	_update_labels(options)
	_updating = false


func _changed() -> void:
	if _updating:
		return
	var options := _options_from_controls()
	background_picker.disabled = not background_check.button_pressed
	Global.document.perform(
		"Export settings", Global.spritesheet.set_export_settings.bind(options.to_dictionary())
	)
	_update_labels(options)


func _options_from_controls() -> ExportOptions:
	var options := ExportOptions.new()
	if background_check.button_pressed:
		options.background = background_picker.color
	options.sprite_name_pattern = pattern.text if pattern.text.strip_edges() else "{index}"
	options.only_selected = only_selected.button_pressed
	options.existing_files = existing.selected as ExportOptions.Existing
	options.metadata = metadata.selected as ExportOptions.MetadataFormat
	options.animation_fps = animation_fps.value
	options.padding = int(padding.value)
	options.spacing = int(spacing.value)
	options.extrude = int(extrude.value)
	return options


func _update_labels(options: ExportOptions) -> void:
	var sheet := Global.spritesheet
	var size := SpritesheetExporter.get_image_size(sheet, options)
	image_size.text = "%d×%d px" % [size.x, size.y]
	var coords := sheet.get_sorted_coords()
	if coords.is_empty():
		pattern_example.text = ""
	else:
		var example := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern,
			sheet,
			coords[mini(1, coords.size() - 1)],
			Settings.get_value(&"index_start")
		)
		pattern_example.text = tr("For example: %s.png") % example


func _add_spin(spin: SpinBox, text: String, tip: String) -> void:
	var label := _label(text)
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	spin.max_value = 256
	spin.suffix = "px"
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spin.tooltip_text = tip
	_advanced.add_child(label)
	_advanced.add_child(spin)


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	return label


static func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


static func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	return grid
