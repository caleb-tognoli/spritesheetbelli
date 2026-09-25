class_name ShortcutsDialog
extends AcceptDialog
## Lists every menu action with its keyboard shortcut.

var _grid := GridContainer.new()


func _init() -> void:
	title = "Keyboard Shortcuts"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 24)
	scroll.add_child(_grid)
	add_child(scroll)
	about_to_popup.connect(_fill)


func _fill() -> void:
	for child in _grid.get_children():
		child.free()
	for menu: String in MainMenuBar.MENUS:
		_add_row(menu, "", true)
		for id: StringName in MainMenuBar.MENUS[menu]:
			if not id.is_empty() and Actions.has(id):
				_add_row(
					Actions.get_action(id).label.trim_suffix("…"), Actions.get_shortcut_text(id)
				)
	_add_row("Preview", "", true)
	_add_row("Pan", "Middle mouse drag")
	_add_row("Zoom", "Mouse wheel")
	_add_row("Select frames", "Click or drag")
	_add_row("Move frames in their cells", "Alt+Arrow keys")


func _add_row(text: String, shortcut: String, heading := false) -> void:
	var label := Label.new()
	label.text = text
	var keys := Label.new()
	keys.text = shortcut
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if heading:
		label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	_grid.add_child(label)
	_grid.add_child(keys)
