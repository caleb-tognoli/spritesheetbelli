class_name SpriteBoxEditor
extends VBoxContainer
## The boxes around the sprites found in a sheet, over the image, to edit by hand before
## they're added (see [SpriteBoxView]). A toolbar undoes, merges, deletes and resets the
## boxes to the sprites as found, and the zoom floats over the top-right corner, like the
## spritesheet preview's. Edits are undone here, apart from the open document's history.

## The boxes were edited by hand, or an edit was undone or redone
signal boxes_edited
signal selection_changed
## Reset was pressed
signal find_requested

const MERGE_ICON := preload("res://assets/icons/Group.svg")
const DELETE_ICON := preload("res://assets/icons/Remove.svg")
const FIND_ICON := preload("res://assets/icons/Reload.svg")
const UNDO_ICON := preload("res://assets/icons/Undo.svg")
const REDO_ICON := preload("res://assets/icons/Redo.svg")

var view := SpriteBoxView.new()
var undo_btn := _tool_button(UNDO_ICON)
var redo_btn := _tool_button(REDO_ICON)
var merge_btn := _tool_button(MERGE_ICON)
var delete_btn := _tool_button(DELETE_ICON)
var find_btn := _tool_button(FIND_ICON)
## The box being dragged or the selected boxes
var info_label := Label.new()
var zoom_label_btn := _tool_button(null)
## Says the sprites were found again over hand edits, which undo brings back
var notice := PanelContainer.new()
var notice_label := Label.new()

## Boxes and selections to go back to, oldest first, see [method _record]
var _history: Array[Dictionary] = []
var _step := 0
## The boxes as found, to tell hand edits from them
var _found: Array[Rect2i] = []


func _init() -> void:
	add_theme_constant_override("separation", 0)
	_build_toolbar()
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	add_child(stage)
	stage.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_overlay(stage)
	view.edited.connect(_on_edited)
	view.selection_changed.connect(
		func() -> void:
			_update_ui()
			selection_changed.emit()
	)
	view.dragged.connect(_update_info)
	view.undo_requested.connect(undo)
	view.redo_requested.connect(redo)
	view.zoom_changed.connect(
		func(zoom: float) -> void: zoom_label_btn.text = "%d%%" % roundi(zoom * 100)
	)
	_update_ui()


func _build_toolbar() -> void:
	var toolbar := PanelContainer.new()
	toolbar.theme_type_variation = &"Toolbar"
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 2)
	bar.add_theme_constant_override("v_separation", 2)
	toolbar.add_child(bar)
	add_child(toolbar)

	Actions.set_tooltip(undo_btn, &"undo", L10n.mark("Undo"))
	undo_btn.pressed.connect(undo)
	Actions.set_tooltip(redo_btn, &"redo", L10n.mark("Redo"))
	redo_btn.pressed.connect(redo)
	merge_btn.text = "Merge"
	merge_btn.tooltip_text = "Joins the selected boxes into one. Ctrl+drag across boxes also does."
	merge_btn.pressed.connect(view.merge_selected)
	delete_btn.text = "Delete"
	Actions.set_tooltip(delete_btn, &"delete_frames", L10n.mark("Delete the selected boxes"))
	delete_btn.pressed.connect(view.remove_selected)
	find_btn.text = "Reset"
	find_btn.tooltip_text = "Finds the sprites again, without the changes made by hand"
	find_btn.pressed.connect(find_requested.emit)
	for control: Control in [undo_btn, redo_btn, VSeparator.new(), merge_btn, delete_btn]:
		bar.add_child(control)
	bar.add_child(VSeparator.new())
	bar.add_child(find_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.add_child(info_label)


## The zoom over the top-right corner and the notice over the bottom-right one, like the
## spritesheet preview's, see [PreviewArea]
func _build_overlay(stage: Control) -> void:
	var zoom := PanelContainer.new()
	zoom.theme_type_variation = &"PreviewOverlay"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	zoom.add_child(row)
	var fit_btn := _tool_button(PreviewArea.CENTER_VIEW_ICON)
	var zoom_out_btn := _tool_button(PreviewArea.ZOOM_OUT_ICON)
	var zoom_in_btn := _tool_button(PreviewArea.ZOOM_IN_ICON)
	zoom_label_btn.custom_minimum_size.x = 56
	for entry: Array in [
		[fit_btn, &"zoom_fit"],
		[zoom_out_btn, &"zoom_out"],
		[zoom_label_btn, &"zoom_reset"],
		[zoom_in_btn, &"zoom_in"],
	]:
		var button: Button = entry[0]
		Actions.set_tooltip(button, entry[1])
		row.add_child(button)
	fit_btn.pressed.connect(fit_to_view)
	zoom_out_btn.pressed.connect(func() -> void: view.zoom_by(0.8))
	zoom_in_btn.pressed.connect(func() -> void: view.zoom_by(1.25))
	zoom_label_btn.pressed.connect(func() -> void: view.reset_zoom())
	zoom_label_btn.text = "100%"
	stage.add_child(zoom)
	zoom.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	zoom.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	notice.theme_type_variation = &"PreviewOverlay"
	notice.visible = false
	var notice_row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = PreviewArea.WARNING_ICON
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	notice_row.add_child(icon)
	notice_row.add_child(notice_label)
	notice.add_child(notice_row)
	stage.add_child(notice)
	notice.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10
	)
	notice.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	notice.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Shows [param img] under the boxes
func set_image(img: Image) -> void:
	view.set_image(img)


func fit_to_view() -> void:
	view.fit_to_view()


## Starts over with [param boxes] as found, forgetting the edits
func start(boxes: Array[Rect2i]) -> void:
	_found = boxes.duplicate()
	view.set_boxes(boxes)
	_history.clear()
	_step = 0
	_record()
	notice.visible = false


## Takes [param boxes], found again, e.g. with other settings. Edits made by hand are
## replaced as a step that can be undone, which a notice says; returns whether there were.
func find_again(boxes: Array[Rect2i]) -> bool:
	var edited := is_edited()
	_found = boxes.duplicate()
	view.set_boxes(boxes)
	if edited:
		_record()
		notice_label.text = tr("Sprites found again. Undo brings back the boxes edited by hand.")
		notice.visible = true
	else:
		# Finding again while dragging in the colour picker keeps a single step
		_history[_step] = _snapshot()
		_history.resize(_step + 1)
		_update_ui()
	return edited


## Whether the boxes were changed by hand since they were found
func is_edited() -> bool:
	return view.boxes != _found


func get_boxes() -> Array[Rect2i]:
	return view.boxes


func get_selected() -> Array[int]:
	return view.selected


func can_undo() -> bool:
	return _step > 0


func can_redo() -> bool:
	return _step < _history.size() - 1


func undo() -> void:
	if can_undo():
		_go_to(_step - 1)


func redo() -> void:
	if can_redo():
		_go_to(_step + 1)


func _go_to(step: int) -> void:
	_step = step
	var entry := _history[step]
	view.set_boxes(entry.boxes, entry.selected)
	notice.visible = false
	_update_ui()
	boxes_edited.emit()


func _on_edited() -> void:
	_record()
	notice.visible = false
	boxes_edited.emit()


## Adds the boxes as they are now to the history, after the step shown, dropping the
## steps that were undone
func _record() -> void:
	_history.resize(_step + 1 if not _history.is_empty() else 0)
	_history.append(_snapshot())
	_step = _history.size() - 1
	_update_ui()


func _snapshot() -> Dictionary:
	return {"boxes": view.boxes.duplicate(), "selected": view.selected.duplicate()}


func _update_ui() -> void:
	undo_btn.disabled = not can_undo()
	redo_btn.disabled = not can_redo()
	merge_btn.disabled = view.selected.size() < 2
	delete_btn.disabled = view.selected.is_empty()
	find_btn.disabled = not is_edited()
	_update_info()


## Where the box being dragged or the selected box is, or how many are selected
func _update_info() -> void:
	var dragged := view.get_dragged_box()
	var selected := view.selected
	if dragged.has_area():
		info_label.text = (
			tr("%d, %d · %d×%d px")
			% [dragged.position.x, dragged.position.y, dragged.size.x, dragged.size.y]
		)
	elif selected.size() == 1:
		var box := view.boxes[selected[0]]
		info_label.text = (
			tr("Frame %d · %d, %d · %d×%d px")
			% [view.get_number(selected[0]), box.position.x, box.position.y, box.size.x, box.size.y]
		)
	elif selected.size() > 1:
		info_label.text = tr_n("%d selected", "%d selected", selected.size()) % selected.size()
	else:
		info_label.text = ""


static func _tool_button(icon: Texture2D) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"ToolbarButton"
	button.icon = icon
	button.focus_mode = Control.FOCUS_NONE
	return button
