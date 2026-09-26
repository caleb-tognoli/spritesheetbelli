class_name AddSpritesheetWindow
extends Window

const DROPDOWN_ICON := preload("res://assets/icons/GuiTreeArrowDown.svg")

signal canceled
## Emitted after frames were added to the open spritesheet
signal frames_added

@onready var preview_area: PreviewArea = %PreviewArea
@onready var add_selected_frames_btn: Button = %AddSelectedFrames
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var grid_columns: SpinBox = %GridColumns
@onready var grid_rows: SpinBox = %GridRows
@onready var offset_x: SpinBox = %OffsetX
@onready var offset_y: SpinBox = %OffsetY
@onready var spacing_x: SpinBox = %SpacingX
@onready var spacing_y: SpinBox = %SpacingY
@onready var slice_info: Label = %SliceInfo

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
var more_options_btn := Button.new()
var more_options_popup := PopupPanel.new()
## Keeps the sprites where they are in the image, in the packed layout
var keep_layout := CheckBox.new()
## The other pages of a packed sheet with a data file, by page
var _other_pages: Array[Image] = []


func _ready() -> void:
	close_requested.connect(hide)
	close_requested.connect(canceled.emit)
	add_selected_frames_btn.pressed.connect(add_selected_frames_to_global)
	add_selected_frames_btn.icon = preload("res://assets/icons/Add.svg")
	add_spritesheet_btn.icon = preload("res://assets/icons/SpriteSheet.svg")
	add_spritesheet_btn.pressed.connect(add_spritesheet_to_global)
	preview_area.spritesheet_preview.selection_changed.connect(on_preview_update)
	grid_columns.value_changed.connect(
		func(columns: float) -> void: update_grid_size(int(columns), spritesheet.grid_size.y)
	)
	grid_rows.value_changed.connect(
		func(rows: float) -> void: update_grid_size(spritesheet.grid_size.x, int(rows))
	)

	for field: SpinBox in [grid_columns, grid_rows, offset_x, offset_y, spacing_x, spacing_y]:
		SpinScroll.enable(field)
	for field: SpinBox in [offset_x, offset_y, spacing_x, spacing_y]:
		field.value_changed.connect(
			func(_value: float) -> void:
				update_grid_size(spritesheet.grid_size.x, spritesheet.grid_size.y)
				_update_options_label()
		)

	# Offset and spacing are rarely needed, so they're in a panel that drops down
	var offset_box := offset_x.get_parent().get_parent() as Control
	var spacing_box := spacing_x.get_parent().get_parent() as Control
	more_options_btn.icon = DROPDOWN_ICON
	more_options_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	more_options_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more_options_btn.tooltip_text = "For sheets with a margin around or gaps between the frames"
	offset_box.add_sibling(more_options_btn)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 8)
	more_options_popup.add_child(fields)
	add_child(more_options_popup)
	for box: Control in [offset_box, spacing_box]:
		box.reparent(fields, false)
		LabelLink.link(box.get_child(0) as Label, box.get_child(1) as Control)
	more_options_btn.pressed.connect(
		func() -> void:
			var below := more_options_btn.get_global_rect()
			below.position.y += below.size.y + 4
			more_options_popup.popup_on_parent(Rect2i(Rect2(below.position, Vector2.ZERO)))
	)
	_update_options_label()

	_build_cut_controls()

	preview_area.spritesheet_preview.able_to_lock_spaces = false
	preview_area.spritesheet_preview.able_to_move_frames = false
	# Show the whole sheet once the window has its size
	visibility_changed.connect(
		func() -> void:
			if visible:
				await get_tree().process_frame
				preview_area.spritesheet_preview.fit_to_view()
	)


## Shows [param img] cut where [param data] says the frames are, or else sliced into a
## guessed grid. The name of the image at [param path] can hold a size hint. The frames
## are linked to [param path] and [param data_file] when they're given.
func setup(img: Image, path := "", data: SheetData = null, data_file := "") -> void:
	spritesheet_image = img
	sheet_data = data
	image_path = path
	data_path = data_file
	_other_pages = _load_other_pages()
	# Packed sheets stay packed when opened, or added to a packed sheet
	var target := Global.spritesheet
	keep_layout.set_pressed_no_signal(
		target.is_empty() or target.layout == Spritesheet.Layout.PACKED
	)
	for field: SpinBox in [offset_x, offset_y, spacing_x, spacing_y]:
		field.set_value_no_signal(0)
	_update_options_label()

	var guessed_size := GridGuesser.guess(img, path.get_file())
	grid_columns.set_value_no_signal(guessed_size.x)
	grid_rows.set_value_no_signal(guessed_size.y)
	cut_option.clear()
	cut_option.add_item("Grid", Cut.GRID)
	cut_option.add_item("Find sprites", Cut.DETECT)
	if data:
		cut_option.add_item(tr("Data: %s") % data_file.get_file(), Cut.DATA)
	set_cut(Cut.DATA if data else Cut.GRID)

	preview_area.spritesheet_preview.camera.position = Vector2.ONE * -50
	preview_area.spritesheet_preview.set_zoom(1)


func get_cut() -> Cut:
	return cut_option.get_selected_id() as Cut


## Cuts the image another way. Cutting with data needs a data file.
func set_cut(cut: Cut) -> void:
	var index := cut_option.get_item_index(cut)
	if index >= 0:
		cut_option.select(index)
	_slice()


func _slice() -> void:
	var cut := get_cut()
	for control: Control in [grid_columns.get_parent().get_parent(), more_options_btn]:
		control.visible = cut == Cut.GRID
	detect_box.visible = cut == Cut.DETECT
	keep_layout.visible = cut != Cut.GRID
	var keep := keep_layout.button_pressed
	match cut:
		Cut.GRID:
			update_grid_size(int(grid_columns.value), int(grid_rows.value))
		Cut.DATA:
			_show_cut(
				sheet_data.to_spritesheet(
					spritesheet_image, image_path, data_path, keep, _other_pages
				)
			)
		Cut.DETECT:
			var rows := SpriteDetector.detect(spritesheet_image, int(merge_distance.value))
			var alignment := align_option.get_selected_id() as Spritesheet.Alignment
			_show_cut(
				SpriteDetector.to_spritesheet(spritesheet_image, rows, alignment, image_path, keep)
			)


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
	spritesheet = sheet
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()
	slice_info.remove_theme_color_override("font_color")
	slice_info.tooltip_text = ""
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
		"Grid: equal cells. Find sprites: every group of pixels surrounded by transparency."
		+ " Data: where the data file exported with the image says."
	)
	cut_option.item_selected.connect(func(_index: int) -> void: _slice())
	LabelLink.link(cut_label, cut_option)
	grid_box.add_sibling(cut_box)
	grid_box.get_parent().move_child(cut_box, 0)

	var merge_label := Label.new()
	merge_label.text = "Join parts within"
	merge_distance.max_value = 64
	merge_distance.suffix = "px"
	merge_distance.tooltip_text = "Parts of a sprite closer than this, like a spark, stay together"
	merge_distance.value_changed.connect(func(_value: float) -> void: _slice())
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
	keep_layout.toggled.connect(func(_on: bool) -> void: _slice())
	cut_box.add_child(keep_layout)


func on_preview_update() -> void:
	var selection_size := preview_area.spritesheet_preview.get_selected_coords().size()
	add_selected_frames_btn.disabled = selection_size == 0
	add_selected_frames_btn.text = tr("Add selected frames (%d)") % selection_size


func update_grid_size(columns: int, rows: int) -> void:
	rows = max(1, rows)
	columns = max(1, columns)
	spritesheet = Spritesheet.new()
	var grid_size := Vector2i(columns, rows)
	var offset := Vector2i(int(offset_x.value), int(offset_y.value))
	var spacing := Vector2i(int(spacing_x.value), int(spacing_y.value))
	var result := Slicer.slice(spritesheet_image, grid_size, offset, spacing)

	spritesheet.begin_batch()
	spritesheet.set_grid_size(grid_size)
	for coord: Vector2i in result.frames:
		var source := FrameSource.for_region(image_path, result.rects[coord]) if image_path else {}
		spritesheet.set_frame(coord, result.frames[coord], source)
	spritesheet.end_batch()
	_show_slice_info(result.cell_size, result.unused)
	preview_area.spritesheet_preview.spritesheet = spritesheet
	on_preview_update()

	grid_columns.set_value_no_signal(columns)
	grid_rows.set_value_no_signal(rows)


func add_spritesheet_to_global() -> void:
	if spritesheet.is_empty():
		close_requested.emit()
		return

	# Place the whole grid below the existing frames, keeping empty rows and columns
	var target := Global.spritesheet
	Global.document.perform(
		"Add spritesheet",
		func() -> void:
			var offset := Vector2i(0, target.get_first_free_row())
			var packed := spritesheet.layout == Spritesheet.Layout.PACKED
			# A packed sheet's pages go after the open sheet's
			var first_page := 0
			if packed and target.is_empty():
				target.set_atlas_settings(spritesheet.atlas_settings)
				target.set_export_settings(spritesheet.export_settings)
				target.set_layout(Spritesheet.Layout.PACKED)
			elif packed:
				first_page = PackedLayout.get_page_count(target)
			target.set_grid_size(target.grid_size.max(spritesheet.grid_size + offset))
			for coord: Vector2i in spritesheet.frames:
				var data := spritesheet.get_cell_data(coord)
				if data.has("placement"):
					data.placement = data.placement.duplicate()
					data.placement.page += first_page
				target.set_cell(coord + offset, data)
			for row: int in spritesheet.row_names:
				target.set_row_name(row + offset.y, spritesheet.row_names[row])
			for animation in spritesheet.animations:
				animation.name = target.get_unique_animation_name(animation.name)
				var cells: Array[Vector2i] = []
				for cell in animation.cells:
					cells.append(cell + offset)
				animation.cells = cells
				target.add_animation(animation)
			# Keep the added sheet's layout without touching free cells elsewhere
			target.lock_free_cells(Rect2i(offset, spritesheet.grid_size))
	)
	frames_added.emit()
	close_requested.emit()


func add_selected_frames_to_global() -> void:
	var cells: Array[Dictionary] = []
	for coord in preview_area.spritesheet_preview.get_selected_coords():
		cells.append(spritesheet.get_cell_data(coord))
	var target := Global.spritesheet
	Global.document.perform(
		"Add frames", target.add_cells.bind(cells, Settings.get_value(&"add_mode"))
	)
	frames_added.emit()
	close_requested.emit()


func _show_slice_info(cell_size: Vector2i, unused: Vector2i) -> void:
	slice_info.text = tr("Cell size: %d×%d px") % [cell_size.x, cell_size.y]
	slice_info.tooltip_text = ""
	slice_info.remove_theme_color_override("font_color")
	if unused != Vector2i.ZERO:
		var parts: PackedStringArray = []
		if unused.x > 0:
			parts.append("%d px on the right" % unused.x)
		if unused.y > 0:
			parts.append("%d px at the bottom" % unused.y)
		slice_info.text += tr(" · %s not used") % " and ".join(parts)
		slice_info.tooltip_text = "The image doesn't divide evenly into this grid"
		slice_info.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))


## Shows the offset and spacing on the button when they're set
func _update_options_label() -> void:
	var offset := Vector2i(int(offset_x.value), int(offset_y.value))
	var spacing := Vector2i(int(spacing_x.value), int(spacing_y.value))
	var parts: PackedStringArray = []
	if offset != Vector2i.ZERO:
		parts.append(tr("Offset %d×%d") % [offset.x, offset.y])
	if spacing != Vector2i.ZERO:
		parts.append(tr("Spacing %d×%d") % [spacing.x, spacing.y])
	more_options_btn.text = " · ".join(parts) if parts else tr("Offset & Spacing")
