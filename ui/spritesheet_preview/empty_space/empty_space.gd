class_name SpritesheetPreviewEmptySpace
extends PanelContainer


signal lock_updated(is_locked: bool)

const HOVER_ALPHA := 0.25
const LOCKED_ALPHA := 0.8

var coordinate_in_spritesheet := -Vector2i.ONE
var is_locked: bool = false: set = set_is_locked


func _draw() -> void:
	const BASE_SIZE_LENGTH := 200
	var line_amount: int = int(size.length() * 1 / BASE_SIZE_LENGTH)
	var line_spacing_x := size.x / line_amount
	var line_spacing_y := size.y / line_amount
	
	var line_color := Color.LIGHT_GRAY
	
	for i in line_amount:
		draw_line(
			Vector2(line_spacing_x * i, size.y),
			Vector2(0, line_spacing_y * (line_amount - i)), 
			line_color
		)
		draw_line(
			Vector2(line_spacing_x * i, 0),
			Vector2(size.x, line_spacing_y * (line_amount - i)), 
			line_color
		)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			is_locked = not is_locked


func setup(spritesheet: Spritesheet, coordinate: Vector2i):
	size = spritesheet.sprite_size
	position.x = spritesheet.sprite_size.x * coordinate.x
	position.y = spritesheet.sprite_size.y * coordinate.y
	coordinate_in_spritesheet = coordinate
	queue_redraw()


func set_is_locked(v: bool):
	is_locked = v
	lock_updated.emit(is_locked)
	
	if is_locked:
		modulate.a = LOCKED_ALPHA
	else:
		modulate.a = 0


func _on_mouse_entered() -> void:
	if not is_locked:
		modulate.a = HOVER_ALPHA


func _on_mouse_exited() -> void:
	if not is_locked:
		modulate.a = 0
