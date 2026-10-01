class_name LinkedFolders
extends PanelContainer
## The sheet's linked folders (see [FolderWatcher]), sunk into the sidebar under Add
## Sprite(s), under a title with a folder icon: each one's name and, smaller, the folder
## it's in, or that it's missing with a button to
## locate it (see [method locate]), and a button to unlink it. Right-clicking one offers to
## show it in the file manager, copy its path, locate it or unlink it. While Reload changed
## files is off, it says they're paused, with a link to turn it on. Hidden while there are
## none, and in a browser, which can't follow folders.

## The items of a folder's menu, see [method open_menu]
enum MenuItem { SHOW, COPY_PATH, LOCATE, UNLINK }

const FOLDER_ICON := preload("res://assets/icons/Folder.svg")
const UNLINK_ICON := preload("res://assets/icons/Unlink.svg")
const PAUSE_ICON := preload("res://assets/icons/Pause.svg")
const COPY_ICON := preload("res://assets/icons/ActionCopy.svg")
## How faint the unlink buttons are until their row is hovered or they have focus
const FAINT := 0.45
## How faint the folder and pause icons are, so they're as muted as the text next to them
## in both themes: tinting them with its colour would make the light theme's dark icons
## darker still
const MUTED := 0.7
## The size of a folder's name, and of the smaller text under it
const NAME_FONT_SIZE := 13
const DETAIL_FONT_SIZE := 11

## How many folders are linked, next to the title
var count_label := Label.new()
## A row for each linked folder, in the sheet's order, see [method _make_row]
var rows := VBoxContainer.new()
## Says the folders are paused while Reload changed files is off
var paused_row := HBoxContainer.new()
var turn_on_button := LinkButton.new()
## The menu of a folder, see [method open_menu]
var menu := PopupMenu.new()
## Asks where a missing folder is now, see [method locate]
var locate_dialog := FileDialog.new()
## What the rows were last made from, see [method refresh]
var _shown := []
## The folder [member menu] is for
var _menu_folder := ""
## The folder [member locate_dialog] asks for
var _locating := ""


func _init() -> void:
	theme_type_variation = &"InsetPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var header_margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		header_margin.add_theme_constant_override("margin_" + side, 6)
	header_margin.add_child(header)
	box.add_child(header_margin)
	var title_icon := TextureRect.new()
	title_icon.texture = FOLDER_ICON
	title_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	title_icon.modulate.a = MUTED
	header.add_child(title_icon)
	var title := Label.new()
	title.text = "Linked folders"
	title.theme_type_variation = &"StatusLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	count_label.theme_type_variation = &"StatusLabel"
	count_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(count_label)

	rows.add_theme_constant_override("separation", 0)
	box.add_child(rows)

	var paused_margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		paused_margin.add_theme_constant_override("margin_" + side, 6)
	paused_margin.add_theme_constant_override("margin_top", 2)
	paused_margin.add_child(paused_row)
	box.add_child(paused_margin)
	paused_row.add_theme_constant_override("separation", 6)
	var pause_icon := TextureRect.new()
	pause_icon.texture = PAUSE_ICON
	pause_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pause_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_icon.modulate.a = MUTED
	paused_row.add_child(pause_icon)
	var paused_text := VBoxContainer.new()
	paused_text.add_theme_constant_override("separation", 0)
	paused_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paused_row.add_child(paused_text)
	var paused_label := Label.new()
	paused_label.text = "Paused: Reload changed files is off."
	paused_label.theme_type_variation = &"StatusLabel"
	paused_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paused_text.add_child(paused_label)
	turn_on_button.text = "Turn on"
	turn_on_button.tooltip_text = "Turn Reload changed files back on"
	turn_on_button.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	turn_on_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	turn_on_button.pressed.connect(func() -> void: Settings.set_value(&"watch_sources", true))
	paused_text.add_child(turn_on_button)

	menu.theme = MainMenuBar.POPUP_THEME
	menu.id_pressed.connect(_on_menu_item)
	add_child(menu)
	locate_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	locate_dialog.access = FileDialog.ACCESS_FILESYSTEM
	locate_dialog.use_native_dialog = true
	locate_dialog.dir_selected.connect(
		func(dir: String) -> void: FolderWatcher.relocate(_locating, dir)
	)
	add_child(locate_dialog)


func _ready() -> void:
	Global.spritesheet.updated.connect(refresh)
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"watch_sources":
				refresh()
	)
	refresh()


func _notification(what: int) -> void:
	# A missing folder may be back, e.g. on a drive plugged in again
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		refresh()
	# The icons and link take the theme's colours, the tooltips the new language
	elif what in [NOTIFICATION_THEME_CHANGED, NOTIFICATION_TRANSLATION_CHANGED]:
		_shown = []
		if is_node_ready():
			refresh()


## Lists the linked folders again, when they, whether they're found, or whether they're
## followed changed
func refresh() -> void:
	var folders := (
		PackedStringArray() if FolderWatcher.in_browser else Global.spritesheet.linked_folders
	)
	var watched: bool = Settings.get_value(&"watch_sources")
	var found := Array(folders).map(
		func(f: String) -> bool: return DirAccess.dir_exists_absolute(f)
	)
	var shown := [folders, watched, found]
	if shown == _shown:
		return
	_shown = shown
	visible = not folders.is_empty()
	count_label.text = str(folders.size())
	paused_row.visible = not watched
	var link_color := get_theme_color("font_color", &"AccentLabel")
	for color: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
		turn_on_button.add_theme_color_override(color, link_color)
	turn_on_button.add_theme_font_size_override(
		"font_size", get_theme_font_size("font_size", &"StatusLabel")
	)
	for row in rows.get_children():
		rows.remove_child(row)
		row.queue_free()
	for i in folders.size():
		rows.add_child(_make_row(folders[i], found[i], watched))


## Opens the menu of the linked [param folder] at [param screen_position]: show it in the
## file manager, copy its path, locate it when it's missing, or unlink it
func open_menu(folder: String, screen_position: Vector2) -> void:
	_menu_folder = folder
	var found := DirAccess.dir_exists_absolute(folder)
	menu.clear()
	menu.add_icon_item(FOLDER_ICON, "Show in File Manager", MenuItem.SHOW)
	menu.set_item_disabled(menu.get_item_index(MenuItem.SHOW), not found)
	menu.add_icon_item(COPY_ICON, "Copy Path", MenuItem.COPY_PATH)
	if not found:
		menu.add_item("Locate…", MenuItem.LOCATE)
	menu.add_separator()
	menu.add_icon_item(UNLINK_ICON, "Unlink Folder", MenuItem.UNLINK)
	menu.popup(Rect2i(Vector2i(screen_position), Vector2i.ZERO))


## Asks where the missing linked [param folder] is now, starting in the nearest folder of
## its path that's still there, and follows the one picked instead, see
## [method FolderWatcher.relocate]
func locate(folder: String) -> void:
	_locating = folder
	locate_dialog.title = tr("Locate %s") % _folder_name(folder)
	locate_dialog.current_dir = StartScreen.nearest_folder(folder)
	locate_dialog.popup_centered()


## Stops following [param folder], as an undoable step
static func unlink(folder: String) -> void:
	Global.document.perform(
		L10n.mark("Unlink folder"), Global.spritesheet.unlink_folder.bind(folder)
	)


func _on_menu_item(id: int) -> void:
	var folder := _menu_folder
	match id:
		MenuItem.SHOW:
			OS.shell_show_in_file_manager(folder)
		MenuItem.COPY_PATH:
			DisplayServer.clipboard_set(folder)
		MenuItem.LOCATE:
			locate(folder)
		MenuItem.UNLINK:
			unlink(folder)


## The row of [param folder]: its name over the folder it's in, smaller, or over "Not
## found" with a Locate… button when it isn't [param found], and the unlink button, faint
## until the row is hovered. Its tooltip has the whole path, and whether images added to
## it are added, which they aren't while not [param watched].
func _make_row(folder: String, found: bool, watched: bool) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = &"InsetRow"
	row.set_meta(&"folder", folder)
	var tip := folder + "\n"
	if not found:
		tip += tr("The folder wasn't found.")
	elif watched:
		tip += tr("Images added to it are added here.")
	else:
		tip += tr("Paused: Reload changed files is off.")
	row.tooltip_text = tip
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(names)
	var name_label := Label.new()
	name_label.text = _folder_name(folder)
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(name_label)
	var where := Label.new()
	where.mouse_filter = Control.MOUSE_FILTER_IGNORE
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	if found:
		var parent := folder.get_base_dir()
		where.text = parent
		where.theme_type_variation = &"StatusLabel"
		where.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		# The end of a path tells more than its start
		where.resized.connect(func() -> void: where.text = StartScreen.trim_start(where, parent))
		where.visible = parent != folder and not parent.is_empty()
	else:
		where.text = "Not found"
		where.theme_type_variation = &"ErrorLabel"
	names.add_child(where)

	if not found:
		var locate_button := Button.new()
		locate_button.text = "Locate…"
		locate_button.tooltip_text = "Find where the folder is now"
		locate_button.theme_type_variation = &"ToolbarButton"
		locate_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		locate_button.pressed.connect(locate.bind(folder))
		box.add_child(locate_button)

	var unlink_button := Button.new()
	unlink_button.theme_type_variation = &"ToolbarButton"
	unlink_button.icon = UNLINK_ICON
	unlink_button.tooltip_text = "Unlink folder"
	unlink_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	unlink_button.modulate.a = FAINT
	unlink_button.pressed.connect(unlink.bind(folder))
	box.add_child(unlink_button)

	# Entering the unlink button doesn't leave the row
	row.mouse_entered.connect(_highlight.bind(row, true))
	row.mouse_exited.connect(_highlight.bind(row, false))
	unlink_button.focus_entered.connect(_highlight.bind(row, null))
	unlink_button.focus_exited.connect(_highlight.bind(row, null))
	row.gui_input.connect(_on_row_input.bind(row, folder))
	return row


## Shades [param row] and shows its unlink button fully while it's hovered or the button
## has focus. [param hovered] is whether the pointer is over it now, or null when that
## didn't change.
func _highlight(row: Control, hovered: Variant) -> void:
	if hovered != null:
		row.set_meta(&"hovered", hovered)
	var unlink_button := row.get_child(0).get_child(-1) as Button
	var lit: bool = row.get_meta(&"hovered", false) or unlink_button.has_focus()
	if lit:
		row.add_theme_stylebox_override("panel", get_theme_stylebox("hover", &"InsetRow"))
	else:
		row.remove_theme_stylebox_override("panel")
	unlink_button.modulate.a = 1.0 if lit else FAINT


func _on_row_input(event: InputEvent, row: Control, folder: String) -> void:
	var mouse := event as InputEventMouseButton
	if mouse and mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
		open_menu(folder, row.get_screen_transform() * mouse.position)
		row.accept_event()


## The name of [param folder], or its whole path for a drive's root
static func _folder_name(folder: String) -> String:
	return folder.get_file() if folder.get_file() else folder
