class_name SpritesheetPreview
extends Node2D

const FRAME_SCENE := preload("res://spritesheet_preview/frame/frame.tscn")
const MOUSE_WHEEL_ZOOM_FORCE := 0.2
const MAX_ZOOM := 10
const MIN_ZOOM := 0.02

@onready var camera: Camera2D = $Camera2D
@onready var sprites: Node2D = $Sprites


var spritesheet: Spritesheet:
	set(v):
		spritesheet = v 
		v.updated.connect(update_preview)
var start_drag_position := Vector2.ZERO
var start_camera_position := Vector2.ZERO


func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_drag"):
		start_drag_position = get_viewport().get_mouse_position()
		start_camera_position = camera.position
	if Input.is_action_pressed("ui_drag"):
		camera.position = (
			+ start_camera_position 
			- (get_viewport().get_mouse_position() - start_drag_position)
				/ camera.zoom
		)
	
	if Input.is_action_pressed("mouse_wheel_up"):
		camera.zoom += Vector2(MOUSE_WHEEL_ZOOM_FORCE, MOUSE_WHEEL_ZOOM_FORCE) * camera.zoom.x
	elif Input.is_action_pressed("mouse_wheel_down"):
		camera.zoom -= Vector2(MOUSE_WHEEL_ZOOM_FORCE, MOUSE_WHEEL_ZOOM_FORCE) * camera.zoom.x
	camera.zoom = clamp(camera.zoom, Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
	

func _draw() -> void:
	if not spritesheet:
		return
	
	for row in spritesheet.grid_size.y + 1:
		draw_line(
			Vector2(0, row * spritesheet.sprite_size.y), 
			Vector2(spritesheet.grid_size.x * spritesheet.sprite_size.x, row * spritesheet.sprite_size.y),
			Color.WHITE,
		)
	
	for column in spritesheet.grid_size.x + 1:
		draw_line(
			Vector2(column * spritesheet.sprite_size.x, 0), 
			Vector2(column * spritesheet.sprite_size.x, spritesheet.grid_size.y * spritesheet.sprite_size.y),
			Color.WHITE,
		)


func update_preview() -> void:
	for child in sprites.get_children():
		child.queue_free()
	
	for img_coord in spritesheet.frames:
		var frame: SpritesheetPreviewFrame = FRAME_SCENE.instantiate()
		frame.setup(spritesheet, img_coord)
		sprites.add_child(frame)
	
	queue_redraw()
