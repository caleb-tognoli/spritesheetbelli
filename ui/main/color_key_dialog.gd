class_name ColorKeyDialog
extends PanelContainer
## Remove Background Colour: a small panel over the preview, under the zoom, with the
## colour to make transparent in the selected frames (every frame when none are selected)
## and how close a pixel must be to it,
## see [ColorKeyControl]. It isn't modal: frames can be selected and the view moved while
## it's open, and its eyedropper picks the colour by clicking a frame, as the frame is,
## not as previewed.
##
## While it's open, the preview shows those frames with the colour removed, see
## [method SpritesheetPreview.show_instead], without changing the sheet. Only Remove
## does, as one step to undo. Cancel or Escape closes it and shows the frames as they are.

var key := ColorKeyControl.new()
## Says which frames the colour is removed from
var targets_label := Label.new()
var remove_button := Button.new()
var cancel_button := Button.new()
var preview: SpritesheetPreview

## Removes the colour from the frames, called with the colour and the tolerance, see
## [method setup]
var _remove := Callable()
## Whether the preview is updated at the end of the frame, once for many changes
var _update_queued := false
## Whether frames are being made transparent on worker threads, and whether something
## changed in the meantime, so it's done again after
var _keying := false
var _stale := false
## Frame images with the colour removed, at the sheet's scale, by the frame image, for
## [member _keyed_with]
var _keyed: Dictionary[Image, Image] = {}
## The colour, tolerance, scale and filter [member _keyed] was made with
var _keyed_with := []


func _init() -> void:
	visible = false
	theme_type_variation = &"PreviewOverlay"
	size_flags_horizontal = Control.SIZE_SHRINK_END
	# More room than the zoom's panel, for a panel with a title and buttons
	var margins := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 6)
	add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margins.add_child(column)
	var title := Label.new()
	title.text = "Remove Background Colour"
	title.theme_type_variation = &"HeaderSmall"
	column.add_child(title)
	key.set_always_on()
	column.add_child(key)

	var row := HBoxContainer.new()
	column.add_child(row)
	targets_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	targets_label.theme_type_variation = &"StatusLabel"
	row.add_child(targets_label)
	remove_button.text = "Remove"
	cancel_button.text = "Cancel"
	for button: Button in [remove_button, cancel_button]:
		# Space pans the preview, rather than pressing the button clicked last
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
	DialogButtons.arrange(row, remove_button, cancel_button, [])
	remove_button.pressed.connect(remove)
	cancel_button.pressed.connect(close)
	key.changed.connect(_queue_update)


## Puts the panel in [param area]'s overlay, previewing on its preview and picking colours
## from it. [param remove_background] removes the colour from the selected frames, or every
## frame when none are selected, called with the colour and the tolerance; it can take a
## while.
func setup(area: PreviewArea, remove_background: Callable) -> void:
	preview = area.spritesheet_preview
	_remove = remove_background
	area.overlay.add_child(self)
	key.watch_preview(preview)
	# The selection or the frames changed
	preview.preview_updated.connect(_queue_update)
	# Another document has other frames
	Global.document.loaded.connect(func(_view: Dictionary) -> void: close())


## Opens the panel suggesting the top-left pixel of the first frame it works on, usually
## the background, and the tolerance used last
func open() -> void:
	var coords := get_target_coords()
	if not visible:
		var color := key.get_color()
		if not coords.is_empty() and not preview.spritesheet.frames[coords[0]].is_empty():
			color = preview.spritesheet.frames[coords[0]].get_pixel(0, 0)
		key.set_key(true, color, Settings.get_value(&"background_tolerance"))
	visible = true
	_queue_update()


## Closes the panel without removing anything, showing the frames as they are
func close() -> void:
	_close()
	preview.show_instead({})


## Removes the colour from the frames as one step to undo, and closes the panel. The
## frames are previewed with it removed until then.
func remove() -> void:
	if get_target_coords().is_empty():
		return
	_close()
	await _remove.call(key.get_color(), key.get_tolerance())
	if not visible:
		preview.show_instead({})


## The selected frames, or every frame when none are
func get_target_coords() -> Array[Vector2i]:
	var coords := preview.get_selected_coords()
	return coords if not coords.is_empty() else preview.spritesheet.get_sorted_coords()


func _close() -> void:
	visible = false
	key.set_picking(false)
	_keyed.clear()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		# Escape puts the eyedropper away first
		if key.is_picking():
			key.set_picking(false)
		else:
			close()
		get_viewport().set_input_as_handled()


## Updates the preview at the end of the frame, once for all changes made until then, like
## dragging in the colour picker
func _queue_update() -> void:
	if visible and not _update_queued:
		_update_queued = true
		_update_preview.call_deferred()


## Shows the frames it works on with the colour removed. Only frames not shown that way
## yet are worked on, on worker threads.
func _update_preview() -> void:
	_update_queued = false
	if not visible:
		return
	if _keying:
		_stale = true
		return
	var sheet := preview.spritesheet
	var coords := get_target_coords()
	remove_button.disabled = coords.is_empty()
	var selected := not preview.get_selected_coords().is_empty()
	targets_label.text = (
		tr("In %d selected frames") % coords.size()
		if selected
		else tr("In all %d frames") % coords.size()
	)
	var color := key.get_color()
	var tolerance := key.get_tolerance()
	var filter := sheet.scale_filter
	var made_with := [color, tolerance, sheet.frame_scale, filter]
	if made_with != _keyed_with:
		_keyed.clear()
		_keyed_with = made_with
	var sources: Array[Image] = []
	for coord in coords:
		var img := sheet.frames[coord]
		if not _keyed.has(img) and img not in sources:
			sources.append(img)
	var sizes: Array[Vector2i] = []
	for img in sources:
		sizes.append(sheet.scaled_frames.scaled_size(img.get_size()))
	_keying = true
	var results := await Parallel.map(
		sources.size(),
		func(i: int) -> Image:
			var img := sources[i].duplicate() as Image
			ImageUtils.color_key(img, color, tolerance)
			if img.get_size() != sizes[i]:
				img.resize(sizes[i].x, sizes[i].y, filter)
			return img
	)
	_keying = false
	if not visible:
		return
	for i in sources.size():
		_keyed[sources[i]] = results[i]
	if _stale:
		_stale = false
		_queue_update()
		return
	# Only the frames it works on, as they are now
	var shown: Dictionary[Image, Image] = {}
	for coord in coords:
		if sheet.frames.get(coord) in _keyed:
			shown[sheet.frames[coord]] = _keyed[sheet.frames[coord]]
	preview.show_instead(shown)
