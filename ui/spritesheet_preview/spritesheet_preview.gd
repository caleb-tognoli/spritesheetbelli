class_name SpritesheetPreview
extends Node2D


signal preview_updated

const FRAME_SCENE := preload("res://ui/spritesheet_preview/frame/frame.tscn")
const EMPTY_SPACE_SCENE := preload("res://ui/spritesheet_preview/empty_space/empty_space.tscn")
const GRID_COLOR := Color(Color.LIGHT_GRAY, 0.8)
const MOUSE_WHEEL_ZOOM_FORCE := 0.2
const MAX_ZOOM := 10
const MIN_ZOOM := 0.02

@onready var camera: Camera2D = $Camera2D
@onready var frames: Node2D = $Frames
@onready var empty_spaces: Node2D = $EmptySpaces

@export var able_to_lock_spaces := true

var spritesheet: Spritesheet = Spritesheet.new():
	set(v):
		spritesheet = v
		update_preview()
		v.updated.connect(update_preview)
var start_drag_position := Vector2.ZERO
var start_camera_position := Vector2.ZERO


func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_drag"):
		start_drag_position = get_viewport().get_mouse_position()
		start_camera_position = camera.position
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		for frame: Control in frames.get_children():
			frame.set_default_cursor_shape(Control.CURSOR_DRAG)
	elif Input.is_action_just_released("ui_drag"):
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		for frame: Control in frames.get_children():
			frame.set_default_cursor_shape(Control.CURSOR_ARROW)
	elif Input.is_action_pressed("ui_drag"):
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
			GRID_COLOR,
		)
	
	for column in spritesheet.grid_size.x + 1:
		draw_line(
			Vector2(column * spritesheet.sprite_size.x, 0), 
			Vector2(column * spritesheet.sprite_size.x, spritesheet.grid_size.y * spritesheet.sprite_size.y),
			GRID_COLOR,
		)


func update_preview() -> void:
	for child in frames.get_children():
		child.free()
	for child in empty_spaces.get_children():
		child.free()
	
	for row in spritesheet.grid_size.y:
		for column in spritesheet.grid_size.x:
			var coord := Vector2i(column, row)
			
			if coord in spritesheet.frames:
				var frame: SpritesheetPreviewFrame = FRAME_SCENE.instantiate()
				frame.setup(spritesheet, coord)
				frame.selection_updated.connect(preview_updated.emit)
				frames.add_child(frame)
			elif able_to_lock_spaces:
				var empty_space: SpritesheetPreviewEmptySpace = EMPTY_SPACE_SCENE.instantiate()
				empty_space.setup(spritesheet, coord)
				empty_space.lock_updated.connect(
					set_locked_coordinate_in_spritesheet.bind(coord)
				)
				empty_space.set_is_locked(coord in spritesheet.locked_coordinates)
				empty_spaces.add_child(empty_space)
	
	queue_redraw()
	preview_updated.emit()


func get_selected_frames() -> Dictionary:
	var frames_dict: Dictionary = {}
	for frame: SpritesheetPreviewFrame in frames.get_children():
		if frame.selected:
			frames_dict[frame.coordinate_in_spritesheet] = frame.img
	return frames_dict


func set_locked_coordinate_in_spritesheet(lock: bool, coord: Vector2i):
	if lock and not spritesheet.locked_coordinates.has(coord):
		spritesheet.locked_coordinates.append(coord)
	elif not lock and spritesheet.locked_coordinates.has(coord):
		spritesheet.locked_coordinates.erase(coord)
