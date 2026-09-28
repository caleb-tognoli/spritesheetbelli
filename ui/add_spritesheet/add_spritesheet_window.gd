class_name AddSpritesheetWindow
extends Window

signal canceled
## Emitted after frames were added to the open spritesheet
signal frames_added

@onready var preview_area: PreviewArea = %PreviewArea
@onready var add_selected_frames_btn: Button = %AddSelectedFrames
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var cancel_btn: Button = %Cancel
@onready var grid_columns: SpinBox = %GridColumns
@onready var grid_rows: SpinBox = %GridRows
@onready var cell_width: SpinBox = %CellWidth
@onready var cell_height: SpinBox = %CellHeight
@onready var offset_x: SpinBox = %OffsetX
@onready var offset_y: SpinBox = %OffsetY
@onready var spacing_x: SpinBox = %SpacingX
@onready var spacing_y: SpinBox = %SpacingY
@onready var slice_info: Label = %SliceInfo
## Locks the added sheet's empty cells, so added sprites skip them
@onready var lock_empty_cells: CheckBox = %LockEmptyCells

## The image that's cut: the one opened, with its background made transparent when
## [member background] is on
@export var spritesheet_image: Image

## How the image is cut into frames
enum Cut {
	GRID,  ## In a grid of equal cells
	DETECT,  ## Every group of pixels surrounded by transparency is a frame
	DATA,  ## Where the data file says
}

var spritesheet: Spritesheet
## Where the frames are, from a data file exported with the image, or null
var sheet_data: SheetData
## The files the frames are linked to (see [FrameSource]), or empty to not link them
var image_path := ""
var data_path := ""
var cut_option := OptionButton.new()
## Settings for finding sprites
var detect_box := HBoxContainer.new()
var merge_distance := SpinBox.new()
var align_option := OptionButton.new()
## Opens the rarely needed offset and spacing fields in a floating panel
var more_options_btn := OptionsDropdown.new("Offset & Spacing")
## Keeps the sprites where they are in the image, in the packed layout
var keep_layout := CheckBox.new()
## Makes a colour transparent before cutting, on for sheets drawn on a solid colour
var background := ColorKeyControl.new()
## The image with a box over each sprite, shown instead of the preview when finding
## sprites: the boxes, edited or not, are what's cut
var box_editor := SpriteBoxEditor.new()
## The image as opened
var source_image: Image
## The other pages of a packed sheet with a data file, by page, as cut
var _other_pages: Array[Image] = []
## The other pages as opened
var _source_pages: Array[Image] = []
## Whether the grid is still the guessed one, which is guessed again when the background
## changes, as that changes where the sprites are
var _grid_guessed := true
## Whether the image is cut again at the end of the frame, once for many changes to the
## background, see [method _on_background_changed]
var _background_queued := false
## Whether the cell size was set last, rather than the grid: the one set last is kept when
## the offset or spacing change, and the other follows
var _by_cell_size := false
## Whether the sprites were found in the image since it was opened, and whether they're to
## be found again, as the settings for finding them changed. They're found once shown.
var _boxes_found := false
var _boxes_stale := true


func _ready() -> void:
	close_requested.connect(hide)
	close_requested.connect(canceled.emit)
	add_selected_frames_btn.pressed.connect(add_selected_frames_to_global)
	add_selected_frames_btn.icon = preload("res://assets/icons/Add.svg")
	add_spritesheet_btn.icon = preload("res://assets/icons/SpriteSheet.svg")
	add_spritesheet_btn.pressed.connect(add_spritesheet_to_global)
	cancel_btn.pressed.connect(close_requested.emit)
	# Like a dialog's: Add Spritesheet where OK goes, Escape cancels
	DialogButtons.arrange(
		%Buttons as HBoxContainer, add_spritesheet_btn, cancel_btn, [add_selected_frames_btn]
	)
	window_input.connect(
		func(event: InputEvent) -> void:
			if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
				# Escape puts the eyedropper away first
				if background.is_picking():
					background.set_picking(false)
					set_input_as_handled()
				else:
					close_requested.emit()
	)
	lock_empty_cells.toggled.connect(
		func(on: bool) -> void: Settings.set_value(&"lock_empty_cells", on)
	)
	preview_area.spritesheet_preview.selection_changed.connect(on_preview_update)
	for field: SpinBox in [grid_columns, grid_rows]:
		field.max_value = Slicer.MAX_GRID
		field.value_changed.connect(
			func(_value: float) -> void:
				update_grid_size(int(grid_columns.value), int(grid_rows.value))
		)
	for field: SpinBox in [cell_width, cell_height]:
		field.value_changed.connect(
			func(_value: float) -> void:
				update_cell_size(int(cell_width.value), int(cell_height.value))
		)

	var fields: Array[SpinBox] = [grid_columns, grid_rows, cell_width, cell_height]
	fields.append_array([offset_x, offset_y, spacing_x, spacing_y])
	for field in fields:
		SpinScroll.enable(field)
	for field: SpinBox in [offset_x, offset_y, spacing_x, spacing_y]:
		field.value_changed.connect(
			func(_value: float) -> void:
				_grid_guessed = false
				_cut_grid()
				_update_options_label()
		)

	# Offset and spacing are rarely needed, so they're in a panel that drops down
	var offset_box := offset_x.get_parent().get_parent() as Control
	var spacing_box := spacing_x.get_parent().get_parent() as Control
	more_options_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more_options_btn.custom_minimum_size.x = 160
	more_options_btn.tooltip_text = "For sheets with a margin around or gaps between the frames"
	more_options_btn.summarize = _options_summary
	offset_box.add_sibling(more_options_btn)
	for entry: Array in [[offset_box, offset_x, offset_y], [spacing_box, spacing_x, spacing_y]]:
		var box: Control = entry[0]
		var x: SpinBox = entry[1]
		var y: SpinBox = entry[2]
		var label := box.get_child(0) as Label
		var pair := box.get_child(1) as Control
		box.remove_child(pair)
		more_options_btn.add_field(
			label.text,
			pair,
			label.tooltip_text,
			func() -> void:
				x.value = 0
				y.value = 0,
			func() -> bool: return x.value == 0 and y.value == 0
		)
		box.queue_free()
	_update_options_label()

	_build_cut_controls()
	background.changed.connect(_on_background_changed)
	background.watch_preview(preview_area.spritesheet_preview)
	# The eyedropper picks from the image under the boxes too
	background.picking_changed.connect(func(on: bool) -> void: box_editor.view.picking = on)
	box_editor.view.color_picked.connect(background.pick)
	# Before the number of frames, which ends the toolbar
	slice_info.add_sibling(background)
	slice_info.get_parent().move_child(slice_info, background.get_index())

	preview_area.spritesheet_preview.able_to_lock_spaces = false
	preview_area.spritesheet_preview.able_to_move_frames = false
	# In the preview's place
	box_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_editor.theme = preview_area.theme
	box_editor.visible = false
	preview_area.add_sibling(box_editor)
	box_editor.boxes_edited.connect(_slice)
	box_editor.selection_changed.connect(on_preview_update)
	box_editor.find_requested.connect(
		func() -> void:
			_boxes_stale = true
			_slice()
	)
	# Show the whole sheet once the window has its size
	visibility_changed.connect(
		func() -> void:
			if visible:
				await get_tree().process_frame
				preview_area.spritesheet_preview.fit_to_view()
				box_editor.fit_to_view()
	)


## Shows [param img] cut where [param data] says the frames are, or else the way that suits
## the open sheet's layout (see [method get_default_cut]). The Grid cut starts from a
## guessed grid; the name of the image at [param path] can hold a size hint. The frames
## are linked to [param path] and [param data_file] when they're given. A colour the image
## is drawn on instead of transparency is made transparent first, see [SheetBackground].
func setup(img: Image, path := "", data: SheetData = null, data_file := "") -> void:
	source_image = img
	sheet_data = data
	image_path = path
	data_path = data_file
	_source_pages = _load_other_pages()
	var found: Variant = SheetBackground.detect(img)
	# Without one, the swatch starts at the top-left pixel, most often the background
	background.set_key(found != null, found if found != null else img.get_pixel(0, 0))
	background.set_picking(false)
	_boxes_found = false
	_remove_background()
	# Packed sheets stay packed when opened, or added to a packed sheet
	var target := Global.spritesheet
	keep_layout.set_pressed_no_signal(
		target.is_empty() or target.layout == Spritesheet.Layout.PACKED
	)
	lock_empty_cells.set_pressed_no_signal(Settings.get_value(&"lock_empty_cells"))
	for field: SpinBox in [offset_x, offset_y, spacing_x, spacing_y]:
		field.set_value_no_signal(0)
	_update_options_label()
	# The offset leaves at least a pixel, and a cell is at most the image
	var image_size := img.get_size()
	_set_max(offset_x, image_size.x - 1)
	_set_max(offset_y, image_size.y - 1)
	_set_max(cell_width, image_size.x)
	_set_max(cell_height, image_size.y)
	_guess_grid()
	cut_option.clear()
	cut_option.add_item("Grid", Cut.GRID)
	cut_option.add_item("Find sprites", Cut.DETECT)
	if data:
		cut_option.add_item(tr("Data: %s") % data_file.get_file(), Cut.DATA)
	set_cut(get_default_cut(data != null, target.layout))


## Fills in the grid guessed from the name of the image and from the gaps between its
## sprites, once its background is transparent. With [param or_keep], a guess of a single
## cell, which finds nothing, keeps the grid there is.
func _guess_grid(or_keep := false) -> void:
	_grid_guessed = true
	# A sprite size in the name is kept when the offset or spacing change
	var image_size := spritesheet_image.get_size()
	var cell_size := GridGuesser.guess_cell_size_from_file_name(image_path, image_size)
	var guessed_size := GridGuesser.guess(spritesheet_image, image_path)
	if or_keep and guessed_size == Vector2i.ONE:
		return
	_by_cell_size = cell_size != Vector2i.ZERO
	grid_columns.set_value_no_signal(guessed_size.x)
	grid_rows.set_value_no_signal(guessed_size.y)
	cell_width.set_value_no_signal(cell_size.x)
	cell_height.set_value_no_signal(cell_size.y)


## Makes the background colour transparent in the images that are cut, when it's on. The
## sprites are to be found again, as that changes where they are.
func _remove_background() -> void:
	spritesheet_image = source_image
	_other_pages = _source_pages
	_boxes_stale = true
	if background.is_on():
		var color := background.get_color()
		var tolerance := background.get_tolerance()
		spritesheet_image = SheetBackground.remove(source_image, color, tolerance)
		_other_pages = []
		for page in _source_pages:
			_other_pages.append(SheetBackground.remove(page, color, tolerance) if page else null)
	box_editor.set_image(spritesheet_image)


## Cuts the image again with the new background at the end of the frame, once for all the
## changes made until then, like dragging in the colour picker
func _on_background_changed() -> void:
	if not _background_queued:
		_background_queued = true
		_cut_with_background.call_deferred()


func _cut_with_background() -> void:
	_background_queued = false
	_remove_background()
	if _grid_guessed:
		_guess_grid(true)
	_slice()


## Remembers with the sources of the frames of [param sheet] that the background was made
## transparent, so reloading them from their files does it again
func _link_background(sheet: Spritesheet) -> void:
	if not background.is_on():
		return
	var color := background.get_color()
	var tolerance := background.get_tolerance()
	sheet.batch(
		func() -> void:
			for coord: Vector2i in sheet.frame_sources.keys():
				var source := FrameSource.with_key(sheet.frame_sources[coord], color, tolerance)
				var origin: Variant = FrameSource.get_origin(sheet, coord)
				sheet.set_frame(coord, sheet.frames[coord], source, origin)
	)


## How an image is cut when it's opened: where its data file says, or else the way that
## suits the open sheet's [param layout], in a grid for the grid layout and by finding the
## sprites for the packed one
static func get_default_cut(has_data: bool, layout: Spritesheet.Layout) -> Cut:
	if has_data:
		return Cut.DATA
	return Cut.DETECT if layout == Spritesheet.Layout.PACKED else Cut.GRID


func get_cut() -> Cut:
	return cut_option.get_selected_id() as Cut


## Cuts the image another way and shows all of it. Cutting with data needs a data file.
func set_cut(cut: Cut) -> void:
	var index := cut_option.get_item_index(cut)
	if index >= 0:
		cut_option.select(index)
	_slice()
	preview_area.spritesheet_preview.fit_to_view()
	box_editor.fit_to_view()


func _slice() -> void:
	var cut := get_cut()
	var grid_controls: Array[Control] = [more_options_btn]
	for field: SpinBox in [grid_columns, cell_width]:
		grid_controls.append(field.get_parent().get_parent())
	for control in grid_controls:
		control.visible = cut == Cut.GRID
	detect_box.visible = cut == Cut.DETECT
	keep_layout.visible = cut != Cut.GRID
	# Found sprites are shown where they are in the image, to edit their boxes
	preview_area.visible = cut != Cut.DETECT
	box_editor.visible = cut == Cut.DETECT
	var keep := keep_layout.button_pressed
	match cut:
		Cut.GRID:
			_cut_grid()
		Cut.DATA:
			_show_cut(
				sheet_data.to_spritesheet(
					spritesheet_image, image_path, data_path, keep, _other_pages
				)
			)
		Cut.DETECT:
			if _boxes_stale:
				_find_sprites()
			var rows := SpriteBoxes.to_rows(box_editor.get_boxes())
			var alignment := align_option.get_selected_id() as Spritesheet.Alignment
			_show_cut(
				SpriteDetector.to_spritesheet(spritesheet_image, rows, alignment, image_path, keep)
			)


## Finds the sprites in the image as it's cut. Boxes edited by hand are replaced, as a
## step that can be undone in the box editor, see [method SpriteBoxEditor.find_again].
func _find_sprites() -> void:
	var rows := SpriteDetector.detect(spritesheet_image, int(merge_distance.value))
	var boxes := SpriteBoxes.from_rows(rows)
	if _boxes_found:
		box_editor.find_again(boxes)
	else:
		box_editor.start(boxes)
	_boxes_found = true
	_boxes_stale = false


## The pages after the first of a packed sheet with a data file, missing ones as empty
## images, which leave their frames out
func _load_other_pages() -> Array[Image]:
	var images: Array[Image] = []
	if sheet_data == null or data_path.is_empty():
		return images
	var paths := sheet_data.get_page_paths(data_path)
	for page in range(1, paths.size()):
		var img := Image.new()
		if not FileAccess.file_exists(paths[page]) or img.load(paths[page]) != OK:
			images.append(null)
			continue
		img.convert(Image.FORMAT_RGBA8)
		images.append(img)
	return images


## Shows frames that were cut without a grid
func _show_cut(sheet: Spritesheet) -> void:
	_link_background(sheet)
	spritesheet = sheet
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()
	preview_area.show_notice("")
	slice_info.text = tr("%d frames") % spritesheet.frames.size()
	if not spritesheet.animations.is_empty():
		slice_info.text += tr(" · %d animations") % spritesheet.animations.size()


func _build_cut_controls() -> void:
	var grid_box := grid_columns.get_parent().get_parent() as Control
	var cut_box := HBoxContainer.new()
	var cut_label := Label.new()
	cut_label.text = "Cut"
	cut_box.add_child(cut_label)
	cut_box.add_child(cut_option)
	cut_option.tooltip_text = (
		"Grid: equal cells. Find sprites: every group of pixels surrounded by transparency,"
		+ " in a box that can be moved, resized, merged or deleted."
		+ " Data: where the data file exported with the image says."
	)
	cut_option.item_selected.connect(func(_index: int) -> void: set_cut(get_cut()))
	LabelLink.link(cut_label, cut_option)
	grid_box.add_sibling(cut_box)
	grid_box.get_parent().move_child(cut_box, 0)

	var merge_label := Label.new()
	merge_label.text = "Join parts within"
	merge_distance.max_value = 64
	merge_distance.suffix = "px"
	merge_distance.tooltip_text = "Parts of a sprite closer than this, like a spark, stay together"
	merge_distance.value_changed.connect(
		func(_value: float) -> void:
			_boxes_stale = true
			_slice()
	)
	SpinScroll.enable(merge_distance)
	var align_label := Label.new()
	align_label.text = "Align"
	align_option.add_item("Centre", Spritesheet.Alignment.CENTER)
	align_option.add_item("Bottom", Spritesheet.Alignment.BOTTOM)
	align_option.tooltip_text = "Bottom keeps the feet of characters on one line"
	align_option.item_selected.connect(func(_index: int) -> void: _slice())
	for control: Control in [merge_label, merge_distance, align_label, align_option]:
		detect_box.add_child(control)
	LabelLink.link(merge_label, merge_distance)
	LabelLink.link(align_label, align_option)
	detect_box.add_theme_constant_override("separation", 8)
	detect_box.visible = false
	cut_box.add_sibling(detect_box)

	keep_layout.text = "Keep the packed layout"
	keep_layout.tooltip_text = (
		"Keeps every sprite where it is in the image, in the packed layout, so an atlas "
		+ "exported again has its frames in the same places"
	)
	# Frames move to other places in the other layout, so it's shown whole again
	keep_layout.toggled.connect(func(_on: bool) -> void: set_cut(get_cut()))
	cut_box.add_child(keep_layout)


func on_preview_update() -> void:
	var selection_size := get_selected_coords().size()
	add_selected_frames_btn.disabled = selection_size == 0
	add_selected_frames_btn.text = tr("Add selected frames (%d)") % selection_size
	# Only shown when some cells have no sprite. The buttons are at the end of the row, so
	# they stay where they are.
	var grid := spritesheet.grid_size if spritesheet else Vector2i.ZERO
	lock_empty_cells.visible = spritesheet != null and spritesheet.frames.size() < grid.x * grid.y


## Cuts the image into [param columns] × [param rows] cells, as big as fit
func update_grid_size(columns: int, rows: int) -> void:
	_by_cell_size = false
	_grid_guessed = false
	grid_columns.set_value_no_signal(columns)
	grid_rows.set_value_no_signal(rows)
	_cut_grid()


## Cuts the image into cells of [param width] × [param height] pixels, as many as fit
func update_cell_size(width: int, height: int) -> void:
	_by_cell_size = true
	_grid_guessed = false
	cell_width.set_value_no_signal(width)
	cell_height.set_value_no_signal(height)
	_cut_grid()


## Cuts the image into a grid, keeping the grid or the cell size, whichever was set last
func _cut_grid() -> void:
	var offset := Vector2i(int(offset_x.value), int(offset_y.value))
	var spacing := Vector2i(int(spacing_x.value), int(spacing_y.value))
	var fitted := Slicer.fit(
		spritesheet_image.get_size(),
		Vector2i(int(grid_columns.value), int(grid_rows.value)),
		Vector2i(int(cell_width.value), int(cell_height.value)),
		offset,
		spacing,
		_by_cell_size
	)
	var grid_size: Vector2i = fitted.grid
	var cell_size: Vector2i = fitted.cell_size
	var result := Slicer.slice(spritesheet_image, grid_size, offset, spacing, cell_size)

	spritesheet = Spritesheet.new()
	spritesheet.begin_batch()
	spritesheet.set_grid_size(grid_size)
	for coord: Vector2i in result.frames:
		var source := FrameSource.for_region(image_path, result.rects[coord]) if image_path else {}
		spritesheet.set_frame(coord, result.frames[coord], source)
	spritesheet.end_batch()
	_link_background(spritesheet)
	_show_slice_info(result.unused)
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()

	grid_columns.set_value_no_signal(grid_size.x)
	grid_rows.set_value_no_signal(grid_size.y)
	cell_width.set_value_no_signal(cell_size.x)
	cell_height.set_value_no_signal(cell_size.y)


func add_spritesheet_to_global() -> void:
	if spritesheet.is_empty():
		close_requested.emit()
		return

	var target := Global.spritesheet
	var lock_empty: bool = Settings.get_value(&"lock_empty_cells")
	Global.document.perform("Add spritesheet", add_sheet.bind(target, spritesheet, lock_empty))
	frames_added.emit()
	close_requested.emit()


## Places the whole grid of [param sheet] below the frames of [param target], keeping
## empty rows and columns. With [param lock_empty], its empty cells are locked so added
## sprites skip them.
static func add_sheet(target: Spritesheet, sheet: Spritesheet, lock_empty: bool) -> void:
	var offset := Vector2i(0, target.get_first_free_row())
	var packed := sheet.layout == Spritesheet.Layout.PACKED
	# A packed sheet's pages go after the open sheet's
	var first_page := 0
	if packed and target.is_empty():
		target.set_atlas_settings(sheet.atlas_settings)
		target.set_export_settings(sheet.export_settings)
		target.set_layout(Spritesheet.Layout.PACKED)
	elif packed:
		first_page = PackedLayout.get_page_count(target)
	target.set_grid_size(target.grid_size.max(sheet.grid_size + offset))
	for coord: Vector2i in sheet.frames:
		var data := sheet.get_cell_data(coord)
		if data.has("placement"):
			data.placement = data.placement.duplicate()
			data.placement.page += first_page
		target.set_cell(coord + offset, data)
	for animation in sheet.animations:
		animation.name = target.get_unique_animation_name(animation.name)
		var cells: Array[Vector2i] = []
		for cell in animation.cells:
			cells.append(cell + offset)
		animation.cells = cells
		# A colour far from the open sheet's animations, not only from its own sheet's,
		# unless the file gave it one (an Aseprite tag's)
		if SheetAnimation.is_palette_color(animation.color):
			animation.color = SheetAnimation.NO_COLOR
		target.add_animation(animation)
	if lock_empty:
		# Only the added sheet's cells, not free cells elsewhere
		target.lock_free_cells(Rect2i(offset, sheet.grid_size))


## The cells of the selected frames: in the preview, or of the selected boxes when finding
## sprites, in reading order
func get_selected_coords() -> Array[Vector2i]:
	if get_cut() != Cut.DETECT:
		return preview_area.spritesheet_preview.get_selected_coords()
	var coords: Array[Vector2i] = []
	var box_coords := SpriteBoxes.get_coords(box_editor.get_boxes())
	for index in box_editor.get_selected():
		coords.append(box_coords[index])
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return coords


func add_selected_frames_to_global() -> void:
	var cells: Array[Dictionary] = []
	for coord in get_selected_coords():
		cells.append(spritesheet.get_cell_data(coord))
	var target := Global.spritesheet
	Global.document.perform(
		"Add frames", target.add_cells.bind(cells, Settings.get_value(&"add_mode"))
	)
	frames_added.emit()
	close_requested.emit()


func _show_slice_info(unused: Vector2i) -> void:
	slice_info.text = tr("%d frames") % spritesheet.frames.size()
	# Over the preview, so the bar above doesn't change width
	var parts: PackedStringArray = []
	if unused.x > 0:
		parts.append(tr("%d px on the right") % unused.x)
	if unused.y > 0:
		parts.append(tr("%d px at the bottom") % unused.y)
	preview_area.show_notice(
		tr("%s not used") % " and ".join(parts) if parts else "",
		"The image doesn't divide evenly into this grid"
	)


## Sets the most [param field] takes without cutting the image again
static func _set_max(field: Range, value: float) -> void:
	field.set_block_signals(true)
	field.max_value = value
	field.set_block_signals(false)


## Shows the offset and spacing on the button when they're set
func _update_options_label() -> void:
	more_options_btn.update_text()


## The offset and spacing when they're set, for the button that shows them
func _options_summary() -> String:
	var offset := Vector2i(int(offset_x.value), int(offset_y.value))
	var spacing := Vector2i(int(spacing_x.value), int(spacing_y.value))
	var parts: PackedStringArray = []
	if offset != Vector2i.ZERO:
		parts.append(tr("Offset %d×%d") % [offset.x, offset.y])
	if spacing != Vector2i.ZERO:
		parts.append(tr("Spacing %d×%d") % [spacing.x, spacing.y])
	return " · ".join(parts)
