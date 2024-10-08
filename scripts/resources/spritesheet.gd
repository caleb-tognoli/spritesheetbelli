class_name Spritesheet
extends Resource


signal updated

enum ImageFormats {PNG, JPG, WEBP}
enum FreeSpace {
	AT_END,
	FREE_ROW_AT_END,
}
enum AddMode {
	SINGLE_SPRITE,
	ROW
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


func get_free_space(free_space_mode: FreeSpace = FreeSpace.AT_END) -> Vector2i:
	#print("setup")
	if is_empty():
		return Vector2i(0, 0)
	var last_row_with_frames := get_first_free_row() - 1
	
	#print("last row still has space")
	if free_space_mode in [FreeSpace.AT_END]:
		var last_frame_column: int = 0
		for column in grid_size.x:
			if frames.has(Vector2i(column, last_row_with_frames)):
				last_frame_column = column
		if last_frame_column + 1 < grid_size.x:
			return Vector2i(last_frame_column + 1, last_row_with_frames)
	
	#print("only 1 row, add a column")
	if free_space_mode in [FreeSpace.AT_END]:
		if grid_size.y == 1:
			return Vector2i(grid_size.x, 0)
	
	#print("free row at end")
	return Vector2i(0, last_row_with_frames + 1)


func get_first_free_row() -> int:
	var last_row_with_frames := -1
	for coord in frames:
		last_row_with_frames = max(coord.y, last_row_with_frames)
	return last_row_with_frames + 1


func add_frames(imgs: Array[Image], add_mode: AddMode = AddMode.SINGLE_SPRITE) -> void:
	match add_mode:
		AddMode.SINGLE_SPRITE:
			for img: Image in imgs:
				var free_space := get_free_space(FreeSpace.AT_END)
				add_frame_at_coordinate(img, free_space)
		AddMode.ROW:
			var free_space := get_free_space(FreeSpace.FREE_ROW_AT_END)
			for img: Image in imgs: 
				add_frame_at_coordinate(img, free_space)
				free_space.x += 1


func add_frame_at_coordinate(img: Image, coordinate: Vector2i):
	var max_coord_x: int = max(coordinate.x + 1, grid_size.x)
	var max_coord_y: int = max(coordinate.y + 1, grid_size.y)
	grid_size = Vector2i(max_coord_x, max_coord_y)
	
	img.convert(Image.FORMAT_RGBA8)
	var img_size: Vector2i = img.get_size()
	sprite_size.x = max(img_size.x, sprite_size.x)
	sprite_size.y = max(img_size.y, sprite_size.y)
	
	frames[coordinate] = img
	pad_frames_to_sprite_size()
	updated.emit()


func pad_frames_to_sprite_size():
	for frame_coord in frames:
		if frames[frame_coord].get_size() < sprite_size:
			var img := Image.create_empty(sprite_size.x, sprite_size.y, false, Image.FORMAT_RGBA8)
			var center := Rect2i(Vector2i.ZERO, frames[frame_coord].get_size())
			img.blend_rect(frames[frame_coord], center, (img.get_size() - frames[frame_coord].get_size()) / 2)
			frames[frame_coord] = img


func get_image() -> Image:
	var img := Image.create_empty(
		sprite_size.x * grid_size.x, 
		sprite_size.y * grid_size.y,
		false,
		Image.Format.FORMAT_RGBA8
	)
	
	if img.get_size() == Vector2i.ZERO:
		return img
	
	for frame_coord in frames:
		img.blend_rect(
			frames[frame_coord],
			Rect2i(Vector2i.ZERO, sprite_size),
			sprite_size * frame_coord
		)
	return img
