class_name AnimationPanel
extends PanelContainer
## The animation panel under the sheet's preview, in three columns: the preview
## ([AnimationPreview]), the list of animations with the selected frames at the top,
## and the chosen animation's details ([AnimationDetail]). Choosing in the list plays it;
## each animation is listed with a swatch of its colour. Above the list, New makes an
## animation, and the chosen one can be duplicated, mirrored or deleted, each as one step
## to undo. Frames dropped on the list, off the animations, or on the details while no
## animation is chosen, make a new animation.
## It's the Animation dock of the [BottomDock] under the sheet's preview, shown with its
## button there or P. It's hidden until the sheet has animations, then shown once; after
## that it stays as it was left, see the animation_panel setting.

const FRAMES_ICON := preload("res://assets/icons/FileList.svg")
const ADD_ICON := preload("res://assets/icons/Add.svg")
const DUPLICATE_ICON := preload("res://assets/icons/Duplicate.svg")
const MIRROR_ICON := preload("res://assets/icons/MirrorX.svg")
const REMOVE_ICON := preload("res://assets/icons/Remove.svg")
const ANIMATION_ICON := preload("res://assets/icons/Animation.svg")
## The narrowest the list gets
const MIN_LIST_WIDTH := 120

## Where selected frames come from
var preview: SpritesheetPreview
## The docks it's in, see [method setup]
var dock: BottomDock
## Its button in the docks' row
var dock_button: Button
var animation_preview := AnimationPreview.new()
var list := ItemList.new()
var new_button := Button.new()
var duplicate_button := Button.new()
var mirror_button := Button.new()
var delete_button := Button.new()
var detail := AnimationDetail.new()
## The preview next to the list and details, and the list next to the details
var columns := HSplitContainer.new()
var list_split := HSplitContainer.new()
var list_sidebar: SidebarSplit

## Whether showing or hiding it is remembered, see [method set_expanded]
var _remember := true
## The animation chosen in the list, or -1 for the selected frames
var _selected := -1
var _list_column := VBoxContainer.new()
## New, then the buttons for the chosen animation
var _list_buttons := HBoxContainer.new()


func _init() -> void:
	theme_type_variation = &"SidebarPanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_child(columns)
	add_child(margin)
	columns.add_child(animation_preview)
	list_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(list_split)

	_list_column.custom_minimum_size.x = MIN_LIST_WIDTH
	list_split.add_child(_list_column)
	_build_list_buttons()
	var list_margin := MarginContainer.new()
	list_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_bottom", 6)
	list.fixed_icon_size = Vector2i(16, 16)
	list.add_theme_font_size_override("font_size", 13)
	list_margin.add_child(list)
	_list_column.add_child(list_margin)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_split.add_child(detail)

	list.item_selected.connect(func(item: int) -> void: select_animation(item - 1))
	list.set_drag_forwarding(Callable(), _can_drop_on_list, _drop_on_list)
	detail.frames_dropped.connect(add_animation)
	new_button.pressed.connect(add_animation)
	duplicate_button.pressed.connect(duplicate_animation)
	mirror_button.pressed.connect(mirror_animation)
	delete_button.pressed.connect(remove_animation)


## New at the top of the list, and the buttons for the chosen animation next to it
func _build_list_buttons() -> void:
	new_button.text = "New"
	new_button.icon = ADD_ICON
	new_button.tooltip_text = "A new animation of the selected frames, or of every frame"
	_list_buttons.add_child(new_button)
	duplicate_button.icon = DUPLICATE_ICON
	duplicate_button.tooltip_text = "Duplicate the animation"
	mirror_button.icon = MIRROR_ICON
	mirror_button.tooltip_text = "Mirrored copy: the frames flipped into a new row"
	delete_button.icon = REMOVE_ICON
	delete_button.tooltip_text = "Delete the animation"
	for button: Button in [duplicate_button, mirror_button, delete_button]:
		button.theme_type_variation = &"ToolbarButton"
		button.focus_mode = Control.FOCUS_NONE
		_list_buttons.add_child(button)
	_list_column.add_child(_list_buttons)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_fit_list_buttons.call_deferred()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and preview and list.item_count > 0:
		list.set_item_text(0, animation_preview.get_selection_title())
		list.set_item_tooltip(0, tr("Plays the selected frames, or every frame"))
		detail.refresh()


## Shows the animations of [param sheet_preview]'s sheet and plays its selected frames.
## Adds it to the [BottomDock] it's in.
func setup(sheet_preview: SpritesheetPreview) -> void:
	preview = sheet_preview
	animation_preview.preview = preview
	# To drop them on a timeline or the list, which opens when they're held over its button
	preview.drag_frames_out = true
	dock = get_parent() as BottomDock
	dock_button = dock.add_dock(self, L10n.mark("Animation"), ANIMATION_ICON)
	Actions.set_tooltip(
		dock_button, &"toggle_animation", L10n.mark("Show or hide the animation panel")
	)
	dock.dock_changed.connect(_on_dock_changed)
	columns.drag_ended.connect(_on_preview_width_dragged)
	columns.get_drag_area_control().gui_input.connect(_on_preview_handle_input)
	list_sidebar = SidebarSplit.new(list_split, _list_column, &"animation_list_width")
	Global.spritesheet.updated.connect(refresh)
	preview.selection_changed.connect(_refresh_selection_title)
	columns.resized.connect(_apply_preview_width)
	# Another sheet starts with its frames playing
	Global.document.loaded.connect(func(_view: Dictionary) -> void: select_animation(-1))
	set_expanded(Settings.get_value(&"animation_panel") == "open", false)
	refresh()


func is_expanded() -> bool:
	return dock != null and dock.get_shown() == self


## Shows the panel in its dock, or hides it when [param expanded] is false, and
## [param remember]s it
func set_expanded(expanded: bool, remember := true) -> void:
	_remember = remember
	if expanded:
		dock.show_dock(self)
	elif is_expanded():
		dock.show_dock(null)
	_remember = true


func toggle() -> void:
	set_expanded(not is_expanded())


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
	_update_list_buttons()


## Index of the chosen animation, or -1 for the selected frames
func get_selected() -> int:
	return _selected


## A new animation of [param cells], named after what their names share, or of the
## selected frames, or of every frame, chosen for editing
func add_animation(cells: Array[Vector2i] = []) -> void:
	var sheet := Global.spritesheet
	var anim_name := sheet.get_unique_animation_name()
	if cells:
		var frame_names := PackedStringArray()
		for cell in cells:
			frame_names.append(sheet.frames[cell].resource_name if sheet.has_frame(cell) else "")
		anim_name = SheetAnimation.default_name(frame_names, sheet.get_animation_names())
	elif preview:
		cells = preview.get_selected_coords()
	if cells.is_empty():
		cells = sheet.get_sorted_coords()
	var index: int = Global.document.perform(
		L10n.mark("New animation"),
		sheet.add_animation.bind(SheetAnimation.create(anim_name, cells))
	)
	select_animation(index)
	detail.focus_name()


## Adds a copy of the chosen animation and chooses it, see
## [method Spritesheet.duplicate_animation]
func duplicate_animation() -> void:
	if _selected >= 0:
		select_animation(
			Global.document.perform(
				L10n.mark("Duplicate animation"),
				Global.spritesheet.duplicate_animation.bind(_selected)
			)
		)


## Adds a mirrored copy of the chosen animation and chooses it, see
## [method SheetAnimation.mirror]
func mirror_animation() -> void:
	if _selected < 0:
		return
	var added: int = Global.document.perform(
		L10n.mark("Mirror animation"), SheetAnimation.mirror.bind(Global.spritesheet, _selected)
	)
	if added >= 0:
		select_animation(added)


func remove_animation() -> void:
	if _selected >= 0:
		Global.document.perform(
			L10n.mark("Delete animation"), Global.spritesheet.remove_animation.bind(_selected)
		)


## Rebuilds the list of animations, keeping the chosen one
func refresh() -> void:
	var animations := Global.spritesheet.animations
	list.clear()
	list.add_item(animation_preview.get_selection_title(), FRAMES_ICON)
	list.set_item_tooltip(0, tr("Plays the selected frames, or every frame"))
	for animation in animations:
		list.add_item(animation.name, AppTheme.swatch(animation.color))
		# A name, even one that reads like text that has a translation
		list.set_item_auto_translate_mode(list.item_count - 1, Node.AUTO_TRANSLATE_MODE_DISABLED)
	# After deleting the last animation, the one before it
	_selected = mini(_selected, animations.size() - 1)
	list.select(_selected + 1)
	animation_preview.select_animation(_selected)
	detail.show_animation(_selected)
	_open_when_animated()
	_update_list_buttons()


## The first time the sheet has animations, the panel opens
func _open_when_animated() -> void:
	if (
		Settings.get_value(&"animation_panel") == "auto"
		and not Global.spritesheet.animations.is_empty()
	):
		set_expanded(true)


func _on_dock_changed() -> void:
	if _remember:
		Settings.set_value(&"animation_panel", "open" if is_expanded() else "closed")
	Actions.refresh()


## The buttons for the chosen animation show while one is chosen
func _update_list_buttons() -> void:
	for button: Button in [duplicate_button, mirror_button, delete_button]:
		button.visible = _selected >= 0


## Keeps room for every button next to New, so the list is as wide with or without them
func _fit_list_buttons() -> void:
	var width := 0.0
	for button: Button in _list_buttons.get_children():
		width += button.get_combined_minimum_size().x
	var separation := _list_buttons.get_theme_constant(&"separation")
	_list_buttons.custom_minimum_size.x = (
		width + separation * (_list_buttons.get_child_count() - 1)
	)


## Frames of the sheet dropped on the list, but not on an animation, make a new one
func _can_drop_on_list(at: Vector2, data: Variant) -> bool:
	if not AnimationTimeline.is_frames_drag(data):
		return false
	return list.get_item_at_position(at, true) < 1


func _drop_on_list(_at: Vector2, data: Variant) -> void:
	var cells: Array[Vector2i] = []
	cells.assign(data.cells)
	add_animation(cells)


func _refresh_selection_title() -> void:
	if list.item_count > 0:
		list.set_item_text(0, animation_preview.get_selection_title())


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
