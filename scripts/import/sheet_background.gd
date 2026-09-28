class_name SheetBackground
## Finds the background of spritesheets drawn on a solid colour, like magenta, instead of
## on transparency, so it can be made transparent before the sheet is cut.
##
## A sheet has one when it has no (or almost no) transparency and most of its border is
## one colour, which isn't the whole image. The whole border decides, not only the
## corners: agreeing corners with other colours along the edges are art that fills the
## image, like a tileset or a scene whose sky reaches every corner, and keying their colour
## would cut holes in it. The other way round, a sprite over one corner doesn't hide a
## background the rest of the border shows.

## At most this share of the pixels can be see-through
const MAX_TRANSPARENT := 0.01
## At least this share of the border has the background colour
const MIN_BORDER_SHARE := 0.8
## Border pixels this close to the most common colour count as it, e.g. after compression
const BORDER_TOLERANCE := 0.02
## How close pixels must be to the background colour to be removed, unless told otherwise
const DEFAULT_TOLERANCE := 0.1


## The background colour of [param img], opaque, or null when it doesn't have one
static func detect(img: Image) -> Variant:
	var size := img.get_size()
	if size.x < 2 or size.y < 2 or not _is_opaque(img):
		return null
	var border := _get_border(img)
	# How many border pixels have each colour
	var counts: Dictionary[int, int] = {}
	for color in border:
		var rgba := color.to_rgba32()
		counts[rgba] = counts.get(rgba, 0) + 1
	var common := 0
	var most := 0
	for rgba in counts:
		if counts[rgba] > most:
			common = rgba
			most = counts[rgba]
	var background := Color.hex(common)
	if background.a < 1.0:
		return null
	var matching := 0
	for rgba in counts:
		if is_close(Color.hex(rgba), background, BORDER_TOLERANCE):
			matching += counts[rgba]
	if matching < border.size() * MIN_BORDER_SHARE or _is_all(img, background):
		return null
	return background


## A copy of [param img] with the pixels close to [param color] made transparent, see
## [method ImageUtils.color_key]
static func remove(img: Image, color: Color, tolerance := DEFAULT_TOLERANCE) -> Image:
	var copy := img.duplicate() as Image
	ImageUtils.color_key(copy, color, tolerance)
	return copy


## Whether [param a] is close enough to [param b] to be keyed with [param tolerance], the
## same way [method ImageUtils.color_key] measures it
static func is_close(a: Color, b: Color, tolerance: float) -> bool:
	var dr := a.r8 - b.r8
	var dg := a.g8 - b.g8
	var db := a.b8 - b.b8
	return dr * dr + dg * dg + db * db <= (tolerance * 255.0) ** 2 * 3.0


## Whether (almost) every pixel of [param img] is opaque
static func _is_opaque(img: Image) -> bool:
	if img.detect_alpha() == Image.ALPHA_NONE:
		return true
	var opaque := BitMap.new()
	opaque.create_from_image_alpha(img, 0.99)
	var total := img.get_width() * img.get_height()
	return total - opaque.get_true_bit_count() <= total * MAX_TRANSPARENT


## Whether every pixel of [param img] is [param color]: an image of one colour is a sprite
## of its own, not a background without sprites
static func _is_all(img: Image, color: Color) -> bool:
	var pixels := img
	if img.get_format() != Image.FORMAT_RGBA8:
		pixels = img.duplicate() as Image
		pixels.convert(Image.FORMAT_RGBA8)
	var filled := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	filled.fill(color)
	return pixels.get_data() == filled.get_data()


## The pixels around the edge of [param img], each once
static func _get_border(img: Image) -> PackedColorArray:
	var last := img.get_size() - Vector2i.ONE
	var colors := PackedColorArray()
	for x in last.x + 1:
		colors.append(img.get_pixel(x, 0))
		colors.append(img.get_pixel(x, last.y))
	for y in range(1, last.y):
		colors.append(img.get_pixel(0, y))
		colors.append(img.get_pixel(last.x, y))
	return colors
