class_name ShortcutsDialog
extends AcceptDialog
## Lists every menu action with its keyboard shortcut, found by typing in the search field.

## Words for modifier keys, as typed in a search, and what shortcuts call them
const MODIFIERS := {
	"ctrl": "ctrl",
	"control": "ctrl",
	"shift": "shift",
	"alt": "alt",
	"option": "alt",
	"cmd": "command",
	"command": "command",
	"meta": "meta",
}

var search := LineEdit.new()
var _grid := GridContainer.new()
var _no_match := Label.new()
## Every row: its two labels, whether it's a heading, and for actions their keys, which a
## search matches as keys (see [method matches_key]) rather than as text
var _rows: Array[Dictionary] = []


func _init() -> void:
	title = "Keyboard Shortcuts"
	ok_button_text = "Close"
	DialogButtons.apply(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	search.placeholder_text = "Search by name or key"
	search.clear_button_enabled = true
	search.right_icon = preload("res://assets/icons/Search.svg")
	box.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 24)
	content.add_child(_grid)
	_no_match.text = "No shortcuts match"
	_no_match.theme_type_variation = &"StatusLabel"
	_no_match.hide()
	content.add_child(_no_match)
	scroll.add_child(content)
	box.add_child(scroll)
	add_child(box)
	search.text_changed.connect(filter.unbind(1))
	about_to_popup.connect(_fill)


func _fill() -> void:
	for child in _grid.get_children():
		child.free()
	_rows.clear()
	for menu: String in MainMenuBar.MENUS:
		_add_row(tr(menu), "", true)
		for id: StringName in MainMenuBar.MENUS[menu]:
			# Actions in submenus are listed where the submenu is, named after it
			if MainMenuBar.SUBMENUS.has(id):
				var submenu: Array = MainMenuBar.SUBMENUS[id]
				for inside: StringName in submenu[1]:
					_add_action_row(inside, submenu[0])
			else:
				_add_action_row(id)
	_add_row(tr("Preview"), "", true)
	_add_row(tr("Pan"), tr("Middle mouse drag or Space+drag"))
	_add_row(tr("Zoom"), tr("Mouse wheel"))
	_add_row(tr("Select a frame"), tr("Click"))
	_add_row(tr("Select or unselect a frame"), tr("Ctrl+click"))
	_add_row(tr("Select a range of frames"), tr("Shift+click"))
	_add_row(tr("Select frames in a box"), tr("Drag from outside the frames"))
	_add_row(tr("Add frames in a box to the selection"), tr("Shift+drag"))
	_add_row(tr("Select or unselect frames in a box"), tr("Ctrl+drag"))
	_add_row(tr("Add the next frame to the selection"), tr("Ctrl+arrow keys"))
	_add_row(tr("Move frames, with the selection when selected"), tr("Drag a frame"))
	_add_row(tr("Add frames to an animation"), tr("Drag them onto its timeline"))
	_add_row(tr("Move frames in their cells"), tr("Arrow keys (Shift: 8 px)"))
	_add_row(tr("Move frames onto or past the next guide or cell edge"), tr("Alt+arrow keys"))
	_add_row(tr("Add a guide (with rulers on)"), tr("Click a ruler"))
	_add_row(tr("Move or remove a guide"), tr("Drag it on its ruler, or onto the other one"))
	_add_row(tr("Move a pivot (with pivots on)"), tr("Drag the cross on a frame"))
	_add_row(tr("Put back what's dragged"), tr("Escape"))
	_add_row(tr("Lock or unlock an empty cell"), tr("Click it"))
	_add_row(tr("Frame actions"), tr("Right-click"))
	_add_row(tr("Timeline"), "", true)
	_add_row(tr("Copy frames in the timeline"), tr("Alt+drag"))
	search.clear()
	filter()
	_focus_search.call_deferred()


## Once shown. The window may be out of the tree by then, e.g. closed in tests.
func _focus_search() -> void:
	if search.is_inside_tree():
		search.grab_focus()


## Shows the rows that match the search, under their headings. A heading that matches
## shows every row under it.
func filter() -> void:
	var query := search.text.strip_edges()
	var heading := {}
	var heading_matches := false
	var any_shown := false
	for row in _rows:
		if row.heading:
			heading = row
			heading_matches = matches(query, row.text)
			_show_row(row, heading_matches)
			continue
		var shown: bool = heading_matches or matches(query, row.text, row.keys)
		_show_row(row, shown)
		if shown:
			_show_row(heading, true)
			any_shown = true
	_no_match.visible = not any_shown


## Whether a row saying [param text] matches [param query]: when its text has it, or when
## one of [param keys] is the key typed, see [method matches_key]
static func matches(query: String, text: String, keys := PackedStringArray()) -> bool:
	query = query.strip_edges()
	if query.is_empty() or text.containsn(query):
		return true
	for key in keys:
		if matches_key(query, key):
			return true
	return false


## Whether [param key] (like "Ctrl+Shift+E") is the key in [param query] with at least its
## modifiers, in any order and case: "ctrl+e" finds Ctrl+E and Ctrl+Shift+E, "F2" finds
## Shift+F2, and "ctrl" every key with Ctrl
static func matches_key(query: String, key: String) -> bool:
	var wanted := _key_parts(query)
	var have := _key_parts(key)
	if wanted.key.is_empty() and wanted.modifiers.is_empty():
		return false
	if wanted.key and wanted.key != have.key:
		return false
	for modifier: String in wanted.modifiers:
		if modifier not in have.modifiers:
			return false
	return true


## [code]{"key": String, "modifiers": PackedStringArray}[/code] of a key like
## "Ctrl+Shift+E", in lower case
static func _key_parts(text: String) -> Dictionary:
	var parts := {"key": "", "modifiers": PackedStringArray()}
	for part in text.to_lower().replace(" ", "").split("+", false):
		if MODIFIERS.has(part):
			parts.modifiers.append(MODIFIERS[part])
		else:
			parts.key = part
	return parts


func _show_row(row: Dictionary, shown: bool) -> void:
	for label: Label in row.labels:
		label.visible = shown


## Adds a row for the action [param id], named after [param submenu] when it's in one
func _add_action_row(id: StringName, submenu := "") -> void:
	if not id.is_empty() and Actions.has(id):
		var label := tr(Actions.get_action(id).label).trim_suffix("…")
		if submenu:
			# Like "Align in Cell: Top"
			label = tr("%s: %s") % [tr(submenu), label]
		var keys := Actions.get_shortcut_texts(id)
		_add_row(label, ", ".join(keys), false, keys)


## Adds a row of [param text] and [param shortcut]. [param keys] are those of an action,
## found by typing them.
func _add_row(
	text: String, shortcut: String, heading := false, keys := PackedStringArray()
) -> void:
	var label := Label.new()
	label.text = text
	var keys_label := Label.new()
	keys_label.text = shortcut
	keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if heading:
		label.theme_type_variation = &"AccentLabel"
	_grid.add_child(label)
	_grid.add_child(keys_label)
	# Free text like "Ctrl+click" is found as text
	var searched := text if keys or heading else text + " " + shortcut
	_rows.append(
		{"labels": [label, keys_label], "heading": heading, "text": searched, "keys": keys}
	)
