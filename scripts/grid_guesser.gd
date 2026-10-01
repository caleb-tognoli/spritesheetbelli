class_name GridGuesser
## Guesses how many columns and rows a spritesheet image has.
##
## In order of confidence: a size in the file name ("hero_32x32.png", "walk_8x2.png",
## "run_strip6.png"), transparent gaps between sprites, cut lines crossing little of the
## sprites (for sprites that touch), square cells matching the other axis, the largest
## common sprite size that divides the image, and finally a single cell.

const COMMON_SIZES: Array[int] = [256, 128, 96, 64, 48, 32, 24, 16, 8]
## Common sizes giving more cells than this on an axis are too small to be a fair guess
const MAX_COMMON_CELLS := 64
## Numbers in a file name at least this big are sprite sizes in pixels, smaller ones are counts
const MIN_SIZE_IN_NAME := 12
const MAX_CELLS_PER_AXIS := 256
const MIN_CELL_SIZE := 8
## Pixels at most this opaque are ignored when the gaps aren't clear, like faint trails
## soft brushes leave between frames
const ALPHA_THRESHOLD := 0.05
## Groups of pixels narrower than this share of the typical sprite are specks, not sprites
const SPECK_SHARE := 0.1
## How far the distance between sprites may be from the typical one, as a share of it
const SPACING_TOLERANCE := 0.25
## Cut lines are clean when they cross at most this share of an average line's pixels
const CLEAN_CUT_SHARE := 0.4
## How far from square a cell guessed from the other axis may be
const SQUARE_TOLERANCE := 0.05


static func guess(img: Image, file_name := "") -> Vector2i:
	var size := img.get_size()
	if size.x <= 0 or size.y <= 0:
		return Vector2i.ONE

	var from_name := guess_from_file_name(file_name, size)
	if from_name != Vector2i.ZERO:
		return from_name

	var from_image := guess_from_image(img)
	if from_image != Vector2i.ZERO:
		return from_image

	for cell in COMMON_SIZES:
		var grid := size / cell
		if (
			size.x % cell == 0
			and size.y % cell == 0
			and grid != Vector2i.ONE
			and maxi(grid.x, grid.y) <= MAX_COMMON_CELLS
		):
			return grid
	return Vector2i.ONE


## Reads "32x32" (sprite size), "8x2" (columns and rows) or "strip8" from a file name.
## Returns ZERO when there is nothing usable.
static func guess_from_file_name(file_name: String, size: Vector2i) -> Vector2i:
	var name := file_name.get_file().get_basename().to_lower()
	var pair := _pair_in_name(name)
	if pair != Vector2i.ZERO:
		if pair.x <= 0 or pair.y <= 0:
			return Vector2i.ZERO
		# Leftover pixels are fine: slicing reports them
		if pair.x >= MIN_SIZE_IN_NAME and pair.y >= MIN_SIZE_IN_NAME:
			if size.x >= pair.x and size.y >= pair.y:
				return size / pair
		elif size.x >= pair.x and size.y >= pair.y:
			return pair
		return Vector2i.ZERO

	var strip := RegEx.create_from_string("strip\\s*(\\d+)").search(name)
	if strip:
		var count := int(strip.get_string(1))
		if count > 0 and size.x >= count:
			return Vector2i(count, 1)
	return Vector2i.ZERO


## The sprite size in a file name like "hero_32x32.png", when it fits in [param size].
## Returns ZERO when the name has no sprite size.
static func guess_cell_size_from_file_name(file_name: String, size: Vector2i) -> Vector2i:
	var pair := _pair_in_name(file_name.get_file().get_basename().to_lower())
	if pair.x < MIN_SIZE_IN_NAME or pair.y < MIN_SIZE_IN_NAME:
		return Vector2i.ZERO
	return pair if size.x >= pair.x and size.y >= pair.y else Vector2i.ZERO


## The numbers of "32x32" or "8x2" in [param name], or ZERO when there are none
static func _pair_in_name(name: String) -> Vector2i:
	var found := RegEx.create_from_string("(\\d+)\\s*[x×]\\s*(\\d+)").search(name)
	if found == null:
		return Vector2i.ZERO
	return Vector2i(int(found.get_string(1)), int(found.get_string(2)))


## Guesses the grid from where the sprites are. Returns ZERO when the image tells
## nothing, like one without transparency.
static func guess_from_image(img: Image) -> Vector2i:
	if img.detect_alpha() == Image.ALPHA_NONE:
		return Vector2i.ZERO

	# Sprites apart from each other, told quickly by lines without a visible pixel
	var grid := Vector2i(
		_count_from_gaps(_visible_lines(img, true)), _count_from_gaps(_visible_lines(img, false))
	)
	if grid.x > 0 and grid.y > 0 and grid != Vector2i.ONE:
		return grid

	# Counting the pixels of every line takes longer, but ignores faint ones and tells how
	# much cut lines cross
	var mask := BitMap.new()
	mask.create_from_image_alpha(img, ALPHA_THRESHOLD)
	var pixels := mask.convert_to_image()
	var columns := _used_per_line(pixels, true)
	var rows := _used_per_line(pixels, false)
	grid = Vector2i(_count_from_gaps(columns), _count_from_gaps(rows))
	if grid.x > 0 and grid.y > 0 and grid != Vector2i.ONE:
		return grid

	# Sprites touching each other, or apart unevenly
	var each_one := grid == Vector2i.ONE
	if grid.x == 0 or each_one:
		grid.x = _count_from_cuts(columns)
	if grid.y == 0 or each_one:
		grid.y = _count_from_cuts(rows)
	if each_one:
		if grid != Vector2i.ZERO:
			# An axis without cut lines has one cell
			return grid.maxi(1)
		# A single sprite, unless it fills the image: then nothing tells where cells are
		var opaque := Array(rows).all(func(used: int) -> bool: return used == img.get_width())
		return Vector2i.ZERO if opaque else Vector2i.ONE

	# Square cells, from the axis that is known
	if grid.x == 0 and grid.y > 0:
		grid.x = _count_from_cell(img.get_width(), float(img.get_height()) / grid.y)
	elif grid.y == 0 and grid.x > 0:
		grid.y = _count_from_cell(img.get_height(), float(img.get_width()) / grid.x)
	if grid == Vector2i.ZERO:
		return Vector2i.ZERO
	return grid.maxi(1)


## 1 for every column or row of [param img] with a visible pixel, 0 for the others
static func _visible_lines(img: Image, columns: bool) -> PackedInt32Array:
	var visible := PackedInt32Array()
	visible.resize(img.get_width() if columns else img.get_height())
	for i in visible.size():
		var line := (
			Rect2i(i, 0, 1, img.get_height()) if columns else Rect2i(0, i, img.get_width(), 1)
		)
		visible[i] = 0 if img.get_region(line).is_invisible() else 1
	return visible


## How many pixels of every column or row of [param mask] are used
static func _used_per_line(mask: Image, columns: bool) -> PackedInt32Array:
	var used := PackedInt32Array()
	if columns:
		used.resize(mask.get_width())
		for x in used.size():
			var column := mask.get_region(Rect2i(x, 0, 1, mask.get_height())).get_data()
			used[x] = column.size() - column.count(0)
	else:
		# Rows lie one after the other in the data: no need to copy them out of the image
		var width := mask.get_width()
		var data := mask.get_data()
		used.resize(mask.get_height())
		for y in used.size():
			used[y] = width - data.slice(y * width, (y + 1) * width).count(0)
	return used


## Counts evenly spaced groups of used lines, some of which may be missing. Returns 0 if
## they aren't evenly spaced.
static func _count_from_gaps(used: PackedInt32Array) -> int:
	var runs: Array[Vector2i] = []  # (start, end) of each group of used lines
	var run_start := -1
	for i in used.size():
		if used[i] > 0 and run_start < 0:
			run_start = i
		elif used[i] == 0 and run_start >= 0:
			runs.append(Vector2i(run_start, i))
			run_start = -1
	if run_start >= 0:
		runs.append(Vector2i(run_start, used.size()))

	if runs.size() > 1:
		var widths: Array[int] = []
		for run in runs:
			widths.append(run.y - run.x)
		widths.sort()
		var speck := widths[widths.size() / 2] * SPECK_SHARE
		var sprites: Array[Vector2i] = []
		for run in runs:
			if run.y - run.x >= speck:
				sprites.append(run)
		runs = sprites
	if runs.size() <= 1:
		return runs.size()
	if runs.size() > MAX_CELLS_PER_AXIS:
		return 0

	# Sprites are evenly spaced when the distances between their centres are multiples of
	# one, more than one where frames are missing
	var spacings: Array[float] = []
	for i in runs.size() - 1:
		spacings.append((runs[i + 1].x + runs[i + 1].y - runs[i].x - runs[i].y) / 2.0)
	var sorted := spacings.duplicate()
	sorted.sort()
	var period: float = sorted[sorted.size() / 2]
	var steps := 0
	for spacing in spacings:
		var step := roundi(spacing / period)
		if step < 1 or absf(spacing - step * period) > period * SPACING_TOLERANCE:
			return 0
		steps += step
	period = (runs[-1].x + runs[-1].y - runs[0].x - runs[0].y) / 2.0 / steps
	return clampi(roundi(used.size() / period), 1, MAX_CELLS_PER_AXIS)


## The most cells an axis splits into evenly with cut lines crossing little of the sprites
## and sprites in every cell. Returns 0 when there are none.
static func _count_from_cuts(used: PackedInt32Array) -> int:
	var length := used.size()
	var before := PackedInt32Array()  # Used pixels before each line, to tell empty cells
	before.resize(length + 1)
	for i in length:
		before[i + 1] = before[i] + used[i]
	if before[length] == 0:
		return 0
	var average := float(before[length]) / length

	var best := 0
	for count in range(2, mini(MAX_CELLS_PER_AXIS, length / MIN_CELL_SIZE) + 1):
		if length % count != 0:
			continue
		var cell := length / count
		var crossed := 0
		var empty_cell := before[cell] == 0
		for i in range(1, count):
			# Sprites touching on the cut use the lines on both of its sides
			crossed += mini(used[i * cell - 1], used[i * cell])
			empty_cell = empty_cell or before[(i + 1) * cell] == before[i * cell]
		if not empty_cell and crossed <= average * CLEAN_CUT_SHARE * (count - 1):
			best = count
	return best


## How many square cells of [param cell] pixels fit evenly in [param length], or 0
static func _count_from_cell(length: int, cell: float) -> int:
	var count := maxi(1, roundi(length / cell))
	if length % count != 0 or absf(float(length) / count - cell) > cell * SQUARE_TOLERANCE:
		return 0
	return count
