class_name DocumentTabs
extends PanelContainer
## The tabs of the open documents over the canvas, one for each of
## [member Global.documents], like the Godot editor's scene tabs. A tab is named after
## its document's file (see [method Document.get_display_name]), with its folder when
## another has the same name, and (*) while it has unsaved changes. Clicking one makes it
## active, dragging one moves it, and its close button or a middle click closes it, asking
## to save it first. Its menu closes more at once. The + after the last tab, or a double
## click next to them, opens a new one.

## The items of a tab's menu, see [method open_menu]
enum MenuItem { CLOSE, CLOSE_OTHERS, CLOSE_RIGHT, CLOSE_ALL, SHOW, COPY_PATH }

const PROJECT_ICON := preload("res://assets/icons/SpriteSheet.svg")
const IMAGE_ICON := preload("res://assets/icons/Image.svg")
const NEW_ICON := preload("res://assets/icons/Add.svg")
const CLOSE_ICON := preload("res://assets/icons/Close.svg")
const FOLDER_ICON := preload("res://assets/icons/Folder.svg")
const COPY_ICON := preload("res://assets/icons/ActionCopy.svg")
## The widest a tab gets before its name is cut
const MAX_TAB_WIDTH := 220

var bar := TabBar.new()
## Opens a new tab, right after the last one, see [method _place_new_button]
var new_button := Button.new()
## The menu of a tab, see [method open_menu]
var menu := PopupMenu.new()
## Asks to save the documents it closes
var files: FileController
## Keeps room for [member new_button] once the tabs fill the bar
var _new_button_room := Control.new()
## The document [member menu] is for
var _menu_document: Document
## True while the tabs are being made again, so the bar choosing one isn't the user's
var _refreshing := false
var _refresh_queued := false


func _init() -> void:
	theme_type_variation = &"TabStrip"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.clip_tabs = true
	bar.max_tab_width = MAX_TAB_WIDTH
	bar.drag_to_rearrange_enabled = true
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	bar.focus_mode = Control.FOCUS_NONE
	# Named after files, and "Untitled" is translated here
	bar.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(bar)
	row.add_child(_new_button_room)
	new_button.icon = NEW_ICON
	new_button.focus_mode = Control.FOCUS_NONE
	new_button.theme_type_variation = &"ToolbarButton"
	bar.add_child(new_button)
	menu.theme = MainMenuBar.POPUP_THEME
	add_child(menu)


func _ready() -> void:
	bar.tab_changed.connect(_on_tab_changed)
	bar.tab_close_pressed.connect(func(tab: int) -> void: close(Global.documents[tab]))
	bar.tab_rmb_clicked.connect(
		func(tab: int) -> void:
			open_menu(tab, bar.get_screen_transform() * bar.get_local_mouse_position())
	)
	bar.active_tab_rearranged.connect(
		func(to: int) -> void: Global.move_document(Global.document, to)
	)
	bar.gui_input.connect(_on_bar_input)
	bar.resized.connect(_place_new_button)
	new_button.pressed.connect(Actions.run.bind(&"new"))
	new_button.minimum_size_changed.connect(_place_new_button)
	menu.id_pressed.connect(_on_menu_item)
	Global.documents_changed.connect(queue_refresh)
	Global.document_switched.connect(queue_refresh.unbind(1))
	refresh()


func _notification(what: int) -> void:
	# "Untitled" in the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()


## Makes the tabs again at the end of the frame, once for many changes
func queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


## Makes a tab for each open document, with the active one chosen
func refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	_refreshing = true
	var documents := Global.documents
	var titles := get_titles(documents)
	bar.tab_count = documents.size()
	for i in documents.size():
		var document := documents[i]
		# Changes made in the background, e.g. by work that ends after another tab was
		# chosen, show too
		if not document.changed.is_connected(queue_refresh):
			document.changed.connect(queue_refresh)
		bar.set_tab_title(i, titles[i] + ("(*)" if document.is_dirty else ""))
		bar.set_tab_tooltip(i, document.get_name_path())
		bar.set_tab_icon(i, _icon_of(document))
	bar.current_tab = documents.find(Global.document)
	_refreshing = false
	_place_new_button.call_deferred()


## What the tab of each of [param documents] is called: its file's name, or "Untitled",
## with the folder before it when another has the same name
static func get_titles(documents: Array[Document]) -> PackedStringArray:
	var names: PackedStringArray = []
	for document in documents:
		var display_name := document.get_display_name()
		names.append(display_name if display_name else TranslationServer.translate("Untitled"))
	var titles := names.duplicate()
	for i in documents.size():
		var path := documents[i].get_name_path()
		if path and names.count(names[i]) > 1:
			var folder := path.get_base_dir().get_file()
			if folder:
				titles[i] = folder.path_join(names[i])
	return titles


static func _icon_of(document: Document) -> Texture2D:
	if ProjectFile.is_project_path(document.path):
		return PROJECT_ICON
	if document.get_name_path():
		return IMAGE_ICON
	return null


## Closes the tab of [param document], asking to save it first
func close(document: Document) -> void:
	files.close_tabs([document] as Array[Document])


## Opens the menu of the tab at [param tab] at [param screen_position]: close it, the
## others, those after it or all of them, and show or copy where its file is
func open_menu(tab: int, screen_position: Vector2) -> void:
	_menu_document = Global.documents[tab]
	var path := _menu_document.get_name_path()
	var count := Global.documents.size()
	menu.clear()
	menu.add_icon_item(CLOSE_ICON, "Close Tab", MenuItem.CLOSE)
	menu.add_item("Close Other Tabs", MenuItem.CLOSE_OTHERS)
	menu.set_item_disabled(menu.get_item_index(MenuItem.CLOSE_OTHERS), count < 2)
	menu.add_item("Close Tabs to the Right", MenuItem.CLOSE_RIGHT)
	menu.set_item_disabled(menu.get_item_index(MenuItem.CLOSE_RIGHT), tab == count - 1)
	menu.add_item("Close All Tabs", MenuItem.CLOSE_ALL)
	if not WebFiles.is_web():
		menu.add_separator()
		menu.add_icon_item(FOLDER_ICON, "Show in File Manager", MenuItem.SHOW)
		menu.set_item_disabled(
			menu.get_item_index(MenuItem.SHOW), not (path and FileAccess.file_exists(path))
		)
		menu.add_icon_item(COPY_ICON, "Copy Path", MenuItem.COPY_PATH)
		menu.set_item_disabled(menu.get_item_index(MenuItem.COPY_PATH), path.is_empty())
	menu.popup(Rect2i(Vector2i(screen_position), Vector2i.ZERO))


func _on_menu_item(id: int) -> void:
	var document := _menu_document
	var index := Global.documents.find(document)
	if index < 0:
		return
	var others: Array[Document] = []
	match id:
		MenuItem.CLOSE:
			close(document)
		MenuItem.CLOSE_OTHERS:
			for other in Global.documents:
				if other != document:
					others.append(other)
			files.close_tabs(others)
		MenuItem.CLOSE_RIGHT:
			files.close_tabs(Global.documents.slice(index + 1))
		MenuItem.CLOSE_ALL:
			files.close_tabs(Global.documents.duplicate())
		MenuItem.SHOW:
			OS.shell_show_in_file_manager(document.get_name_path())
		MenuItem.COPY_PATH:
			DisplayServer.clipboard_set(document.get_name_path())


func _on_tab_changed(tab: int) -> void:
	if not _refreshing and tab >= 0 and tab < Global.documents.size():
		Global.switch_to(Global.documents[tab])


## A middle click closes a tab, and a double click next to the tabs opens a new one
func _on_bar_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var tab := bar.get_tab_idx_at_point(click.position)
	if click.button_index == MOUSE_BUTTON_MIDDLE and tab >= 0:
		close(Global.documents[tab])
		bar.accept_event()
	elif click.button_index == MOUSE_BUTTON_LEFT and click.double_click and tab < 0:
		Actions.run(&"new")
		bar.accept_event()


## Puts the + right after the last tab, or at the end of the bar once the tabs fill it,
## with room kept for it there
func _place_new_button() -> void:
	var button_size := new_button.get_combined_minimum_size()
	new_button.size = button_size
	var end := 0.0
	if bar.tab_count > 0:
		end = bar.get_tab_rect(bar.tab_count - 1).end.x
	var room := bar.size.x
	_new_button_room.custom_minimum_size.x = button_size.x if end + button_size.x > room else 0.0
	new_button.position = Vector2(minf(end, room), roundf((bar.size.y - button_size.y) / 2))
