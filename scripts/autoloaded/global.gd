extends Node
## Holds the open documents, one per tab, and keeps the window title in sync with the
## active one. Connect to the signals here rather than to a document's own, as they
## follow whichever document is active.

## The theme was built again, see [method apply_theme]
signal theme_applied
## The active document's [signal Document.changed]
signal document_changed
## The active document's [signal Document.loaded]
signal document_loaded(view: Dictionary)
## The active document's spritesheet's [signal Spritesheet.updated]
signal spritesheet_updated
## The active document's spritesheet's [signal Spritesheet.layout_warning]
signal layout_warning(message: String)
## Another document became active, see [method switch_to]. [param previous] is null
## when it was closed.
signal document_switched(previous: Document)
## Documents were opened, closed or reordered, see [member documents]
signal documents_changed

## The open documents, in the order of their tabs. Never empty.
var documents: Array[Document] = []
## The active document, the one the editor shows. Change it with [method switch_to].
var document: Document
## True when started from the command line to pack or export, without the window
var cli_mode := false
## The interface's scale, the [code]ui_scale[/code] setting or the screen's for "Automatic"
var ui_scale := 1.0
## Places and sizes the main window, on desktops only, see [method WindowPlacement.is_supported]
var window_placement: WindowPlacement
## Whether the interface is light: the [code]theme[/code] setting's, or the operating
## system's for "System"
var light_theme := false
## The interface's accent colour: the [code]accent_color[/code] setting's, or the
## operating system's when [code]system_accent[/code] is on and it has one
var accent_color := AppTheme.DEFAULT_ACCENT
## Whether the operating system is in dark mode, true where it can't tell. Tests replace it.
var is_system_dark := func() -> bool:
	return not DisplayServer.is_dark_mode_supported() or DisplayServer.is_dark_mode()
## The operating system's accent colour, transparent where it has none. Tests replace it.
var get_system_accent := func() -> Color: return DisplayServer.get_accent_color()
## The open document's spritesheet
var spritesheet: Spritesheet:
	get:
		return document.spritesheet


func _init() -> void:
	# Other autoloads connect to the document in their _ready, also on the command line
	add_document(Document.new())


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if Cli.is_cli(args):
		cli_mode = true
		# The command line speaks English, whatever the language chosen
		TranslationServer.set_locale("en")
		get_tree().quit(await Cli.run(args))
		return
	L10n.load_user_translations()
	L10n.apply(Settings.get_value(&"language"))
	document.reset()
	document_changed.connect(update_window_title)
	document_switched.connect(update_window_title.unbind(1))
	update_window_title()
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"ui_scale":
				apply_ui_scale()
			elif key in [&"theme", &"accent_color", &"system_accent"]:
				apply_theme()
			elif key == &"language":
				L10n.apply(Settings.get_value(key))
	)
	# Follows the operating system's dark mode and accent colour as they change
	DisplayServer.set_system_theme_change_callback(
		func() -> void: update_system_theme.call_deferred()
	)
	get_tree().node_added.connect(_on_node_added)
	# Placed now, before the main window is set up, so it only changes once after the splash
	if WindowPlacement.is_supported():
		window_placement = WindowPlacement.new()
		add_child(window_placement)
	apply_ui_scale()
	apply_theme()
	if window_placement:
		window_placement.restore()


## Frees the nodes held in [param holder]'s variables that were never added to the tree,
## such as dialogs when the command line quits before the window is set up
func free_unused_nodes(holder: Object) -> void:
	for property in holder.get_property_list():
		if property.type != TYPE_OBJECT:
			continue
		var value: Variant = holder.get(property.name)
		if value is Node and is_instance_valid(value) and (value as Node).get_parent() == null:
			(value as Node).free()


func _notification(what: int) -> void:
	# In case the operating system didn't say its theme changed
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not cli_mode:
		update_system_theme()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not cli_mode:
		update_window_title()


## Fills the project theme (an empty resource in project.godot) with the generated one,
## so every control and window uses it, whatever its parents are
func apply_theme() -> void:
	light_theme = _is_light_theme()
	accent_color = _get_accent_color()
	var project_theme := ThemeDB.get_project_theme()
	if project_theme == null:
		return
	project_theme.clear()
	project_theme.merge_with(AppTheme.build(light_theme, accent_color))
	get_tree().root.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)
	theme_applied.emit()


## Applies the theme again when it follows the operating system's dark mode or accent
## colour and they changed
func update_system_theme() -> void:
	if _is_light_theme() != light_theme or _get_accent_color() != accent_color:
		apply_theme()


func _is_light_theme() -> bool:
	match Settings.get_value(&"theme"):
		"light":
			return true
		"system":
			return not is_system_dark.call()
	return false


## Whether the operating system has an accent colour, see [member get_system_accent]
func has_system_accent() -> bool:
	return (get_system_accent.call() as Color).a > 0


func _get_accent_color() -> Color:
	if Settings.get_value(&"system_accent") and has_system_accent():
		return Color(get_system_accent.call() as Color, 1.0)
	return Settings.get_value(&"accent_color")


## Scales the whole interface, the main window and every separate one; "Automatic"
## follows the screen's scale
func apply_ui_scale() -> void:
	ui_scale = Settings.get_value(&"ui_scale")
	if ui_scale <= 0:
		ui_scale = DisplayServer.screen_get_scale()
	get_tree().root.content_scale_factor = ui_scale
	# The main window's smallest size is in interface units too
	if window_placement:
		window_placement.apply_min_size(ui_scale)
	var nodes: Array[Node] = [get_tree().root]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		nodes.append_array(node.get_children(true))
		if node is Window and _needs_scaling(node):
			scale_window(node, ui_scale)


## Gives [param window] the interface's [param scale], with its minimum size (set in
## unscaled pixels) scaled to match but kept within the screen. An open window grows or
## shrinks around its centre.
func scale_window(window: Window, scale: float) -> void:
	if not window.has_meta(&"unscaled_min_size"):
		window.set_meta(&"unscaled_min_size", window.min_size)
	var screen := Rect2(DisplayServer.screen_get_usable_rect(get_tree().root.current_screen))
	var old_scale := window.content_scale_factor
	var old_rect := Rect2(window.position, window.size)
	window.content_scale_factor = scale
	var min_size := Vector2(window.get_meta(&"unscaled_min_size")) * scale
	# Without a screen (headless) there's nothing to keep within
	if screen.has_area():
		min_size = min_size.min(screen.size)
	window.min_size = Vector2i(min_size.ceil())
	if window.visible and old_scale != scale:
		var rect := Rect2(Vector2.ZERO, (old_rect.size * scale / old_scale).ceil())
		rect.position = old_rect.get_center() - rect.size / 2
		if screen.has_area():
			rect.size = rect.size.min(screen.size)
			rect.position = rect.position.clamp(screen.position, screen.end - rect.size)
		window.size = Vector2i(rect.size)
		window.position = Vector2i(rect.position)


## Separate windows start at scale 1, unlike the main window. Embedded ones (all of them
## on the web) already draw at the main window's scale, and popup menus and tooltips scale
## themselves to their parent window when they open.
func _needs_scaling(window: Window) -> bool:
	return not (
		window == get_tree().root
		or window.is_embedded()
		or window is PopupMenu
		or window.theme_type_variation == &"TooltipPanel"
	)


func _on_node_added(node: Node) -> void:
	var window := node as Window
	if window == null or not _needs_scaling(window):
		return
	# Its minimum size may still be set in its _ready
	if window.is_node_ready():
		scale_window(window, ui_scale)
	else:
		window.ready.connect(func() -> void: scale_window(window, ui_scale), CONNECT_ONE_SHOT)


## Adds [param doc] as a tab after the active one, or at the end when there's none yet,
## and makes it active when [param activate]
func add_document(doc: Document, activate := true) -> void:
	documents.insert(documents.find(document) + 1 if document else documents.size(), doc)
	documents_changed.emit()
	if activate or document == null:
		switch_to(doc)


## Makes [param doc], one of [member documents], the active document
func switch_to(doc: Document) -> void:
	if doc == document or doc not in documents:
		return
	var previous := document
	if previous:
		previous.changed.disconnect(document_changed.emit)
		previous.loaded.disconnect(document_loaded.emit)
		previous.spritesheet.updated.disconnect(spritesheet_updated.emit)
		previous.spritesheet.layout_warning.disconnect(layout_warning.emit)
	document = doc
	doc.changed.connect(document_changed.emit)
	doc.loaded.connect(document_loaded.emit)
	doc.spritesheet.updated.connect(spritesheet_updated.emit)
	doc.spritesheet.layout_warning.connect(layout_warning.emit)
	document_switched.emit(previous if previous in documents else null)


## Closes the tab of [param doc] without asking anything. The last one isn't closed but
## emptied, as after New. The tab after it becomes active, else the one before.
func close_document(doc: Document) -> void:
	var index := documents.find(doc)
	if index < 0:
		return
	if documents.size() == 1:
		doc.reset()
		return
	documents.remove_at(index)
	if doc == document:
		switch_to(documents[mini(index, documents.size() - 1)])
	documents_changed.emit()


## Puts the tab of [param doc] at [param index]
func move_document(doc: Document, index: int) -> void:
	var from := documents.find(doc)
	if from < 0 or from == index:
		return
	documents.remove_at(from)
	documents.insert(clampi(index, 0, documents.size()), doc)
	documents_changed.emit()


## The open document with [param path] as its project file, or null
func find_document(path: String) -> Document:
	if path.is_empty():
		return null
	for doc in documents:
		if doc.path == path:
			return doc
	return null


## Closes every tab but the active one, which is emptied, as at startup. For tests.
func reset_documents() -> void:
	for doc in documents.duplicate():
		if doc != document:
			documents.erase(doc)
	documents_changed.emit()
	document.reset()


func update_window_title() -> void:
	DisplayServer.window_set_title(get_window_title(document))


## Like "(*) walk.png - spritesheetbelli 1.0", with "(*)" for unsaved changes and
## "Untitled" for a document that isn't named after any file
static func get_window_title(doc: Document) -> String:
	var title := "(*) " if doc.is_dirty else ""
	var display_name := doc.get_display_name()
	title += display_name if display_name else String(TranslationServer.translate("Untitled"))
	title += " - " + ProjectSettings.get_setting("application/config/name")
	title += " " + ProjectSettings.get_setting("application/config/version", "")
	return title
