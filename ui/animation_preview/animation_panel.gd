class_name AnimationPanel
extends PanelContainer
## The animation panel under the sheet's preview, in three columns: the preview
## ([AnimationPreview]), the list of animations with the selected frames at the top,
## and the chosen animation's details ([AnimationDetail]). Choosing in the list plays it;
## each animation is listed with a swatch of its colour.
## The handle on its top edge makes it taller, up to half the window; it remembers its
## height. Collapsed, it's a bar with the name of what plays, a thumbnail and play/pause.
## It starts collapsed until the sheet has animations, then opens once; after that it
## stays as it was left, see the animation_panel setting.

const FRAMES_ICON := preload("res://assets/icons/FileList.svg")
const ADD_ICON := preload("res://assets/icons/Add.svg")
const EXPANDED_ICON := preload("res://assets/icons/GuiTreeArrowDown.svg")
const COLLAPSED_ICON := preload("res://assets/icons/GuiTreeArrowRight.svg")
const MIN_HEIGHT := 160
## The narrowest the list gets
const MIN_LIST_WIDTH := 120

## Where selected frames come from
var preview: SpritesheetPreview
var animation_preview := AnimationPreview.new()
var list := ItemList.new()
var new_button := Button.new()
var detail := AnimationDetail.new()
## The bar on top, which is all that shows when collapsed
var header := HBoxContainer.new()
var collapse_button := Button.new()
var title_label := Label.new()
var thumbnail := TextureRect.new()
var play_button := Button.new()
## The preview next to the list and details, and the list next to the details
var columns := HSplitContainer.new()
var list_split := HSplitContainer.new()
var list_sidebar: SidebarSplit

## The split between the sheet's preview and this panel
var _split: SplitContainer
var _expanded := false
## The animation chosen in the list, or -1 for the selected frames
var _selected := -1
var _list_column := VBoxContainer.new()


func _init() -> void:
	theme_type_variation = &"SidebarPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 4)
	header_margin.add_theme_constant_override("margin_right", 4)
	header_margin.add_child(header)
	box.add_child(header_margin)
	collapse_button.theme_type_variation = &"ToolbarButton"
	collapse_button.text = "Animation"
	collapse_button.focus_mode = Control.FOCUS_NONE
	collapse_button.pressed.connect(toggle)
	header.add_child(collapse_button)
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumbnail.custom_minimum_size = Vector2(20, 20)
	header.add_child(thumbnail)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.theme_type_variation = &"StatusLabel"
	header.add_child(title_label)
	play_button.theme_type_variation = &"ToolbarButton"
	play_button.focus_mode = Control.FOCUS_NONE
	play_button.pressed.connect(
		func() -> void: animation_preview.player.playing = not animation_preview.player.playing
	)
	header.add_child(play_button)

	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	columns.add_child(animation_preview)
	list_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(list_split)

	_list_column.custom_minimum_size.x = MIN_LIST_WIDTH
	list_split.add_child(_list_column)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(16, 16)
	list.add_theme_font_size_override("font_size", 13)
	_list_column.add_child(list)
	new_button.text = "New"
	new_button.icon = ADD_ICON
	new_button.tooltip_text = "A new animation of the selected frames, or of every frame"
	var new_margin := MarginContainer.new()
	new_margin.add_theme_constant_override("margin_bottom", 6)
	new_margin.add_child(new_button)
	_list_column.add_child(new_margin)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_split.add_child(detail)

	list.item_selected.connect(func(item: int) -> void: select_animation(item - 1))
	new_button.pressed.connect(add_animation)
	detail.animation_added.connect(select_animation)
	animation_preview.title_changed.connect(func(_title: String) -> void: _update_header())
	animation_preview.player.frame_changed.connect(
		func(_cell: Vector2i) -> void: _update_thumbnail()
	)
	animation_preview.player.playing_changed.connect(func(_playing: bool) -> void: _update_header())


## Shows the animations of [param sheet_preview]'s sheet and plays its selected frames
func setup(sheet_preview: SpritesheetPreview) -> void:
	preview = sheet_preview
	animation_preview.preview = preview
	detail.preview = preview
	# Frames dragged out of the sheet go to the timeline of the animation edited
	preview.frames_dragged_out.connect(
		func(coords: Array[Vector2i]) -> void:
			force_drag(
				AnimationTimeline.frames_drag_data(coords),
				AnimationTimeline.drag_preview(Global.spritesheet, coords)
			)
	)
	_split = get_parent() as SplitContainer
	_split.drag_ended.connect(_on_height_dragged)
	_split.dragged.connect(func(_offset: int) -> void: _clamp_height())
	_split.get_drag_area_control().gui_input.connect(_on_handle_input)
	columns.drag_ended.connect(_on_preview_width_dragged)
	columns.get_drag_area_control().gui_input.connect(_on_preview_handle_input)
	list_sidebar = SidebarSplit.new(list_split, _list_column, &"animation_list_width")
	Global.spritesheet.updated.connect(refresh)
	preview.selection_changed.connect(_refresh_selection_title)
	# The number of frames played can change with the selection
	preview.preview_updated.connect(_update_header)
	get_viewport().size_changed.connect(apply_height)
	columns.resized.connect(_apply_preview_width)
	# Another sheet starts with its frames playing
	Global.document.loaded.connect(func(_view: Dictionary) -> void: select_animation(-1))
	set_expanded(Settings.get_value(&"animation_panel") == "open", false)
	refresh()


func is_expanded() -> bool:
	return _expanded


## Shows the whole panel, or only its bar when [param expanded] is false, and
## [param remember]s it
func set_expanded(expanded: bool, remember := true) -> void:
	_expanded = expanded
	if remember:
		Settings.set_value(&"animation_panel", "open" if expanded else "closed")
	columns.visible = expanded
	collapse_button.icon = EXPANDED_ICON if expanded else COLLAPSED_ICON
	collapse_button.tooltip_text = Actions.get_tooltip(
		&"toggle_animation",
		"Collapse the animation panel" if expanded else "Open the animation panel"
	)
	# Collapsed, it keeps playing in the bar's thumbnail
	animation_preview.player.play_hidden = not expanded
	apply_height()
	_update_header()
	_update_drag_out()
	Actions.refresh()


func toggle() -> void:
	set_expanded(not _expanded)


## Opens the panel and starts editing the chosen animation, or the first
func edit() -> void:
	set_expanded(true)
	if detail.get_animation_index() < 0 and not Global.spritesheet.animations.is_empty():
		select_animation(0)
	if detail.get_animation_index() >= 0:
		detail.focus_name()
	else:
		new_button.grab_focus()


## Plays and shows the animation at [param index], or the selected frames with -1
func select_animation(index: int) -> void:
	if index >= Global.spritesheet.animations.size():
		index = -1
	_selected = index
	list.select(index + 1)
	list.ensure_current_is_visible()
	animation_preview.select_animation(index)
	detail.show_animation(index)
	_update_drag_out()


## Index of the chosen animation, or -1 for the selected frames
func get_selected() -> int:
	return _selected


## A new animation of the selected frames, or of every frame, chosen for editing
func add_animation() -> void:
	var sheet := Global.spritesheet
	var cells := preview.get_selected_coords() if preview else ([] as Array[Vector2i])
	if cells.is_empty():
		cells = sheet.get_sorted_coords()
	var anim_name := sheet.get_unique_animation_name()
	var index: int = Global.document.perform(
		"New animation", sheet.add_animation.bind(SheetAnimation.create(anim_name, cells))
	)
	select_animation(index)
	detail.focus_name()


## Rebuilds the list of animations, keeping the chosen one
func refresh() -> void:
	var animations := Global.spritesheet.animations
	list.clear()
	list.add_item(animation_preview.get_selection_title(), FRAMES_ICON)
	list.set_item_tooltip(0, tr("Plays the selected frames, or every frame"))
	for animation in animations:
		list.add_item(animation.name, AppTheme.swatch(animation.color))
	# After deleting the last animation, the one before it
	_selected = mini(_selected, animations.size() - 1)
	list.select(_selected + 1)
	animation_preview.select_animation(_selected)
	detail.show_animation(_selected)
	_open_when_animated()
	_update_drag_out()


## The height the panel gets: the remembered one, within its limits
func get_height() -> int:
	return clampi(Settings.get_value(&"animation_panel_height"), MIN_HEIGHT, get_max_height())


## Half the window, but never below the smallest height
func get_max_height() -> int:
	return maxi(MIN_HEIGHT, int(get_viewport_rect().size.y / 2))


## Gives the panel its remembered height, or only its bar when collapsed
func apply_height() -> void:
	if not _split:
		return
	custom_minimum_size.y = MIN_HEIGHT if _expanded else 0
	_split.collapsed = not _expanded
	_split.dragging_enabled = _expanded
	_split.split_offset = -get_height() if _expanded else 0


## The first time the sheet has animations, the panel opens
func _open_when_animated() -> void:
	if (
		Settings.get_value(&"animation_panel") == "auto"
		and not Global.spritesheet.animations.is_empty()
	):
		set_expanded(true)


## Frames are dragged out of the sheet while there's a timeline to drop them on
func _update_drag_out() -> void:
	if preview:
		preview.drag_frames_out = _expanded and detail.get_animation_index() >= 0


func _refresh_selection_title() -> void:
	if list.item_count > 0:
		list.set_item_text(0, animation_preview.get_selection_title())


func _update_header() -> void:
	var player := animation_preview.player
	title_label.text = animation_preview.get_title()
	title_label.visible = not _expanded
	thumbnail.visible = not _expanded
	play_button.visible = not _expanded
	play_button.icon = FramePlayer.PAUSE_ICON if player.playing else FramePlayer.PLAY_ICON
	play_button.tooltip_text = "Pause" if player.playing else "Play"
	play_button.disabled = player.get_cells().size() < 2
	_update_thumbnail()


func _update_thumbnail() -> void:
	if thumbnail.visible:
		thumbnail.texture = animation_preview.player.get_current_texture()


## Keeps the height dragged within its limits
func _clamp_height() -> void:
	if -_split.split_offset > get_max_height():
		_split.split_offset = -get_max_height()


func _on_height_dragged() -> void:
	var height := clampi(-_split.split_offset, MIN_HEIGHT, get_max_height())
	Settings.set_value(&"animation_panel_height", height)
	apply_height()


func _on_handle_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
		# Not the start of a drag: back to the first height
		_split.get_drag_area_control().accept_event()
		Settings.set_value(&"animation_panel_height", Settings.DEFAULTS[&"animation_panel_height"])
		apply_height()


## The preview is as wide as it's tall, unless dragged wider or narrower
func _apply_preview_width() -> void:
	var width: int = Settings.get_value(&"animation_preview_width")
	columns.split_offset = width if width > 0 else roundi(columns.size.y)


func _on_preview_width_dragged() -> void:
	var width := roundi(maxf(columns.split_offset, animation_preview.get_combined_minimum_size().x))
	# Close to square counts as square, so it keeps up with the height
	var square := absi(width - roundi(columns.size.y)) <= 4
	Settings.set_value(&"animation_preview_width", 0 if square else width)
	_apply_preview_width()


func _on_preview_handle_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
		columns.get_drag_area_control().accept_event()
		Settings.set_value(&"animation_preview_width", 0)
		_apply_preview_width()
