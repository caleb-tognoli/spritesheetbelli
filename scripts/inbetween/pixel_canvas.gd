class_name PixelCanvas
extends RefCounted
## Helpers for making in-betweens on canvases: keys drawn where they're placed, read and
## written as raw RGBA bytes, which is much faster than reading pixel by pixel. See
## [InBetween].


## [param img] drawn at [param position] on a transparent canvas covering [param rect]
static func draw(img: Image, position: Vector2i, rect: Rect2i) -> PackedByteArray:
	var canvas := Image.create_empty(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(rgba(img), Rect2i(Vector2i.ZERO, img.get_size()), position - rect.position)
	return canvas.get_data()


## [param img], or a copy of it in RGBA8 when it's in another format
static func rgba(img: Image) -> Image:
	if img.get_format() == Image.FORMAT_RGBA8:
		return img
	var copy := img.duplicate()
	copy.convert(Image.FORMAT_RGBA8)
	return copy


## 1 for each pixel of [param data] that isn't fully transparent, 0 for the others
static func mask(data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(data.size() / 4)
	for p in result.size():
		result[p] = 1 if data[p * 4 + 3] > 0 else 0
	return result


## Each pixel's colour as one number, 0 for transparent ones
static func colors(data: PackedByteArray) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(data.size() / 4)
	for p in result.size():
		var i := p * 4
		if data[i + 3] > 0:
			result[p] = data[i] << 24 | data[i + 1] << 16 | data[i + 2] << 8 | data[i + 3]
	return result


## How light each pixel is, from 0 to 1
static func lightness(data: PackedByteArray) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(data.size() / 4)
	for p in result.size():
		var i := p * 4
		result[p] = (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) / 255.0
	return result


## The index of the pixel at ([param x], [param y]) of a canvas [param width] ×
## [param height] pixels, or -1 outside it
static func index_at(x: int, y: int, width: int, height: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return y * width + x


## How far each pixel is from the nearest one whose [param mask_data] is [param value],
## in thirds of a pixel (3 straight, 4 diagonally), and which pixel that is, or -1 when
## none is: [code][distances, nearest][/code]
static func distances(
	mask_data: PackedByteArray, width: int, height: int, value: int
) -> Array[PackedInt32Array]:
	var count := width * height
	# Farther than any pixel, for when none is the value
	var none := (width + height) * 4
	var distance := PackedInt32Array()
	var nearest := PackedInt32Array()
	distance.resize(count)
	nearest.resize(count)
	for p in count:
		var is_value := mask_data[p] == value
		distance[p] = 0 if is_value else none
		nearest[p] = p if is_value else -1
	# Down from the top left, then up from the bottom right, each pixel taking what its
	# neighbours already passed found
	var forward: Array[Vector3i] = [
		Vector3i(-1, 0, 3), Vector3i(-1, -1, 4), Vector3i(0, -1, 3), Vector3i(1, -1, 4)
	]
	var backward: Array[Vector3i] = [
		Vector3i(1, 0, 3), Vector3i(1, 1, 4), Vector3i(0, 1, 3), Vector3i(-1, 1, 4)
	]
	for pass_index in 2:
		var neighbours := forward if pass_index == 0 else backward
		for row in height:
			var y := row if pass_index == 0 else height - 1 - row
			for column in width:
				var x := column if pass_index == 0 else width - 1 - column
				var p := y * width + x
				if distance[p] == 0:
					continue
				for neighbour in neighbours:
					var nx := x + neighbour.x
					var ny := y + neighbour.y
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var q := ny * width + nx
					if distance[q] + neighbour.z < distance[p]:
						distance[p] = distance[q] + neighbour.z
						nearest[p] = nearest[q]
	return [distance, nearest]


## A frame of the pixels of [param data] covering [param rect], cut to the ones shown and
## placed where they were: [code]{"image": Image, "origin": Vector2i}[/code]
static func cropped(data: PackedByteArray, rect: Rect2i) -> Dictionary:
	var img := Image.create_from_data(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8, data)
	var used := img.get_used_rect()
	if not used.has_area():
		var empty := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		return {"image": empty, "origin": rect.get_center()}
	return {"image": img.get_region(used), "origin": rect.position + used.position}


## A transparent canvas of [param count] pixels
static func blank(count: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(count * 4)
	data.fill(0)
	return data


## Where the pixels shown in a canvas [param width] × [param height] pixels with
## [param pixel_colors] (see [method colors]) are, grown by a pixel and kept a pixel off the
## canvas's edge, or an empty rectangle when none is
static func shown_area(pixel_colors: PackedInt32Array, width: int, height: int) -> Rect2i:
	var low := Vector2i(width, height)
	var high := Vector2i(-1, -1)
	for p in pixel_colors.size():
		if pixel_colors[p] != 0:
			var at := Vector2i(p % width, p / width)
			low = low.min(at)
			high = high.max(at)
	if high.x < 0:
		return Rect2i()
	var area := Rect2i(low - Vector2i.ONE, high - low + Vector2i(3, 3))
	return area.intersection(Rect2i(1, 1, width - 2, height - 2))
