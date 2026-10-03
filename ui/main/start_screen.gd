class_name StartScreen
extends Panel
## What the window shows below the menu while nothing is open (see
## [method Document.is_blank]), covering the editor: the app's name, a zone to drop files
## on with buttons to open a file or add sprites, and the recent files with their
## thumbnails (see [Thumbnails]) and when they were changed, to open, forget, or locate
## when they were moved. Files dropped anywhere in the window are opened like on the canvas.
## Arrow keys start moving between the recent files and the buttons, see [method _input].
## A browser has no recent files, so it only has the name and the drop zone.

## Emitted when a recent file is clicked, or located (see [method locate])
signal file_chosen(path: String)

## The items of the menu of a recent file, see [method open_menu]
enum MenuItem { OPEN, LOCATE, SHOW, COPY_PATH, FORGET }

## The actions of the buttons, so their names, icons and shortcuts match the menus. Add
## Folder is only an icon, right next to Add Sprite(s), see [method _build_drop_zone].
const BUTTON_ACTIONS: Array[StringName] = [
	&"open", &"add_spritesheet", &"add_sprites", &"add_folder"
]
## The height of the buttons, and the width of Add Folder's
const BUTTON_HEIGHT := 34
## Between Add Sprite(s) and Add Folder, less than between the other buttons
const PAIR_GAP := 3
## Actions for the editor it covers, which can't run while it shows, see [method cover_actions]
const EDITOR_ACTIONS: Array[StringName] = [
	&"layout_grid",
	&"layout_packed",
	&"zoom_in",
	&"zoom_out",
	&"zoom_reset",
	&"zoom_fit",
	&"toggle_grid",
	&"toggle_pixel_grid",
	&"toggle_indices",
	&"toggle_rulers",
	&"clear_guides",
	&"guides_color",
	&"toggle_sprites",
	&"toggle_history",
	&"toggle_status_bar",
	&"toggle_animation",
]
# L10n.mark
## Months in dates, see [method format_date]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const CLOSE_ICON := preload("res://assets/icons/Close.svg")
const LOGO := preload("res://icon.svg")
const DROP_ICON := preload("res://assets/icons/Load.svg")
const FOLDER_ICON := preload("res://assets/icons/Folder.svg")
const COPY_ICON := preload("res://assets/icons/ActionCopy.svg")
## Shown until a recent file has a thumbnail, or when it's missing
const PROJECT_ICON := preload("res://assets/icons/SpriteSheet.svg")
const IMAGE_ICON := preload("res://assets/icons/Image.svg")
const CARD_SIZE := Vector2(184, 208)
const CARD_GAP := 10
const THUMBNAIL_SIZE := Vector2(168, 126)
## Recent files in a row at most. The most that are kept (see
## [constant Settings.MAX_RECENT_FILES]) fill two rows.
const MAX_COLUMNS := 5
## Around everything, and at least on the sides when the window is narrower than the
## columns
const MARGIN := 24

## Whether it's in a browser, which has no recent files to list
var in_browser := WebFiles.is_web()
## Above the recent files, for notices like work to recover (see [RecoveryNotice]), added
## with [method add_notice]. Hidden while none shows.
var notices := VBoxContainer.new()
var drop_zone := DropZone.new()
var drop_hint := Label.new()
## The buttons, Add Sprite(s) and Add Folder in a row of their own so they stay together
var buttons := HFlowContainer.new()
## The button of each of the [constant BUTTON_ACTIONS], by action
var action_buttons: Dictionary[StringName, Button] = {}
var recent_list := HFlowContainer.new()
## Said instead of the recent files while there are none
var empty_hint := Label.new()
## The card of each recent file listed, by path
var cards: Dictionary[String, Button] = {}
## The thumbnail of each recent file listed, by path
var thumbnails: Dictionary[String, TextureRect] = {}
## Asks where a missing recent file is now, see [method locate]
var locate_dialog := FileDialog.new()
## The menu of a recent file, see [method open_menu]
var card_menu := PopupMenu.new()
var _scroll := ScrollContainer.new()
## Keeps everything as wide as [constant MAX_COLUMNS] cards at most, see [method _fit_width]
var _margin := MarginContainer.new()
## Thumbnails asked for, so an image that can't be loaded isn't tried again and again
var _asked: Dictionary[String, bool] = {}
## The recent file [member locate_dialog] asks for
var _locating := ""
## The recent file [member card_menu] is for
var _menu_file := ""


func _ready() -> void:
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll)
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, MARGIN)
	_scroll.add_child(_margin)
	_scroll.resized.connect(_fit_width)
	_scroll.get_v_scroll_bar().visibility_changed.connect(_fit_width)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	_margin.add_child(column)

	column.add_child(_make_header())
	_build_drop_zone()
	column.add_child(drop_zone)
	notices.visible = false
	column.add_child(notices)
	recent_list.alignment = FlowContainer.ALIGNMENT_CENTER
	# Rows that aren't full start on the left, under the cards above
	recent_list.last_wrap_alignment = FlowContainer.LAST_WRAP_ALIGNMENT_BEGIN
	recent_list.add_theme_constant_override("h_separation", CARD_GAP)
	recent_list.add_theme_constant_override("v_separation", CARD_GAP)
	column.add_child(recent_list)
	empty_hint.text = "Files you open will appear here"
	empty_hint.theme_type_variation = &"StatusLabel"
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(empty_hint)
	locate_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	locate_dialog.access = FileDialog.ACCESS_FILESYSTEM
	locate_dialog.use_native_dialog = true
	locate_dialog.file_selected.connect(func(path: String) -> void: replace(_locating, path))
	add_child(locate_dialog)
	card_menu.theme = MainMenuBar.POPUP_THEME
	card_menu.id_pressed.connect(_on_menu_item)
	add_child(card_menu)

	Global.document.changed.connect(update)
	Global.spritesheet.updated.connect(update)
	visibility_changed.connect(
		func() -> void:
			if visible:
				refresh()
	)
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key in [&"recent_files", &"background_color", &"theme"]:
				refresh()
	)
	refresh()
	update()


func _process(_delta: float) -> void:
	for file in Thumbnails.take_finished():
		if thumbnails.has(file):
			_show_thumbnail(file)


func _exit_tree() -> void:
	# Worker threads are waited for before quitting
	Thumbnails.wait_for_all()


func _notification(what: int) -> void:
	# Files may have been moved or changed meanwhile
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and visible:
		refresh()
	# When files were changed is said in the new language
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()


## Nothing has focus until an arrow key is pressed, which starts on the first recent file,
## or the first button when there are none. Escape and clicks leave nothing focused again.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	var ours := focused != null and is_ancestor_of(focused)
	if event is InputEventMouseButton and not event.pressed and ours:
		# After the click is handled, or a button pressed with the mouse wouldn't be
		focused.release_focus.call_deferred()
	elif ours and event.is_action_pressed(&"ui_cancel"):
		focused.release_focus()
		get_viewport().set_input_as_handled()
	elif focused == null and _is_arrow(event):
		var first: Control = cards.values()[0] if cards else action_buttons.values()[0]
		first.grab_focus()
		get_viewport().set_input_as_handled()


static func _is_arrow(event: InputEvent) -> bool:
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if event.is_action_pressed(action, true):
			return true
	return false


## Shows it while nothing is open, see [method Document.is_blank]
func update() -> void:
	visible = Global.document.is_blank()


## Makes the [constant EDITOR_ACTIONS] unavailable while it shows, saying why
func cover_actions() -> void:
	for id in EDITOR_ACTIONS:
		if not Actions.has(id):
			continue
		var action := Actions.get_action(id)
		var can_run := action.can_run
		var why_disabled := action.why_disabled
		action.can_run = func() -> bool:
			return not visible and (not can_run.is_valid() or can_run.call())
		action.why_disabled = func() -> String:
			if visible:
				return L10n.mark("Nothing open")
			return why_disabled.call() if why_disabled.is_valid() else ""


## Lists the recent files again
func refresh() -> void:
	for card: Button in cards.values():
		card.queue_free()
	cards.clear()
	thumbnails.clear()
	var files := PackedStringArray() if in_browser else Settings.get_recent_files()
	for file in files:
		var card := _make_card(file)
		recent_list.add_child(card)
		cards[file] = card
		_show_thumbnail(file)
	recent_list.visible = not files.is_empty()
	empty_hint.visible = files.is_empty() and not in_browser


## Shows [param notice] above the recent files while it's visible
func add_notice(notice: Control) -> void:
	notices.add_child(notice)
	notice.visibility_changed.connect(_update_notices)
	_update_notices()


func _update_notices() -> void:
	notices.visible = notices.get_children().any(
		func(notice: Control) -> bool: return notice.visible
	)


## Takes [param file] off the recent files, with its thumbnail
func forget(file: String) -> void:
	Thumbnails.forget(file)
	Settings.remove_recent_file(file)


## Asks where the missing recent file [param file] is now, starting in the nearest folder
## of its path that's still there. Picking it puts it in place of [param file] and opens
## it, see [method replace].
func locate(file: String) -> void:
	_locating = file
	locate_dialog.title = tr("Locate %s") % file.get_file()
	var project := ProjectFile.is_project_path(file)
	locate_dialog.filters = [
		FileController.PROJECT_FILTER if project else FileController.IMAGE_FILTER
	]
	locate_dialog.current_dir = nearest_folder(file)
	locate_dialog.popup_centered()


## Puts [param new_file] in place of the recent file [param file], which is forgotten
## with its thumbnails, and opens it
func replace(file: String, new_file: String) -> void:
	Thumbnails.forget(file)
	Settings.replace_recent_file(file, new_file)
	file_chosen.emit(new_file)


## Opens the menu of the recent file [param file] at [param screen_position]: open it, or
## locate it when it's missing, show it in the file manager, copy its path, or forget it
func open_menu(file: String, screen_position: Vector2) -> void:
	_menu_file = file
	var found := FileAccess.file_exists(file)
	card_menu.clear()
	if found:
		card_menu.add_icon_item(DROP_ICON, "Open", MenuItem.OPEN)
	elif not in_browser:
		card_menu.add_item("Locate…", MenuItem.LOCATE)
	card_menu.add_icon_item(FOLDER_ICON, "Show in File Manager", MenuItem.SHOW)
	card_menu.set_item_disabled(card_menu.get_item_index(MenuItem.SHOW), not found)
	card_menu.add_icon_item(COPY_ICON, "Copy Path", MenuItem.COPY_PATH)
	card_menu.add_separator()
	card_menu.add_icon_item(CLOSE_ICON, "Remove from Recent Files", MenuItem.FORGET)
	card_menu.popup(Rect2i(Vector2i(screen_position), Vector2i.ZERO))


func _on_menu_item(id: int) -> void:
	var file := _menu_file
	match id:
		MenuItem.OPEN:
			file_chosen.emit(file)
		MenuItem.LOCATE:
			locate(file)
		MenuItem.SHOW:
			OS.shell_show_in_file_manager(file)
		MenuItem.COPY_PATH:
			DisplayServer.clipboard_set(file)
		MenuItem.FORGET:
			_forget_keeping_focus(file)


## Forgets [param file], and when its card had focus, gives it to the next card, or the
## previous one when it was the last, or else to the first button
func _forget_keeping_focus(file: String) -> void:
	var card: Button = cards.get(file)
	var had_focus := card != null and card.has_focus()
	var index := cards.keys().find(file)
	forget(file)
	if not had_focus:
		return
	var files := cards.keys()
	if files.is_empty():
		action_buttons.values()[0].grab_focus()
	else:
		cards[files[mini(index, files.size() - 1)]].grab_focus()


## The nearest folder of [param file]'s path that exists, or its root when none does
static func nearest_folder(file: String) -> String:
	var folder := file.get_base_dir()
	while not DirAccess.dir_exists_absolute(folder):
		var parent := folder.get_base_dir()
		if parent == folder or parent.is_empty():
			break
		folder = parent
	return folder


## How long ago [param time] was at [param now] (both Unix times), like "3 hours ago",
## "Yesterday", or the date after a week, translated
static func describe_age(time: int, now: int) -> String:
	var seconds := now - time
	if seconds < 60:
		return String(TranslationServer.translate("Just now"))
	if seconds < 3600:
		var minutes := seconds / 60
		return (
			String(TranslationServer.translate_plural("%d minute ago", "%d minutes ago", minutes))
			% minutes
		)
	if seconds < 86400:
		var hours := seconds / 3600
		return (
			String(TranslationServer.translate_plural("%d hour ago", "%d hours ago", hours)) % hours
		)
	var days := seconds / 86400
	if days == 1:
		return String(TranslationServer.translate("Yesterday"))
	if days < 7:
		return String(TranslationServer.translate_plural("%d day ago", "%d days ago", days)) % days
	return format_date(time)


## The day of [param time] (a Unix time) where the computer is, like "12 Sep 2026", and
## with [param with_time] its time too, like "12 Sep 2026, 14:03"
static func format_date(time: int, with_time := false) -> String:
	var local: int = time + Time.get_time_zone_from_system().bias * 60
	var date := Time.get_datetime_dict_from_unix_time(local)
	var month := String(TranslationServer.translate(MONTHS[date.month - 1]))
	var text := "%d %s %d" % [date.day, month, date.year]
	if with_time:
		text += ", %02d:%02d" % [date.hour, date.minute]
	return text


## Makes the column as wide as the most cards that fit in a row, [constant MAX_COLUMNS]
## at most, in the middle, so the drop zone lines up with the cards
func _fit_width() -> void:
	var bar := _scroll.get_v_scroll_bar()
	var room := _scroll.size.x - (bar.size.x if bar.visible else 0.0)
	var fitting := floori((room - MARGIN * 2 + CARD_GAP) / (CARD_SIZE.x + CARD_GAP))
	var columns := clampi(fitting, 1, MAX_COLUMNS)
	var width := columns * CARD_SIZE.x + (columns - 1) * CARD_GAP
	var side := maxi(0, floori((room - width) / 2))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)


## The app's logo, name and version
func _make_header() -> Control:
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.custom_minimum_size = Vector2(48, 48)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(logo)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	header.add_child(names)
	var app_name := Label.new()
	app_name.text = ProjectSettings.get_setting("application/config/name")
	app_name.add_theme_font_size_override(&"font_size", 22)
	app_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	names.add_child(app_name)
	var version := Label.new()
	version.text = "v" + AboutDialog.get_version()
	version.theme_type_variation = &"StatusLabel"
	version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	names.add_child(version)
	return header


## The drop zone: a big icon, where to drop files, and the buttons
func _build_drop_zone() -> void:
	for side: String in ["left", "top", "right", "bottom"]:
		drop_zone.add_theme_constant_override("margin_" + side, 24)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	drop_zone.add_child(box)
	var icon := TextureRect.new()
	icon.texture = _big_icon(DROP_ICON)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.modulate.a = 0.6
	box.add_child(icon)
	drop_hint.text = "Drop images, folders or a .sbelli project here"
	drop_hint.theme_type_variation = &"EmptyHint"
	drop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(drop_hint)
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	for id in BUTTON_ACTIONS:
		if Actions.has(id):
			action_buttons[id] = _action_button(id)
	for id in action_buttons:
		if id == &"add_folder" and action_buttons.has(&"add_sprites"):
			continue
		if id == &"add_sprites" and action_buttons.has(&"add_folder"):
			var pair := HBoxContainer.new()
			pair.add_theme_constant_override("separation", PAIR_GAP)
			pair.add_child(action_buttons[id])
			pair.add_child(action_buttons[&"add_folder"])
			buttons.add_child(pair)
		else:
			buttons.add_child(action_buttons[id])
	box.add_child(buttons)


## A button running action [param id], with its name and icon, or only its icon for Add
## Folder
func _action_button(id: StringName) -> Button:
	var action := Actions.get_action(id)
	var button := Button.new()
	button.icon = action.icon
	if id == &"add_folder":
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.custom_minimum_size.x = BUTTON_HEIGHT
	else:
		button.text = action.label
	Actions.set_tooltip(button, id)
	button.custom_minimum_size.y = BUTTON_HEIGHT
	button.pressed.connect(func() -> void: Actions.run(id))
	return button


## A button that opens [param file], with its thumbnail, name, folder and when it was
## changed, and a button to forget it. A missing file can't be opened: it says it's not
## found, with a button to locate it (see [method locate]). Right-clicking it, or the menu
## key while it has focus, opens its menu (see [method open_menu]), and Delete forgets it.
func _make_card(file: String) -> Button:
	var found := FileAccess.file_exists(file)
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = file
	card.disabled = not found
	card.pressed.connect(func() -> void: file_chosen.emit(file))
	card.gui_input.connect(_on_card_input.bind(card, file))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	var background := ColorRect.new()
	background.custom_minimum_size = THUMBNAIL_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(background)
	var thumbnail := TextureRect.new()
	thumbnail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(thumbnail)
	thumbnails[file] = thumbnail

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = file.get_file()
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var close := Button.new()
	close.theme_type_variation = &"ToolbarButton"
	close.icon = CLOSE_ICON
	close.tooltip_text = "Remove from Recent Files"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(forget.bind(file))
	name_row.add_child(close)
	var folder_label := Label.new()
	folder_label.text = file.get_base_dir() if found else L10n.mark("Not found")
	folder_label.theme_type_variation = &"StatusLabel" if found else &"ErrorLabel"
	folder_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if found:
		# The end of a path tells more than its start
		folder_label.resized.connect(
			func() -> void: folder_label.text = trim_start(folder_label, file.get_base_dir())
		)
		box.add_child(folder_label)
		var modified := FileAccess.get_modified_time(file)
		var age := Label.new()
		age.text = describe_age(modified, int(Time.get_unix_time_from_system()))
		age.theme_type_variation = &"StatusLabel"
		age.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		box.add_child(age)
		card.tooltip_text += "\n" + tr("Changed %s") % format_date(modified, true)
		return card
	var missing_row := HBoxContainer.new()
	missing_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(missing_row)
	folder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	missing_row.add_child(folder_label)
	# A browser has no recent files to locate
	if not in_browser:
		var locate_button := Button.new()
		locate_button.text = "Locate…"
		locate_button.tooltip_text = "Find where the file is now"
		locate_button.theme_type_variation = &"ToolbarButton"
		locate_button.focus_mode = Control.FOCUS_NONE
		locate_button.pressed.connect(locate.bind(file))
		missing_row.add_child(locate_button)
	return card


func _on_card_input(event: InputEvent, card: Button, file: String) -> void:
	var mouse := event as InputEventMouseButton
	if mouse and mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
		open_menu(file, card.get_screen_transform() * mouse.position)
		card.accept_event()
	var key := event as InputEventKey
	if not key or not key.pressed:
		return
	if key.keycode == KEY_DELETE and key.get_modifiers_mask() == 0:
		_forget_keeping_focus(file)
		card.accept_event()
	elif key.keycode == KEY_MENU or (key.keycode == KEY_F10 and key.shift_pressed):
		open_menu(file, card.get_screen_transform() * Vector2(0, card.size.y / 2))
		card.accept_event()
	# A missing file can't be opened, but it can be located
	elif card.disabled and key.is_action_pressed(&"ui_accept") and not in_browser:
		locate(file)
		card.accept_event()


## Shows the thumbnail of [param file], or an icon while it has none, made from an image
## file when it's missing, see [Thumbnails]
func _show_thumbnail(file: String) -> void:
	var thumbnail := thumbnails[file]
	var found := FileAccess.file_exists(file)
	var img := Thumbnails.load_image(file) if found else null
	thumbnail.modulate.a = 1.0 if found else 0.5
	# On the preview's background, like the sheet on the canvas. An icon is on the card's.
	var background := thumbnail.get_parent() as ColorRect
	background.color = Settings.get_value(&"background_color") if img else Color.TRANSPARENT
	if img:
		thumbnail.texture = ImageTexture.create_from_image(img)
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Small sheets are made bigger, pixel art stays sharp
		var fits := img.get_width() <= THUMBNAIL_SIZE.x and img.get_height() <= THUMBNAIL_SIZE.y
		thumbnail.texture_filter = (
			CanvasItem.TEXTURE_FILTER_NEAREST if fits else CanvasItem.TEXTURE_FILTER_LINEAR
		)
		return
	var is_project := ProjectFile.is_project_path(file)
	thumbnail.texture = _big_icon(PROJECT_ICON if is_project else IMAGE_ICON)
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var target := Thumbnails.get_path_for(file)
	if found and not is_project and not _asked.has(target):
		_asked[target] = true
		Thumbnails.make_for_image(file)


## [param text] with its start cut off, after an ellipsis, when [param label] is too
## narrow for it
static func trim_start(label: Label, text: String) -> String:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var width := label.size.x
	var measure := func(shown: String) -> float:
		return font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if width <= 0 or measure.call(text) <= width:
		return text
	for start in range(1, text.length()):
		var shown := "…" + text.substr(start)
		if measure.call(shown) <= width:
			return shown
	return "…"


## [param icon] drawn three times bigger, still sharp
static func _big_icon(icon: Texture2D) -> Texture2D:
	var dpi := icon as DPITexture
	if not dpi:
		return icon
	var big := dpi.duplicate() as DPITexture
	big.base_scale = dpi.base_scale * 3
	return big
