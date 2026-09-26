class_name SettingsWindow
extends AcceptDialog
## Edits [code]Settings[/code] like Godot's Editor Settings: categories on the left, their
## settings on the right, and a search over all of them. Changes apply immediately; a
## setting that differs from its default has a button to revert it.

## Categories with rows of [key, label, control type, options...]
const CATEGORIES := [
	[
		"General",
		[
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
			[&"watch_sources", "Ask to reload sprites when their image files change", "check"],
			[&"use_pivots", "Set pivots: the point engines anchor each frame at", "check"],
			[&"confirm_grid_shrink", "Ask before shrinking the grid deletes sprites", "check"],
			[&"restore_session", "Reopen the last project on start", "check"],
		]
	],
	[
		"Preview",
		[
			[&"index_start", "Number frames from", "option", ["0", "1"]],
			[&"show_grid", "Show grid", "check"],
			[&"show_indices", "Show frame numbers", "check"],
			[&"show_checkerboard", "Show checkerboard behind sprites", "check"],
			[&"grid_color", "Grid colour", "color"],
			[&"background_color", "Background colour", "color"],
			[&"checker_size", "Checkerboard square size", "spin", [2, 64, 1, "px"]],
			[&"zoom_speed", "Zoom speed", "spin", [0.05, 1.0, 0.05, ""]],
		]
	],
	[
		"Export",
		[
			[&"jpg_quality", "JPG quality", "spin", [0.1, 1.0, 0.05, ""]],
			[&"jpg_background", "JPG background (replaces transparency)", "color"],
		]
	],
	[
		"Atlas",
		[
			[&"atlas_dedupe", "Pack frames that look the same once, sharing their place", "check"],
			[&"atlas_power_of_two", "Power-of-two pages (256, 512, 1024… px)", "check"],
			[&"atlas_square", "Square pages", "check"],
		]
	],
	[
		"Interface",
		[
			[&"theme", "Theme", "option", ["Dark", "Light"], ["dark", "light"]],
			[&"accent_color", "Accent colour", "color"],
			[
				&"ui_scale",
				"Interface scale",
				"option",
				["Automatic", "75%", "100%", "125%", "150%", "200%"],
				[0.0, 0.75, 1.0, 1.25, 1.5, 2.0]
			],
			[&"show_status_bar", "Show the status bar", "check"],
		]
	],
]
const REVERT_ICON := preload("res://assets/icons/Reload.svg")
const SEARCH_ICON := preload("res://assets/icons/Search.svg")

var categories := ItemList.new()
var search := LineEdit.new()

var _list := VBoxContainer.new()
## Each setting's row: key, category, label text, the row and its revert button
var _rows: Array[Dictionary] = []
var _headers: Array[Label] = []
## Refreshes each control from its setting, by key
var _refreshers: Dictionary[StringName, Callable] = {}
var _category := "General"


func _init() -> void:
	title = "Settings"
	ok_button_text = "Close"
	min_size = Vector2i(760, 500)
	var reset := add_button("Reset All…", true, "reset")
	reset.tooltip_text = "Restore every setting to its default"
	custom_action.connect(
		func(_action: StringName) -> void:
			Notify.confirm(
				"Reset settings",
				"Restore every setting to its default?",
				Settings.reset_to_defaults,
				"Reset"
			)
	)

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(190, 0)
	layout.add_child(left)
	search.placeholder_text = "Filter settings"
	search.right_icon = SEARCH_ICON
	search.clear_button_enabled = true
	left.add_child(search)
	categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(categories)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_build()

	categories.item_selected.connect(
		func(index: int) -> void:
			_category = categories.get_item_text(index)
			search.text = ""
			_filter()
	)
	search.text_changed.connect(func(_text: String) -> void: _filter())


func _ready() -> void:
	Settings.changed.connect(_refresh)
	about_to_popup.connect(func() -> void: _refresh(&""))
	_filter()


## Shows the settings of [param category]
func show_category(category: String) -> void:
	_category = category
	search.text = ""
	_filter()


## The control that edits the setting [param key]
func get_control(key: StringName) -> Control:
	for row in _rows:
		if row.key == key:
			return row.control
	return null


## The button that reverts the setting [param key] to its default
func get_revert_button(key: StringName) -> Button:
	for row in _rows:
		if row.key == key:
			return row.revert
	return null


func _build() -> void:
	for category: Array in CATEGORIES:
		var category_name: String = category[0]
		categories.add_item(category_name)
		var header := Label.new()
		header.text = category_name
		header.theme_type_variation = &"HeaderSmall"
		_list.add_child(header)
		_headers.append(header)
		for row: Array in category[1]:
			_add_row(category_name, row)


func _add_row(category: String, row: Array) -> void:
	var key: StringName = row[0]
	var box := HBoxContainer.new()
	box.custom_minimum_size.y = 32
	box.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = row[1]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapped label needs a width, or it's measured one word per line
	label.custom_minimum_size = Vector2(220, 0)
	box.add_child(label)
	var control := _create_control(key, row[2], row.slice(3))
	LabelLink.link(label, control)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = row[1]
	box.add_child(control)
	var revert := Button.new()
	revert.icon = REVERT_ICON
	revert.flat = true
	revert.tooltip_text = "Revert to the default"
	revert.pressed.connect(func() -> void: Settings.set_value(key, Settings.DEFAULTS[key]))
	# Keeps the row's width when hidden, so controls don't jump
	var revert_slot := Control.new()
	revert_slot.custom_minimum_size = Vector2(28, 0)
	revert_slot.add_child(revert)
	box.add_child(revert_slot)
	_list.add_child(box)
	_rows.append(
		{
			"key": key,
			"category": category,
			"text": row[1],
			"row": box,
			"control": control,
			"revert": revert
		}
	)


func _create_control(key: StringName, kind: String, options: Array) -> Control:
	match kind:
		"check":
			var check := CheckBox.new()
			check.text = "On"
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


## Shows the selected category, or every matching setting while searching
func _filter() -> void:
	var query := search.text.strip_edges().to_lower()
	# While searching, results come from every category
	categories.deselect_all()
	for i in categories.item_count:
		if not query and categories.get_item_text(i) == _category:
			categories.select(i)
	var category := _category
	var shown_categories := {}
	for row in _rows:
		var shown: bool = (
			query in (row.text as String).to_lower() if query else row.category == category
		)
		(row.row as Control).visible = shown
		if shown:
			shown_categories[row.category] = true
	# Headers only help when results come from several categories
	for header in _headers:
		header.visible = query and shown_categories.has(header.text)


func _refresh(key: StringName) -> void:
	for k in _refreshers:
		if key.is_empty() or k == key:
			_refreshers[k].call()
	for row in _rows:
		if key.is_empty() or row.key == key:
			var is_default: bool = Settings.get_value(row.key) == Settings.DEFAULTS[row.key]
			(row.revert as Button).visible = not is_default
