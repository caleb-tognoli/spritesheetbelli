class_name GridGuesser
## Guesses how many columns and rows a spritesheet image has.
##
## In order of confidence: a size in the file name ("hero_32x32.png", "walk_8x2.png",
## "run_strip6.png"), transparent gaps between sprites, the largest common sprite size
## that divides the image, and finally a single cell.

const COMMON_SIZES: Array[int] = [256, 128, 96, 64, 48, 32, 24, 16, 8]
## Numbers in a file name at least this big are sprite sizes in pixels, smaller ones are counts
const MIN_SIZE_IN_NAME := 12
const MAX_CELLS_PER_AXIS := 256


static func guess(img: Image, file_name := "") -> Vector2i:
	var size := img.get_size()
	if size.x <= 0 or size.y <= 0:
		return Vector2i.ONE

	var from_name := guess_from_file_name(file_name, size)
	if from_name != Vector2i.ZERO:
		return from_name

	var from_gaps := guess_from_gaps(img)
	if from_gaps != Vector2i.ZERO:
		return from_gaps

	for cell in COMMON_SIZES:
		if size.x % cell == 0 and size.y % cell == 0 and size != Vector2i(cell, cell):
			return size / cell
	return Vector2i.ONE


## Reads "32x32" (sprite size), "8x2" (columns and rows) or "strip8" from a file name.
## Returns ZERO when there is nothing usable.
static func guess_from_file_name(file_name: String, size: Vector2i) -> Vector2i:
	var name := file_name.get_file().get_basename().to_lower()
	var regex := RegEx.create_from_string("(\\d+)\\s*[x×]\\s*(\\d+)")
	var found := regex.search(name)
	if found:
		var a := int(found.get_string(1))
		var b := int(found.get_string(2))
		if a <= 0 or b <= 0:
			return Vector2i.ZERO
		# Leftover pixels are fine: slicing reports them
		if a >= MIN_SIZE_IN_NAME and b >= MIN_SIZE_IN_NAME:
			if size.x >= a and size.y >= b:
				return Vector2i(size.x / a, size.y / b)
		elif size.x >= a and size.y >= b:
			return Vector2i(a, b)
		return Vector2i.ZERO

	var strip := RegEx.create_from_string("strip\\s*(\\d+)").search(name)
	if strip:
		var count := int(strip.get_string(1))
		if count > 0 and size.x >= count:
			return Vector2i(count, 1)
	return Vector2i.ZERO


## Finds sprites separated by fully transparent columns and rows. Returns ZERO if the
## sprites aren't evenly spaced.
static func guess_from_gaps(img: Image) -> Vector2i:
	var columns := _count_along(img, true)
	var rows := _count_along(img, false)
	if columns <= 0 or rows <= 0 or (columns == 1 and rows == 1):
		return Vector2i.ZERO
	return Vector2i(columns, rows)


## Counts evenly spaced groups of non-transparent pixels along one axis
static func _count_along(img: Image, horizontal: bool) -> int:
	var length := img.get_width() if horizontal else img.get_height()
	var runs: Array[Vector2i] = []  # (start, end) of each group of used lines
	var run_start := -1
	for i in length:
		var line := (
			Rect2i(i, 0, 1, img.get_height()) if horizontal else Rect2i(0, i, img.get_width(), 1)
		)
		var used := not img.get_region(line).is_invisible()
		if used and run_start < 0:
			run_start = i
		elif not used and run_start >= 0:
			runs.append(Vector2i(run_start, i))
			run_start = -1
	if run_start >= 0:
		runs.append(Vector2i(run_start, length))

	if runs.size() <= 1:
		return runs.size()
	if runs.size() > MAX_CELLS_PER_AXIS:
		return 0

	# Sprites are evenly spaced when the distance between their centres is constant
	var spacings: Array[float] = []
	for i in runs.size() - 1:
		spacings.append((runs[i + 1].x + runs[i + 1].y - runs[i].x - runs[i].y) / 2.0)
	spacings.sort()
	var period := spacings[spacings.size() / 2]
	for spacing in spacings:
		if absf(spacing - period) > period * 0.25:
			return 0
	return maxi(0, roundi(length / period))
