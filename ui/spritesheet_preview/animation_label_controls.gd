class_name AnimationLabelControls
extends Node
## What the names of animations on the grid do (see [AnimationLabels]), and the toolbar
## button choosing which are shown: it opens a flyover listing every animation that can be
## labelled, each with an eye to show or hide its name, with Show all, Hide all and Only
## the playing animation. The choices are part of the sheet, so they're saved with the
## project and undone like other changes.
## Clicking a name chooses its animation, double-clicking renames it, right-clicking
## offers what can be done to it and hovering tells its length, speed and type.
## The button, the flyover and the names are only there in the grid layout.

## A name was clicked: its animation's frames are to be selected and played
signal animation_chosen(index: int)
## Asked from a name's right-click menu, done by the animation panel
signal edit_requested(index: int)
signal mirror_requested(index: int)
signal delete_requested(index: int)

enum Item { RENAME, EDIT, MIRROR, HIDE, DELETE }

const ICON := preload("res://assets/icons/AnimationLabels.svg")
const SHOWN_ICON := preload("res://assets/icons/GuiVisibilityVisible.svg")
const HIDDEN_ICON := preload("res://assets/icons/GuiVisibilityHidden.svg")
const POPUP_THEME := preload("res://resources/themes/popup_menu_theme.tres")
## Speeds offered in a name's right-click menu, in frames per second
const SPEEDS: Array[float] = [4, 6, 8, 10, 12, 15, 20, 24, 30, 60]

var area: PreviewArea
var labels: AnimationLabels
## The toolbar button, next to the view toggles
var button: Button
var flyover := PopupPanel.new()
var show_all_button := Button.new()
var hide_all_button := Button.new()
var playing_only_check := CheckBox.new()
## A button for each animation that can be labelled, with an eye showing whether it is
var list := VBoxContainer.new()
## Says how many animations can't be labelled
var left_out := Label.new()
var menu := PopupMenu.new()
var speed_menu := PopupMenu.new()
var type_menu := PopupMenu.new()
## Renames an animation over its name
var rename_edit := LineEdit.new()
## The animation right-clicked, and the one being renamed, or -1
var _menu_index := -1
var _renaming := -1


## Makes [param preview_area]'s grid show names, and [param toolbar_button] open the flyover
func setup(preview_area: PreviewArea, toolbar_button: Button) -> void:
	area = preview_area
	button = toolbar_button
	var preview := area.spritesheet_preview
	labels = preview.animation_labels
	labels.enabled = true
	labels.update(preview.spritesheet, preview.grid_view)
	button.pressed.connect(open_flyover)
	_build_flyover()
	_build_menu()
	rename_edit.visible = false
	rename_edit.text_submitted.connect(func(_text: String) -> void: _finish_rename(true))
	rename_edit.focus_exited.connect(_finish_rename.bind(true))
	rename_edit.gui_input.connect(
		func(event: InputEvent) -> void:
			if event.is_action_pressed(&"ui_cancel"):
				rename_edit.accept_event()
				_finish_rename(false)
	)
	area.stage.add_child(rename_edit)

	labels.clicked.connect(func(index: int) -> void: animation_chosen.emit(index))
	labels.double_clicked.connect(start_rename)
	labels.menu_requested.connect(open_menu)
	labels.hovered_changed.connect(_on_hovered)
	area.container.mouse_exited.connect(
		func() -> void:
			labels.set_hovered(-1)
			preview.queue_redraw()
	)
	preview.preview_updated.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	# The animation panel says nothing when another animation plays, so it's checked here
	if labels and labels.is_outdated():
		var preview := area.spritesheet_preview
		labels.update(preview.spritesheet, preview.grid_view)
		preview.queue_redraw()
		refresh()


## Shows the button in the grid layout only, and the flyover's choices as they are
func refresh() -> void:
	var sheet := area.spritesheet_preview.spritesheet
	button.visible = sheet.layout == Spritesheet.Layout.GRID
	button.disabled = sheet.animations.is_empty()
	if not button.visible:
		flyover.hide()
	if flyover.visible:
		_fill_flyover()


#region Flyover


func _build_flyover() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	flyover.add_child(box)
	var buttons := HBoxContainer.new()
	for entry: Array in [[show_all_button, "Show all", true], [hide_all_button, "Hide all", false]]:
		var all_button: Button = entry[0]
		all_button.text = entry[1]
		all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		all_button.focus_mode = Control.FOCUS_NONE
		all_button.pressed.connect(show_all.bind(entry[2]))
		buttons.add_child(all_button)
	box.add_child(buttons)
	playing_only_check.text = "Only the playing animation"
	playing_only_check.tooltip_text = "Name only the animation chosen in the animation panel"
	playing_only_check.focus_mode = Control.FOCUS_NONE
	playing_only_check.toggled.connect(set_playing_only)
	box.add_child(playing_only_check)
	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	box.add_child(scroll)
	left_out.theme_type_variation = &"StatusLabel"
	left_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_out.custom_minimum_size.x = 220
	box.add_child(left_out)
	area.add_child(flyover)


## Opens the flyover below the toolbar button
func open_flyover() -> void:
	if not button.is_visible_in_tree():
		return
	_fill_flyover()
	# The screen transform accounts for the window position and the interface's scale
	var below := button.get_screen_transform() * Rect2(0, button.size.y + 4, button.size.x, 0)
	flyover.popup(Rect2i(below))
	# The button is near the window's right edge, so it opens leftwards when it must
	var window := button.get_window()
	var past := flyover.position.x + flyover.size.x - (window.position.x + window.size.x)
	if past > 0:
		flyover.position.x -= past


func _fill_flyover() -> void:
	var sheet := Global.spritesheet
	var animations := sheet.animations
	var labelled := AnimationLabels.get_labelled(sheet)
	# Later, as the pressed one is still running
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for index in labelled:
		var animation := animations[index]
		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.text = animation.name
		row.icon = SHOWN_ICON if animation.show_label else HIDDEN_ICON
		row.tooltip_text = "Hide its name" if animation.show_label else "Show its name"
		row.disabled = sheet.label_playing_only
		row.pressed.connect(set_label_shown.bind(index, not animation.show_label))
		list.add_child(row)
	playing_only_check.set_pressed_no_signal(sheet.label_playing_only)
	var missing := animations.size() - labelled.size()
	left_out.visible = missing > 0
	left_out.text = (
		tr("%d more can't be named: their frames aren't in a row, a column or one area.") % missing
	)
	# At most as tall as a dozen names, scrolling past them
	var scroll := list.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = minf(list.get_combined_minimum_size().y, 12 * 28)
	flyover.reset_size()


## Shows or hides the name of the animation at [param index], as one undoable step
func set_label_shown(index: int, shown: bool) -> void:
	var sheet := Global.spritesheet
	if index < 0 or index >= sheet.animations.size():
		return
	var animation := sheet.animations[index]
	animation.show_label = shown
	Global.document.perform(
		"Show label" if shown else "Hide label", sheet.set_animation.bind(index, animation)
	)


## Shows or hides every animation's name, and stops naming only the playing one
func show_all(shown: bool) -> void:
	var sheet := Global.spritesheet
	Global.document.perform(
		"Show all labels" if shown else "Hide all labels",
		func() -> void:
			sheet.set_label_playing_only(false)
			var animations := sheet.animations
			for i in animations.size():
				animations[i].show_label = shown
				sheet.set_animation(i, animations[i])
	)


func set_playing_only(on: bool) -> void:
	var sheet := Global.spritesheet
	Global.document.perform(
		"Label only the playing animation" if on else "Label the chosen animations",
		sheet.set_label_playing_only.bind(on)
	)


#endregion

#region Names


func _on_hovered(index: int) -> void:
	var preview := area.spritesheet_preview
	if index >= 0:
		area.container.tooltip_text = AnimationLabels.describe(preview.spritesheet, index)
	else:
		area.update_tooltip(preview.hovered_cell)


## Edits the animation's name over its label
func start_rename(index: int) -> void:
	var rect := labels.get_tag_rect(index)
	if not rect.has_area() or index >= Global.spritesheet.animations.size():
		return
	_renaming = index
	rename_edit.text = Global.spritesheet.animations[index].name
	rename_edit.reset_size()
	rename_edit.size.x = maxf(rect.size.x + 48, 120)
	rename_edit.position = rect.get_center() - Vector2(rect.size.x / 2, rename_edit.size.y / 2)
	rename_edit.visible = true
	rename_edit.grab_focus()
	rename_edit.select_all()


func _finish_rename(apply: bool) -> void:
	if _renaming < 0:
		return
	var index := _renaming
	_renaming = -1
	rename_edit.visible = false
	var sheet := Global.spritesheet
	var new_name := rename_edit.text.strip_edges()
	if not apply or new_name.is_empty() or index >= sheet.animations.size():
		return
	var animation := sheet.animations[index]
	animation.name = new_name
	Global.document.perform("Rename animation", sheet.set_animation.bind(index, animation))


func _build_menu() -> void:
	for popup: PopupMenu in [menu, speed_menu, type_menu]:
		popup.theme = POPUP_THEME
	menu.add_item("Rename", Item.RENAME)
	menu.add_item("Edit", Item.EDIT)
	menu.add_child(speed_menu)
	menu.add_submenu_node_item("Speed", speed_menu)
	menu.add_child(type_menu)
	menu.add_submenu_node_item("Type", type_menu)
	menu.add_item("Mirror", Item.MIRROR)
	menu.add_item("Hide Label", Item.HIDE)
	menu.add_separator()
	menu.add_item("Delete", Item.DELETE)
	menu.id_pressed.connect(_on_menu_item)
	for speed in SPEEDS:
		speed_menu.add_radio_check_item(tr("%s fps") % String.num(speed))
	speed_menu.index_pressed.connect(
		func(item: int) -> void:
			_edit_animation(func(animation: SheetAnimation) -> void: animation.fps = SPEEDS[item])
	)
	for mode: int in [
		SheetAnimation.Mode.LOOP, SheetAnimation.Mode.PING_PONG, SheetAnimation.Mode.ONCE
	]:
		type_menu.add_radio_check_item(SheetAnimation.MODE_NAMES[mode], mode)
	type_menu.id_pressed.connect(
		func(mode: int) -> void:
			_edit_animation(
				func(animation: SheetAnimation) -> void:
					animation.mode = mode as SheetAnimation.Mode
			)
	)
	area.add_child(menu)


## Opens the right-click menu of the animation at [param index], at [param position] in
## the view
func open_menu(index: int, position: Vector2) -> void:
	var animations := Global.spritesheet.animations
	if index >= animations.size():
		return
	_menu_index = index
	var animation := animations[index]
	for i in SPEEDS.size():
		speed_menu.set_item_checked(i, is_equal_approx(SPEEDS[i], animation.fps))
	for i in type_menu.item_count:
		type_menu.set_item_checked(i, type_menu.get_item_id(i) == animation.mode)
	# Only the names chosen can be hidden
	menu.set_item_disabled(menu.get_item_index(Item.HIDE), Global.spritesheet.label_playing_only)
	var screen_position := area.container.get_screen_transform() * position
	menu.popup(Rect2i(Vector2i(screen_position), Vector2i.ZERO))


func _on_menu_item(id: int) -> void:
	var index := _menu_index
	match id:
		Item.RENAME:
			start_rename(index)
		Item.EDIT:
			edit_requested.emit(index)
		Item.MIRROR:
			mirror_requested.emit(index)
		Item.HIDE:
			set_label_shown(index, false)
		Item.DELETE:
			delete_requested.emit(index)


## Changes the right-clicked animation with [param change] as one undoable step
func _edit_animation(change: Callable) -> void:
	var sheet := Global.spritesheet
	if _menu_index < 0 or _menu_index >= sheet.animations.size():
		return
	var animation := sheet.animations[_menu_index]
	change.call(animation)
	Global.document.perform("Edit animation", sheet.set_animation.bind(_menu_index, animation))

#endregion
