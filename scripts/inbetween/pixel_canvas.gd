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
## none is: [code][distances, nearest][/code]. Where none is, the distance is
## [param far], or farther than any pixel of the canvas when 0.
##
## A part of a bigger canvas (see [method region]) gives the same as the whole canvas
## there, given the same [param far], when every pixel of the value is in it, and for value
## 0, it has a pixel of the value all round.
static func distances(
	mask_data: PackedByteArray, width: int, height: int, value: int, far := 0
) -> Array[PackedInt32Array]:
	if NativeKernels.kernels:
		return NativeKernels.distances(mask_data, width, height, value, far)
	var count := width * height
	# Farther than any pixel, for when none is the value
	var none := far if far > 0 else (width + height) * 4
	var distance := PackedInt32Array()
	var nearest := PackedInt32Array()
	distance.resize(count)
	nearest.resize(count)
	distance.fill(none)
	nearest.fill(-1)
	var p := mask_data.find(value)
	while p >= 0:
		distance[p] = 0
		nearest[p] = p
		p = mask_data.find(value, p + 1)
	# Down from the top left, then up from the bottom right, each pixel taking what its
	# neighbours already passed found: going down, those left, up left, up and up right;
	# going up, those right, down right, down and down left, in that order, a nearer one
	# found later winning
	var last_column := width - 1
	for y in height:
		var row := y * width
		for x in width:
			p = row + x
			var d := distance[p]
			if d == 0:
				continue
			var n := nearest[p]
			var q := p - 1
			if x > 0 and distance[q] + 3 < d:
				d = distance[q] + 3
				n = nearest[q]
			if y > 0:
				q = p - width
				if x > 0 and distance[q - 1] + 4 < d:
					d = distance[q - 1] + 4
					n = nearest[q - 1]
				if distance[q] + 3 < d:
					d = distance[q] + 3
					n = nearest[q]
				if x < last_column and distance[q + 1] + 4 < d:
					d = distance[q + 1] + 4
					n = nearest[q + 1]
			distance[p] = d
			nearest[p] = n
	var last_row := height - 1
	for y in range(last_row, -1, -1):
		var row := y * width
		for x in range(last_column, -1, -1):
			p = row + x
			var d := distance[p]
			if d == 0:
				continue
			var n := nearest[p]
			var q := p + 1
			if x < last_column and distance[q] + 3 < d:
				d = distance[q] + 3
				n = nearest[q]
			if y < last_row:
				q = p + width
				if x < last_column and distance[q + 1] + 4 < d:
					d = distance[q + 1] + 4
					n = nearest[q + 1]
				if distance[q] + 3 < d:
					d = distance[q] + 3
					n = nearest[q]
				if x > 0 and distance[q - 1] + 4 < d:
					d = distance[q - 1] + 4
					n = nearest[q - 1]
			distance[p] = d
			nearest[p] = n
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


## The pixels of [param data], a canvas [param width] pixels wide, covering [param area]
static func region(data: PackedByteArray, width: int, area: Rect2i) -> PackedByteArray:
	var height := data.size() / 4 / width
	var img := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	return img.get_region(area).get_data()


## [param data], the pixels covering [param area], put back on a transparent canvas
## [param width] × [param height] pixels
static func placed(data: PackedByteArray, area: Rect2i, width: int, height: int) -> PackedByteArray:
	var canvas := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var part := Image.create_from_data(area.size.x, area.size.y, false, Image.FORMAT_RGBA8, data)
	canvas.blit_rect(part, Rect2i(Vector2i.ZERO, area.size), area.position)
	return canvas.get_data()


## Where the pixels shown (not fully transparent) in [param data], a canvas [param width]
## × [param height] pixels, are, grown by [param margin] and kept on the canvas; empty
## when none is
static func shown_rect(data: PackedByteArray, width: int, height: int, margin: int) -> Rect2i:
	var img := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	var used := img.get_used_rect()
	if not used.has_area():
		return Rect2i()
	return used.grow(margin).intersection(Rect2i(0, 0, width, height))


## Where the pixels shown in [param first] or [param second] are (see [method shown_rect]);
## a pixel of the canvas when neither shows any
static func shown_rect_of(
	first: PackedByteArray, second: PackedByteArray, width: int, height: int, margin: int
) -> Rect2i:
	var area := shown_rect(first, width, height, margin)
	var other := shown_rect(second, width, height, margin)
	if not area.has_area():
		area = other
	elif other.has_area():
		area = area.merge(other)
	return area if area.has_area() else Rect2i(0, 0, 1, 1)


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
