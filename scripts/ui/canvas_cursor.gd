class_name CanvasCursor
## The mouse cursor over the canvases (the sheet's preview and the boxes in Add
## Spritesheet), in one place: each canvas says what pressing or dragging where the mouse is
## would do, as a [enum Hint], and [method apply] shows the system cursor for it. Only the
## system's cursors are used, so they keep the size and colour set for them.
##
## A canvas shows its cursor on a Control of its own, never as the app's default cursor,
## so it never shows over other panels.

enum Hint {
	NONE,  ## Nothing to drag here: the arrow
	PAN,  ## Dragging pans, or is panning
	PICK,  ## Clicking picks a colour
	GRAB,  ## Dragging moves what's under the mouse
	MOVE,  ## Moving something
	BOX,  ## Drawing a selection box
	POINT,  ## Dragging puts a point somewhere, like a pivot, or draws a box from there
	LINK,  ## Clicking does something, like an animation's name
	RESIZE_H,  ## Dragging a left or right edge
	RESIZE_V,  ## Dragging a top or bottom edge
	RESIZE_FDIAG,  ## Dragging the top-left or bottom-right corner
	RESIZE_BDIAG,  ## Dragging the top-right or bottom-left corner
	FORBIDDEN,  ## Letting go here does nothing
}

const SHAPES: Dictionary[Hint, Control.CursorShape] = {
	Hint.NONE: Control.CURSOR_ARROW,
	Hint.PAN: Control.CURSOR_DRAG,
	Hint.PICK: Control.CURSOR_CROSS,
	Hint.GRAB: Control.CURSOR_MOVE,
	Hint.MOVE: Control.CURSOR_MOVE,
	Hint.BOX: Control.CURSOR_CROSS,
	Hint.POINT: Control.CURSOR_CROSS,
	Hint.LINK: Control.CURSOR_POINTING_HAND,
	Hint.RESIZE_H: Control.CURSOR_HSIZE,
	Hint.RESIZE_V: Control.CURSOR_VSIZE,
	Hint.RESIZE_FDIAG: Control.CURSOR_FDIAGSIZE,
	Hint.RESIZE_BDIAG: Control.CURSOR_BDIAGSIZE,
	Hint.FORBIDDEN: Control.CURSOR_FORBIDDEN,
}


static func shape(hint: Hint) -> Control.CursorShape:
	return SHAPES[hint]


## Shows the cursor for [param hint] over [param control], right away
static func apply(control: Control, hint: Hint) -> void:
	if control:
		control.mouse_default_cursor_shape = shape(hint)
