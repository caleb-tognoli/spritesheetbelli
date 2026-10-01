class_name FrameMover
extends RefCounted
## Frames of a [SpritesheetPreview] being dragged to another place: which they are, where
## they'd land and, in the packed layout, whether they fit there, drawn there over the
## sheet. In the grid they move by whole cells; packed, by pixels onto the page under the
## mouse. Frames dragged out of the preview stay lifted while [member carried], to move
## them again if they come back, see [method SpritesheetPreview.carry_back].

## The frames being moved, drawn where they'd land
const GHOST_COLOR := Color(1, 1, 1, 0.6)
const INVALID_COLOR := Color(1, 0.3, 0.3, 0.6)

## The frames being moved, in reading order, or none
var lifted: Array[Vector2i] = []
## How far they'd move: in cells in the grid, in pixels on pages
var offset := Vector2i.ZERO
## The page packed frames are dragged from and onto, and whether they fit there
var start_page := 0
var page := 0
var fits := true
## Whether the frames lifted were dragged out of the preview, and what follows the mouse
## with them, hidden while they're back over it
var carried := false
var card: Control

## Where the drag started, and in which cell, even outside the grid
var _start_world := Vector2.ZERO
var _start_cell := Vector2i.ZERO


## Lifts [param coords] of [param canvas], dragged from [param world]
func lift(canvas: SpritesheetPreview, coords: Array[Vector2i], world: Vector2) -> void:
	lifted = coords
	offset = Vector2i.ZERO
	_start_world = world
	_start_cell = canvas.grid_view.get_cell_unclamped(world)
	var placements := canvas.spritesheet.placements
	start_page = placements[coords[0]].page if placements.has(coords[0]) else 0
	page = start_page
	fits = true


## Follows the mouse at [param world]. Whether where they'd land changed.
func follow(canvas: SpritesheetPreview, world: Vector2) -> bool:
	if canvas.is_packed():
		return _follow_on_pages(canvas, world)
	var to := canvas.grid_view.get_cell_unclamped(world) - _start_cell
	# Every moved frame stays inside the positive quadrant
	for coord in lifted:
		to = to.max(-coord)
	if to == offset:
		return false
	offset = to
	return true


## Where packed frames would go: the page under the mouse, whole pixels away from where
## they are, and whether they fit there
func _follow_on_pages(canvas: SpritesheetPreview, world: Vector2) -> bool:
	var on := canvas.packed_view.get_page_at(world)
	if on < 0:
		on = page
	# Frames stay under the mouse when they go to another page
	var origins := canvas.packed_view.page_origins
	var to := Vector2i((world - _start_world + origins[start_page] - origins[on]).round())
	if to == offset and on == page:
		return false
	offset = to
	page = on
	fits = not PackedLayout.moved(canvas.spritesheet, lifted, on, to).is_empty()
	return true


## Asks [param canvas] to move the frames where they'd land, with its signals, and puts
## them down
func put_down(canvas: SpritesheetPreview) -> void:
	if canvas.is_packed():
		if fits and (offset != Vector2i.ZERO or page != start_page):
			canvas.placement_move_requested.emit(lifted, page, offset)
	elif offset != Vector2i.ZERO:
		canvas.move_requested.emit(lifted, offset)
	drop()


## Puts the frames down where they are
func drop() -> void:
	lifted = []
	offset = Vector2i.ZERO
	fits = true
	carried = false
	card = null


## Shows what follows the mouse while the frames are carried off the preview, or hides it
func show_card(shown: bool) -> void:
	if card:
		card.visible = shown


## Draws the frames lifted where they'd land, outlined, in red packed where they don't fit
func draw(canvas: SpritesheetPreview, pixel: float) -> void:
	var outline := canvas.selection_color if fits else INVALID_COLOR
	for coord in lifted:
		var target := canvas.cell_rect(coord + offset)
		if canvas.is_packed():
			var origins := canvas.packed_view.page_origins
			var from_page: int = canvas.spritesheet.placements[coord].page
			target = canvas.packed_view.get_frame_rect(coord)
			target.position += Vector2(offset) + origins[page] - origins[from_page]
			canvas.packed_view.draw_frame(canvas, coord, target, GHOST_COLOR)
		else:
			canvas.grid_view.draw_frame(canvas, coord, target, GHOST_COLOR)
		canvas.draw_rect(target.grow(-pixel), outline, false, pixel * 2)
