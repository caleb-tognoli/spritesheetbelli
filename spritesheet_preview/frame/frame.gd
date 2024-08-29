class_name SpritesheetPreviewFrame
extends TextureRect


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
