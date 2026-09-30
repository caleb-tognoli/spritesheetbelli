class_name ColorKeyPreview
extends Node
## Remove Background Colour in the main view: a [ColorKeyDropdown] in the canvas toolbar,
## for the selected frames, or every frame when none are selected. Its eyedropper picks
## the colour by clicking a frame, as the frame is, not as previewed.
##
## While it's open, the preview shows those frames with the colour removed, see
## [method SpritesheetPreview.show_instead], without changing the sheet. Clicks on the
## canvas select frames as usual, and the preview follows the selection. Only Confirm
## changes the sheet, as one step to undo. Cancel, Escape or clicking elsewhere shows the
## frames as they are.

var dropdown := ColorKeyDropdown.new()
var preview: SpritesheetPreview
## Keying passes started for the preview, one at a time, see [method _update_preview]
var passes := 0

## Edits frames on worker threads as one step, see [method setup]
var _edit_in_background := Callable()
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


## Previews on [param area]'s preview and picks colours from it. Frames are edited with
## [param edit_in_background], the main view's [code]edit_selection_in_background[/code]. The
## dropdown goes in the toolbar, see [method PreviewArea.set_toolbar_actions].
func setup(area: PreviewArea, edit_in_background: Callable) -> void:
	preview = area.spritesheet_preview
	_edit_in_background = edit_in_background
	dropdown.add_picker(preview, area.container)
	dropdown.let_clicks_through(area.stage)
	dropdown.opening.connect(_on_opening)
	dropdown.changed.connect(_queue_update)
	dropdown.confirmed.connect(_on_confirmed)
	dropdown.canceled.connect(_on_canceled)
	# The selection or the frames changed
	preview.preview_updated.connect(_queue_update)
	# Another document has other frames
	Global.document.loaded.connect(
		func(_view: Dictionary) -> void:
			if dropdown.is_open():
				dropdown.cancel()
	)


## Opens the dropdown, as the toolbar button does
func open() -> void:
	if not dropdown.is_open():
		dropdown.open()


## The selected frames, or every frame when none are
func get_target_coords() -> Array[Vector2i]:
	var coords := preview.get_selected_coords()
	return coords if not coords.is_empty() else preview.spritesheet.get_sorted_coords()


## Suggests the top-left pixel of the first frame it works on, usually the background, and
## the tolerance used last
func _on_opening() -> void:
	var coords := get_target_coords()
	var color := dropdown.get_color()
	if not coords.is_empty() and not preview.spritesheet.frames[coords[0]].is_empty():
		color = preview.spritesheet.frames[coords[0]].get_pixel(0, 0)
	dropdown.set_key(true, color, Settings.get_value(&"background_tolerance"))
	_update_note()
	# Once it's open
	_queue_update.call_deferred()


## Makes pixels close to [param color] transparent in the selected frames, or in every
## frame when none are selected, as one step to undo. It can take a while.
func remove(color: Color, tolerance: float) -> void:
	var coords := get_target_coords()
	if coords.is_empty():
		return
	await _edit_in_background.call(
		L10n.mark("Remove background"),
		tr("Removing background"),
		func(img: Image) -> Image:
			ImageUtils.color_key(img, color, tolerance)
			return img,
		Callable(),
		FrameEdits.color_key_op(color, tolerance),
		coords
	)


## Removes the colour from the frames. They're previewed with it removed until then.
func _on_confirmed() -> void:
	_keyed.clear()
	await remove(dropdown.get_color(), dropdown.get_tolerance())
	if not dropdown.is_open():
		preview.show_instead({})


func _on_canceled() -> void:
	_keyed.clear()
	preview.show_instead({})


func _update_note() -> void:
	var count := get_target_coords().size()
	dropdown.note.text = (
		tr_n("In %d selected frame", "In %d selected frames", count) % count
		if not preview.get_selected_coords().is_empty()
		else tr_n("In %d frame", "In all %d frames", count) % count
	)
	dropdown.note.visible = true
	dropdown.confirm_button.disabled = count == 0


## Updates the preview at the end of the frame, once for all changes made until then, like
## dragging in the colour picker
func _queue_update() -> void:
	if dropdown.is_open() and not _update_queued:
		_update_queued = true
		_update_preview.call_deferred()


## Shows the frames it works on with the colour removed. Only frames not shown that way
## yet are worked on, on worker threads, one pass at a time: changes made during a pass
## are worked on after it, with the latest colour only.
func _update_preview() -> void:
	_update_queued = false
	if not dropdown.is_open():
		return
	if _keying:
		_stale = true
		return
	_update_note()
	var sheet := preview.spritesheet
	var coords := get_target_coords()
	var color := dropdown.get_color()
	var tolerance := dropdown.get_tolerance()
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
	passes += 1
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
	if not dropdown.is_open():
		return
	if _stale:
		_stale = false
		_queue_update()
	for i in sources.size():
		_keyed[sources[i]] = results[i]
	# Only the frames it works on, as they are now
	var shown: Dictionary[Image, Image] = {}
	for coord in coords:
		if sheet.frames.get(coord) in _keyed:
			shown[sheet.frames[coord]] = _keyed[sheet.frames[coord]]
	preview.show_instead(shown)
