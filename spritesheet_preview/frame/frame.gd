class_name SpritesheetPreviewFrame
extends TextureRect


signal selection_updated

enum SelectionMode {NONE, SELECTING, DESELECTING}

@onready var selection_panel: Panel = $SelectionPanel

static var selection_mode: SelectionMode = SelectionMode.NONE

var selected := false:
	set = set_selected
var coordinate_in_spritesheet := -Vector2i.ONE
var img: Image


func _ready() -> void:
	mouse_entered.connect(
		func():
			if Input.is_action_pressed("select"):
				if selection_mode == SelectionMode.SELECTING:
					set_selected(true)
				elif selection_mode == SelectionMode.DESELECTING:
					set_selected(false)
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var s := not selected
			selection_mode = SelectionMode.SELECTING if s else SelectionMode.DESELECTING
			set_selected(s)


func setup(spritesheet: Spritesheet, coordinate: Vector2i):
	var img_texture := ImageTexture.new()
	img_texture.set_image(spritesheet.frames[coordinate])
	texture = img_texture
	size = spritesheet.sprite_size
	position.x = spritesheet.sprite_size.x * coordinate.x
	position.y = spritesheet.sprite_size.y * coordinate.y
	
	var coordinate_label: Label = get_node("%Coordinate")
	coordinate_label.text = str(coordinate.y * spritesheet.grid_size.x + coordinate.x)
	if size < Vector2(50, 50):
		coordinate_label.visible = false
	
	coordinate_in_spritesheet = coordinate
	img = spritesheet.frames[coordinate]


func set_selected(v: bool):
	selected = v
	selection_panel.visible = selected
	selection_updated.emit()
