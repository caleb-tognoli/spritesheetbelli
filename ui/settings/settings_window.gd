class_name SettingsWindow
extends AcceptDialog
## Edits [code]Settings[/code]. Rows are built from [constant ROWS]; changes apply immediately.

## Section headings, and rows of [key, label, control type, options]
const ROWS := [
	"Adding sprites",
	[
		&"add_mode",
		"New sprites go to",
		"option",
		["The first free cell", "After the last frame", "A new row"]
	],
	[
		&"resize_filter",
		"Resize filter",
		"option",
		["Nearest (pixel art)", "Bilinear", "Cubic", "Trilinear", "Lanczos"]
	],
	"Preview",
	[&"index_start", "Number frames from", "option", ["0", "1"]],
	[&"show_grid", "Show grid", "check"],
	[&"show_indices", "Show frame numbers", "check"],
	[&"show_checkerboard", "Show checkerboard behind sprites", "check"],
	[&"grid_color", "Grid colour", "color"],
	[&"background_color", "Background colour", "color"],
	[&"checker_size", "Checkerboard square size", "spin", [2, 64, 1, "px"]],
	[&"zoom_speed", "Zoom speed", "spin", [0.05, 1.0, 0.05, ""]],
	"Export",
	[&"jpg_quality", "JPG quality", "spin", [0.1, 1.0, 0.05, ""]],
	[&"jpg_background", "JPG background (replaces transparency)", "color"],
	"Interface",
	[
		&"ui_scale",
		"Interface scale",
		"option",
		["Automatic", "75%", "100%", "125%", "150%", "200%"],
		[0.0, 0.75, 1.0, 1.25, 1.5, 2.0]
	],
	[&"confirm_grid_shrink", "Ask before shrinking the grid deletes sprites", "check"],
	[&"restore_session", "Reopen the last project on start", "check"],
]

var _grid := GridContainer.new()
## Refreshes each control from its setting, by key
var _refreshers: Dictionary[StringName, Callable] = {}


func _init() -> void:
	title = "Settings"
	ok_button_text = "Close"
	var reset := add_button("Reset to Defaults", true, "reset")
	reset.tooltip_text = "Restores every setting to its default"
	custom_action.connect(func(_action: StringName) -> void: Settings.reset_to_defaults())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	add_child(scroll)
	_build()


func _ready() -> void:
	Settings.changed.connect(_refresh)
	about_to_popup.connect(func() -> void: _refresh(&""))


func _build() -> void:
	for row: Variant in ROWS:
		if row is String:
			var heading := Label.new()
			heading.text = row
			heading.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
			_grid.add_child(heading)
			_grid.add_child(Control.new())
			continue
		var key: StringName = row[0]
		var label := Label.new()
		label.text = row[1]
		_grid.add_child(label)
		var control := _create_control(key, row[2], row.slice(3))
		control.size_flags_horizontal = Control.SIZE_SHRINK_END
		control.tooltip_text = row[1]
		_grid.add_child(control)


func _create_control(key: StringName, kind: String, options: Array) -> Control:
	match kind:
		"check":
			var check := CheckBox.new()
			check.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
			_refreshers[key] = func() -> void: check.set_pressed_no_signal(Settings.get_value(key))
			return check
		"color":
			var picker := ColorPickerButton.new()
			picker.custom_minimum_size = Vector2(60, 0)
			picker.color_changed.connect(func(color: Color) -> void: Settings.set_value(key, color))
			_refreshers[key] = func() -> void: picker.color = Settings.get_value(key)
			return picker
		"spin":
			var spin := SpinBox.new()
			spin.min_value = options[0][0]
			spin.max_value = options[0][1]
			spin.step = options[0][2]
			spin.suffix = options[0][3]
			spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			spin.value_changed.connect(func(value: float) -> void: Settings.set_value(key, value))
			_refreshers[key] = func() -> void: spin.set_value_no_signal(Settings.get_value(key))
			return spin
		_:
			var option := OptionButton.new()
			var labels: Array = options[0]
			var values: Array = options[1] if options.size() > 1 else range(labels.size())
			for i in labels.size():
				option.add_item(labels[i])
			option.item_selected.connect(
				func(index: int) -> void: Settings.set_value(key, values[index])
			)
			_refreshers[key] = func() -> void:
				option.select(maxi(0, values.find(Settings.get_value(key))))
			return option


func _refresh(key: StringName) -> void:
	for k in _refreshers:
		if key.is_empty() or k == key:
			_refreshers[k].call()
