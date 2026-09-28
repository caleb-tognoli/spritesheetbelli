class_name SpritesPanel
extends PanelContainer
## Lists every frame with a thumbnail, its name and size, under the first animation showing
## it, or under its row. Selecting frames here selects them in the preview and the other way
## round; clicking a group's name selects its frames, and its arrow folds it.
## Frames are renamed by double-clicking their name or F2, found by typing in the search field, and
## pinned with the button on each frame in the packed layout. Right-clicking them offers
## the actions given to [method set_context_actions].

const THUMBNAIL_SIZE := 32
const PIN_ICON := preload("res://assets/icons/Pin.svg")
const PIN_BUTTON := 0
## Where frames in no animation are listed, see [method group_frames]
const NO_ANIMATION := "none"

## Where the frames are selected, and shown
var preview: SpritesheetPreview
var search := LineEdit.new()
## Lists the frames by row rather than by animation
var by_row_button := Button.new()
var tree := Tree.new()
var close_button := Button.new()
var context_menu := ActionPopupMenu.new()

var _thumbnails: Dictionary[Image, Texture2D] = {}
## The selection's highlight on the name, on the size, and on the size and pin, without
## and with focus on the list: the list highlights each cell on its own, rounded, and
## leaves out the pin, so the selected frames get these across the row instead
var _highlights: Dictionary[bool, Array] = {}
## Whether the selection is being copied between the list and the preview, so it isn't
## copied back
var _syncing := false
## The groups folded in the list, by key, see [method group_frames]. Kept while the app runs.
var _collapsed: Dictionary[String, bool] = {}


func _init() -> void:
	theme_type_variation = &"SidebarPanel"
	custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	add_child(box)

	var header := HBoxContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_child(header)
	box.add_child(margin)
	var title := Label.new()
	title.text = "Sprites"
	title.theme_type_variation = &"HeaderSmall"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_button.flat = true
	close_button.icon = preload("res://assets/icons/Close.svg")
	close_button.tooltip_text = Actions.get_tooltip(&"toggle_sprites", "Hide the sprites")
	header.add_child(close_button)

	search.placeholder_text = "Search by name"
	search.clear_button_enabled = true
	search.right_icon = preload("res://assets/icons/Search.svg")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	by_row_button.flat = true
	by_row_button.toggle_mode = true
	by_row_button.icon = preload("res://assets/icons/Rows.svg")
	by_row_button.tooltip_text = "Group by row instead of by animation"
	var search_row := HBoxContainer.new()
	search_row.add_child(search)
	search_row.add_child(by_row_button)
	var search_margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		search_margin.add_theme_constant_override("margin_" + side, 6)
	search_margin.add_child(search_row)
	box.add_child(search_margin)

	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.add_theme_font_size_override("font_size", 13)
	tree.columns = 2
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 100)
	tree.tooltip_text = "Double-click a name to rename the frame"
	# Right-clicking a frame outside the selection selects it, like in the preview
	tree.allow_rmb_select = true
	box.add_child(tree)
	context_menu.theme = preload("res://resources/themes/popup_menu_theme.tres")
	add_child(context_menu)


func _ready() -> void:
	close_button.pressed.connect(func() -> void: Settings.set_value(&"show_sprites", false))
	search.text_changed.connect(refresh.unbind(1))
	by_row_button.set_pressed_no_signal(Settings.get_value(&"sprites_by_row"))
	by_row_button.toggled.connect(func(on: bool) -> void: Settings.set_value(&"sprites_by_row", on))
	Settings.changed.connect(_on_setting_changed)
	tree.item_collapsed.connect(_on_item_collapsed)
	tree.multi_selected.connect(_on_tree_multi_selected)
	tree.item_activated.connect(_edit_selected)
	tree.item_edited.connect(_on_item_edited)
	tree.button_clicked.connect(_on_button_clicked)
	tree.gui_input.connect(_on_tree_input)
	tree.focus_entered.connect(_highlight_all)
	tree.focus_exited.connect(_highlight_all)
	# The selected frames are dragged, in the listed order, e.g. into an animation
	tree.set_drag_forwarding(_get_drag_data_of_tree, Callable(), Callable())
	Global.spritesheet.updated.connect(refresh)
	visibility_changed.connect(refresh)
	if preview:
		preview.selection_changed.connect(_show_selection)
	refresh()


## Lists the frames again
func refresh() -> void:
	if not visible or not is_inside_tree():
		return
	var sheet := Global.spritesheet
	tree.clear()
	var root := tree.create_item()
	var filter := search.text.strip_edges().to_lower()
	var alive := {}
	for group in group_frames(sheet, Settings.get_value(&"sprites_by_row")):
		# Only groups with frames found are listed
		var header: TreeItem = null
		for coord: Vector2i in group.coords:
			alive[sheet.frames[coord]] = true
			var label := frame_label(sheet, coord)
			if filter and filter not in label.to_lower():
				continue
			if not header:
				header = _add_header(root, group)
			_add_frame(header, coord, label)
		if header:
			header.set_text(1, str(header.get_child_count()))
			# Frames found are shown even in folded groups
			if not filter:
				header.collapsed = _collapsed.get(group.key, false)
	for img: Image in _thumbnails.keys():
		if not alive.has(img):
			_thumbnails.erase(img)
	_show_selection()


## Every frame of [param sheet] in groups, each a dictionary with a "key" that stays the same
## while the sheet changes, a "title" and the frames' "coords". By animation, in the sheet's
## order, a frame is in the first one showing it, at its first place in play order; frames in
## none follow in reading order. With [param by_row], each row is a group. Groups without
## frames are left out.
static func group_frames(sheet: Spritesheet, by_row := false) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	if by_row:
		for coord in sheet.get_sorted_coords():
			var key := "row:%d" % coord.y
			if groups.is_empty() or groups[-1].key != key:
				var title := TranslationServer.translate("Row %d") % coord.y
				var coords: Array[Vector2i] = []
				groups.append({"key": key, "title": title, "coords": coords})
			groups[-1].coords.append(coord)
		return groups
	var listed := {}
	for animation in sheet.animations:
		var coords: Array[Vector2i] = []
		for cell in animation.get_frame_cells(sheet):
			if not listed.has(cell):
				listed[cell] = true
				coords.append(cell)
		if coords:
			groups.append(
				{"key": "animation:" + animation.name, "title": animation.name, "coords": coords}
			)
	var rest: Array[Vector2i] = []
	for coord in sheet.get_sorted_coords():
		if not listed.has(coord):
			rest.append(coord)
	if rest:
		var title := TranslationServer.translate("No animation")
		groups.append({"key": NO_ANIMATION, "title": title, "coords": rest})
	return groups


## Adds the name of [param group], from [method group_frames], with the number of frames
## listed under it. It isn't a frame: clicking it selects its frames instead.
func _add_header(root: TreeItem, group: Dictionary) -> TreeItem:
	var header := tree.create_item(root)
	header.set_text(0, group.title)
	header.set_metadata(0, group.key)
	header.set_tooltip_text(0, tr("Click to select these frames"))
	header.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	var muted := get_theme_color("font_color", &"StatusLabel")
	for column in tree.columns:
		header.set_selectable(column, false)
		header.set_custom_color(column, muted)
	return header


## Lists the frame at [param coord] under [param header], named [param label]
func _add_frame(header: TreeItem, coord: Vector2i, label: String) -> void:
	var sheet := Global.spritesheet
	var img := sheet.frames[coord]
	var item := tree.create_item(header)
	# No room is kept for an arrow, so frames line up under their group's name
	item.disable_folding = true
	item.set_text(0, label)
	item.set_icon(0, _thumbnail(img))
	item.set_icon_max_width(0, THUMBNAIL_SIZE)
	var frame_size := img.get_size()
	item.set_text(1, "%d×%d" % [frame_size.x, frame_size.y])
	# Only names are picked and edited
	item.set_selectable(1, false)
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_metadata(0, coord)
	item.set_tooltip_text(0, PreviewArea.describe_cell(sheet, coord))
	if sheet.layout == Spritesheet.Layout.PACKED and sheet.placements.has(coord):
		var pinned: bool = sheet.placements[coord].get("pinned", false)
		item.add_button(1, PIN_ICON, PIN_BUTTON, false, tr("Unpin") if pinned else tr("Pin"))
		item.set_metadata(1, pinned)
	_highlight(item, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_update_highlights()
		refresh()


## Actions offered when right-clicking frames, with [param submenus] as in
## [method ActionPopupMenu.set_actions]
func set_context_actions(ids: Array[StringName], submenus := {}) -> void:
	context_menu.set_actions(ids, submenus)


## The frame's name, or its number when it has none
static func frame_label(sheet: Spritesheet, coord: Vector2i) -> String:
	var frame_name := sheet.frames[coord].resource_name
	if frame_name:
		return frame_name.get_basename()
	var index: int = sheet.index_of(coord) + Settings.get_value(&"index_start")
	return TranslationServer.translate("Frame %d") % index


## The frames selected in the list
func get_selected_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var item := tree.get_next_selected(null)
	while item:
		if item.get_metadata(0) is Vector2i:
			coords.append(item.get_metadata(0))
		item = tree.get_next_selected(item)
	return coords


## The selected frames as dragged, see [method AnimationTimeline.frames_drag_data]
func _get_drag_data_of_tree(_at: Vector2) -> Variant:
	var coords := get_selected_coords()
	if coords.is_empty():
		return null
	tree.set_drag_preview(AnimationTimeline.drag_preview(Global.spritesheet, coords))
	return AnimationTimeline.frames_drag_data(coords)


## The frame shrunk to fit a square, in the middle of it, so names line up
func _thumbnail(img: Image) -> Texture2D:
	if not _thumbnails.has(img):
		var small: Image = img.duplicate()
		small.convert(Image.FORMAT_RGBA8)
		var longest := maxi(img.get_width(), img.get_height())
		if longest > THUMBNAIL_SIZE:
			var shrunk := (Vector2(img.get_size()) * THUMBNAIL_SIZE / longest).round()
			small.resize(maxi(1, int(shrunk.x)), maxi(1, int(shrunk.y)), Image.INTERPOLATE_BILINEAR)
		var square := Image.create_empty(THUMBNAIL_SIZE, THUMBNAIL_SIZE, false, Image.FORMAT_RGBA8)
		var at := (Vector2i.ONE * THUMBNAIL_SIZE - small.get_size()) / 2
		square.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), at)
		_thumbnails[img] = ImageTexture.create_from_image(square)
	return _thumbnails[img]


## Selects in the list what's selected in the preview, with the keyboard cursor on the
## first selected frame, or on none
func _show_selection() -> void:
	if _syncing or not preview or not visible:
		return
	_syncing = true
	var selected := {}
	for coord in preview.get_selected_coords():
		selected[coord] = true
	tree.deselect_all()
	var item := tree.get_root().get_next_in_tree() if tree.get_root() else null
	var first_selected: TreeItem = null
	while item:
		var coord: Variant = item.get_metadata(0)
		if coord is Vector2i and selected.has(coord):
			item.select(0, not first_selected)
			if not first_selected:
				first_selected = item
		_highlight(item, item.is_selected(0))
		item = item.get_next_in_tree()
	if first_selected:
		# To its group's name when the group is folded
		var parent := first_selected.get_parent()
		tree.scroll_to_item(parent if parent.collapsed else first_selected)
	_syncing = false


## Makes the highlights from the theme's, and stops the list drawing its own
func _update_highlights() -> void:
	_highlights.clear()
	for focused: bool in [false, true]:
		var style := &"selected_focus" if focused else &"selected"
		var selected := get_theme_stylebox(style, &"Tree") as StyleBoxFlat
		if not selected:
			_highlights.clear()
			return
		var name_box := selected.duplicate() as StyleBoxFlat
		name_box.corner_radius_top_right = 0
		name_box.corner_radius_bottom_right = 0
		var size_box := selected.duplicate() as StyleBoxFlat
		size_box.corner_radius_top_left = 0
		size_box.corner_radius_bottom_left = 0
		var pin_box := size_box.duplicate() as StyleBoxFlat
		pin_box.expand_margin_right = (
			PIN_ICON.get_width()
			+ tree.get_theme_stylebox("button_pressed").get_minimum_size().x
			+ tree.get_theme_constant("button_margin")
		)
		_highlights[focused] = [name_box, size_box, pin_box]
	for style: StringName in [&"selected", &"selected_focus"]:
		tree.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	# The pointer shades a selected cell as it does the others
	var hovered := get_theme_stylebox("hovered", &"Tree")
	for style: StringName in [&"hovered_selected", &"hovered_selected_focus"]:
		tree.add_theme_stylebox_override(style, hovered)


## Highlights [param item]'s row if its frame is [param selected]. The size and pin,
## which aren't picked with the name, take the colours of the selection's text.
func _highlight(item: TreeItem, selected: bool) -> void:
	if not item.get_metadata(0) is Vector2i:
		return
	var pinnable := item.get_button_count(1) > 0
	if not _highlights.is_empty():
		var boxes: Array = _highlights[tree.has_focus()]
		item.set_custom_stylebox(0, boxes[0] if selected else null)
		item.set_custom_stylebox(1, (boxes[2] if pinnable else boxes[1]) if selected else null)
	item.set_custom_color(
		1,
		(
			tree.get_theme_color("font_selected_color")
			if selected
			else get_theme_color("font_color", &"StatusLabel")
		)
	)
	if pinnable:
		# Pinned frames show the pin like a pressed toggle, in its own grey over the
		# selection; the others a faint one to click
		var color := &"icon_disabled_color"
		if item.get_metadata(1):
			color = &"icon_normal_color" if selected else &"icon_pressed_color"
		item.set_button_color(1, 0, get_theme_color(color, &"Button"))


## Highlights the selected frames again, as they are with focus on the list or without
func _highlight_all() -> void:
	var item := tree.get_root().get_next_in_tree() if tree.get_root() else null
	while item:
		_highlight(item, item.is_selected(0))
		item = item.get_next_in_tree()


## Sent for each name picked or unpicked, sometimes before the item has changed
func _on_tree_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	_highlight(item, selected)
	_on_tree_selected()


func _on_tree_selected() -> void:
	if _syncing or not preview:
		return
	_syncing = true
	preview.set_selected_coords(get_selected_coords())
	_syncing = false


## Starts renaming the selected frame
func _edit_selected() -> void:
	var item := tree.get_selected()
	if item and item.get_metadata(0) is Vector2i:
		item.set_editable(0, true)
		item.set_text(0, Global.spritesheet.frames[item.get_metadata(0)].resource_name)
		tree.set_selected(item, 0)
		tree.edit_selected(true)


func _on_item_edited() -> void:
	_rename(tree.get_edited())


## Renames the frame of [param item] to what's typed in it
func _rename(item: TreeItem) -> void:
	if not item or not item.get_metadata(0) is Vector2i:
		return
	item.set_editable(0, false)
	var coord: Vector2i = item.get_metadata(0)
	var sheet := Global.spritesheet
	var new_name := item.get_text(0).strip_edges()
	if new_name != sheet.frames[coord].resource_name:
		Global.document.perform("Rename frame", sheet.rename_frame.bind(coord, new_name))
	else:
		refresh()


func _on_button_clicked(item: TreeItem, _column: int, id: int, _button: int) -> void:
	var coord: Variant = item.get_metadata(0)
	if id != PIN_BUTTON or not coord is Vector2i:
		return
	var sheet := Global.spritesheet
	var pin: bool = not sheet.placements[coord].get("pinned", false)
	Global.document.perform(
		"Pin frame" if pin else "Unpin frame",
		sheet.set_pinned.bind([coord] as Array[Vector2i], pin)
	)


## The name of the group at [param at] in the list, off its arrow, or null
func _header_at(at: Vector2) -> TreeItem:
	var item := tree.get_item_at_position(at)
	if not item or item.get_metadata(0) is Vector2i:
		return null
	var arrow_end := (
		tree.get_theme_stylebox("panel").get_margin(SIDE_LEFT)
		+ tree.get_theme_constant("item_margin")
	)
	return item if at.x >= arrow_end else null


## Selects the frames listed under [param header], clicked with [param mouse]. Shift or Ctrl
## adds them to the selection; right-clicking keeps the selection when it has them all, like
## right-clicking a frame.
func _select_group(header: TreeItem, mouse: InputEventMouseButton) -> void:
	if not preview:
		return
	var coords: Array[Vector2i] = []
	for item in header.get_children():
		coords.append(item.get_metadata(0))
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if coords.all(preview.is_selected):
			return
	elif mouse.shift_pressed or mouse.is_command_or_control_pressed():
		coords.append_array(preview.get_selected_coords())
	preview.set_selected_coords(coords)


func _on_setting_changed(key: StringName) -> void:
	if key == &"sprites_by_row":
		by_row_button.set_pressed_no_signal(Settings.get_value(key))
		refresh()


## Remembers which groups are folded, to fold them again when the list is refreshed
func _on_item_collapsed(item: TreeItem) -> void:
	var key: Variant = item.get_metadata(0)
	if key is String:
		_collapsed[key] = item.collapsed


func _on_tree_input(event: InputEvent) -> void:
	# F2 alone: with Shift or Ctrl, it makes an animation
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_F2 and key.get_modifiers_mask() == 0:
		_edit_selected()
		tree.accept_event()
	var mouse := event as InputEventMouseButton
	var header := _header_at(mouse.position) if mouse and mouse.pressed else null
	if header and mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		# Instead of folding the group, and double-clicking it doesn't rename a frame
		_select_group(header, mouse)
		tree.accept_event()
	# Sizes can't be picked, and double-clicking one doesn't rename another frame
	elif mouse and mouse.double_click and tree.get_column_at_position(mouse.position) == 1:
		tree.accept_event()
	elif (
		mouse
		and mouse.button_index == MOUSE_BUTTON_RIGHT
		and not mouse.pressed
		and context_menu.item_count > 0
		and tree.get_item_at_position(mouse.position)
	):
		var screen_position := tree.get_screen_transform() * mouse.position
		context_menu.popup(Rect2i(Vector2i(screen_position), Vector2i.ZERO))
