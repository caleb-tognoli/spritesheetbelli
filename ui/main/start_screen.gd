class_name StartScreen
extends Panel
## What the canvas shows while nothing is open (see [method Document.is_blank]): buttons
## to open a file or add sprites, and the recent files with their thumbnails (see
## [Thumbnails]), to open or forget. Files dropped on it are opened like on the canvas.
## A browser has no recent files, so it only has the buttons and the drop hint.

## Emitted when a recent file is clicked
signal file_chosen(path: String)

## The actions of the buttons, so their names, icons and shortcuts match the menus
const BUTTON_ACTIONS: Array[StringName] = [&"open", &"add_sprites", &"add_spritesheet"]
const CLOSE_ICON := preload("res://assets/icons/Close.svg")
## Shown until a recent file has a thumbnail, or when it's missing
const PROJECT_ICON := preload("res://assets/icons/SpriteSheet.svg")
const IMAGE_ICON := preload("res://assets/icons/Image.svg")
const CARD_SIZE := Vector2(184, 190)
const THUMBNAIL_SIZE := Vector2(168, 126)

## Whether it's in a browser, which has no recent files to list
var in_browser := WebFiles.is_web()
## Above the recent files, for notices like work to recover (see [RecoveryNotice]), added
## with [method add_notice]. Hidden while none shows.
var notices := VBoxContainer.new()
var buttons := HFlowContainer.new()
var recent_heading := Label.new()
var recent_list := HFlowContainer.new()
var drop_hint := Label.new()
## The card of each recent file listed, by path
var cards: Dictionary[String, Button] = {}
## The thumbnail of each recent file listed, by path
var thumbnails: Dictionary[String, TextureRect] = {}
## Thumbnails asked for, so an image that can't be loaded isn't tried again and again
var _asked: Dictionary[String, bool] = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	for id in BUTTON_ACTIONS:
		if Actions.has(id):
			buttons.add_child(_action_button(id))
	column.add_child(buttons)
	notices.visible = false
	column.add_child(notices)
	recent_heading.text = "Recent Files"
	recent_heading.theme_type_variation = &"HeaderSmall"
	recent_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(recent_heading)
	recent_list.alignment = FlowContainer.ALIGNMENT_CENTER
	recent_list.add_theme_constant_override("h_separation", 10)
	recent_list.add_theme_constant_override("v_separation", 10)
	column.add_child(recent_list)
	drop_hint.text = "Drop images, folders or a .sbelli project here"
	drop_hint.theme_type_variation = &"StatusLabel"
	drop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(drop_hint)

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


## Shows it while nothing is open, see [method Document.is_blank]
func update() -> void:
	visible = Global.document.is_blank()


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
	recent_heading.visible = not files.is_empty()
	recent_list.visible = not files.is_empty()


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


func _action_button(id: StringName) -> Button:
	var action := Actions.get_action(id)
	var button := Button.new()
	button.text = action.label
	button.icon = action.icon
	button.tooltip_text = Actions.get_tooltip(id)
	button.custom_minimum_size.y = 34
	button.pressed.connect(func() -> void: Actions.run(id))
	return button


## A button that opens [param file], with its thumbnail, name and folder, and a button
## to forget it. A missing file can't be opened and says it's not found.
func _make_card(file: String) -> Button:
	var found := FileAccess.file_exists(file)
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = file
	card.disabled = not found
	card.pressed.connect(func() -> void: file_chosen.emit(file))
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
	folder_label.text = file.get_base_dir() if found else "Not found"
	folder_label.theme_type_variation = &"StatusLabel" if found else &"ErrorLabel"
	folder_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if found:
		# The end of a path tells more than its start
		folder_label.resized.connect(
			func() -> void: folder_label.text = trim_start(folder_label, file.get_base_dir())
		)
	box.add_child(folder_label)
	return card


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
