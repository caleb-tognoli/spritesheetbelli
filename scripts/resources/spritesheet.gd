class_name Spritesheet
extends Resource


signal updated


enum ImageFormats {PNG, JPG, WEBP}
enum AddMode {
	FIRST_FREE_IN_LAST_ROW_WITH_FRAMES
} 

var grid_size: Vector2i = Vector2i.ZERO:
	set = set_grid_size
var sprite_size: Vector2i = Vector2i.ZERO
var frames: Dictionary = {} #Frame coordinate -> image


func is_empty() -> bool:
	return frames.is_empty()


func set_grid_size(size: Vector2i):
	size.x = max(0, size.x)
	size.y = max(0, size.y)
	
	if size.x == 0 or size.y == 0:
		size = Vector2i.ZERO
		sprite_size = Vector2i.ZERO
	else:
		size.y = max(1, size.y)
		size.x = max(1, size.x)
	
	grid_size = size
	
	for frame_coords in frames.keys():
		if frame_coords.x >= grid_size.x or frame_coords.y >= grid_size.y:
			frames.erase(frame_coords)
	
	updated.emit()


func add_rows(amount: int = 0):
	grid_size = Vector2i(grid_size.x, grid_size.y + amount)

func add_columns(amount: int = 0):
	grid_size = Vector2i(grid_size.x + amount, grid_size.y)


func resize_frames(size: Vector2i):
	sprite_size = size
	for frame: Image in frames.values():
		frame.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)
	updated.emit()


func get_free_space(_add_mode: AddMode = AddMode.FIRST_FREE_IN_LAST_ROW_WITH_FRAMES) -> Vector2i:
	var last_row_with_frames := -1
	for coord in frames:
		last_row_with_frames = max(coord.y, last_row_with_frames)
	
	if last_row_with_frames == -1:
		#print("first row is empty")
		return Vector2i(0, 0)
	
	for column in grid_size.x:
		if not frames.has(Vector2i(column, last_row_with_frames)):
			#print("last row still has space")
			return Vector2i(column, last_row_with_frames)
	
	if (last_row_with_frames + 1 < grid_size.y 
			and not frames.has(Vector2(0, last_row_with_frames + 1))):
		#print("Went to free row")
		return Vector2i(0, last_row_with_frames + 1)
	
	if grid_size.y == 1:
		#print("only 1 row, add a column")
		add_columns(1)
		return Vector2i(grid_size.x - 1, 0)
	
	#print("new row")
	add_rows(1)
	return Vector2i(0, grid_size.y - 1)


func add_sprites(paths: PackedStringArray, add_mode: AddMode = AddMode.FIRST_FREE_IN_LAST_ROW_WITH_FRAMES) -> void:
	if is_empty() and grid_size == Vector2i.ZERO:
		grid_size = Vector2i.ONE
	
	for path: String in paths:
		var img := Image.new()
		img.load(path)
		img.convert(Image.FORMAT_RGBA8)
		
		var img_size: Vector2i = img.get_size()
		sprite_size.x = max(img_size.x, sprite_size.x)
		sprite_size.y = max(img_size.y, sprite_size.y)
		
		var end_space := get_free_space(add_mode)
		frames[end_space] = img
		
	for frame_coord in frames:
		var sprite := Image.create_empty(sprite_size.x, sprite_size.y, false, Image.FORMAT_RGBA8)
		var center := Rect2i(Vector2i.ZERO, frames[frame_coord].get_size())
		sprite.blend_rect(frames[frame_coord], center, (sprite.get_size() - frames[frame_coord].get_size()) / 2)
		frames[frame_coord] = sprite

	updated.emit()


func get_subviewport() -> SubViewport:
	var spritesheet_vp = SubViewport.new()
	spritesheet_vp.transparent_bg = true
	spritesheet_vp.size = Vector2(
		sprite_size.x * grid_size.x,
		sprite_size.y * grid_size.y
	)
	spritesheet_vp.render_target_clear_mode = SubViewport.UPDATE_ALWAYS
	spritesheet_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	var sprites := Node2D.new()
	for img_coord in frames:
		var texture := ImageTexture.new()
		texture.set_image(frames[img_coord])
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position.x = sprite_size.x * img_coord.x
		sprite.position.y = sprite_size.y * img_coord.y
		sprites.add_child(sprite)
	
	sprites.position = sprite_size / 2
	spritesheet_vp.add_child(sprites)
	return spritesheet_vp
