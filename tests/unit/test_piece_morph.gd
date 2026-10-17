extends "res://tests/test_case.gd"
## In-betweens made of pieces (PieceMorph): pieces found and followed, turned about their
## joints, squashed and stretched, drawn without new colours

const SKIN := Color("f2c094")
const SHIRT := Color("3b6fd1")
const LEGS := Color("2b2b40")
const STEEL := Color("d0d8e0")
const GOLD := Color("f1c40f")
const OUTLINE := Color("1d1b2a")


static func key(img: Image, origin := Vector2i.ZERO) -> Dictionary:
	return {"image": img, "origin": origin}


static func blank(size := Vector2i(32, 32)) -> Image:
	return Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)


## A line [param thickness] pixels thick from [param from] to [param to]
static func line(img: Image, from: Vector2, to: Vector2, color: Color, thickness := 2) -> void:
	var steps := int(from.distance_to(to) * 2) + 1
	for i in steps + 1:
		var at := from.lerp(to, float(i) / steps)
		var corner := Vector2i(at.round()) - Vector2i.ONE * (thickness / 2)
		img.fill_rect(Rect2i(corner, Vector2i.ONE * thickness), color)


## The colour [param frame] shows where [param position] is placed
static func pixel_at(frame: Dictionary, position: Vector2i) -> Color:
	var img: Image = frame.image
	var local: Vector2i = position - frame.origin
	if not Rect2i(Vector2i.ZERO, img.get_size()).has_point(local):
		return Color(0, 0, 0, 0)
	return img.get_pixelv(local)


## The colours shown in [param img]
static func colors_in(img: Image) -> Dictionary:
	var colors := {}
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if color.a > 0:
				colors[color.to_html()] = true
	return colors


## Where [param frame] shows [param color], placed
static func where(frame: Dictionary, color: Color) -> Rect2i:
	var img: Image = frame.image
	var found := Rect2i()
	var any := false
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(color):
				var at := Rect2i(frame.origin + Vector2i(x, y), Vector2i.ONE)
				found = at if not any else found.merge(at)
				any = true
	return found


## A figure with a body, a head, legs and two arms; the right arm is raised by
## [param raised] pixels
static func figure(raised: int) -> Image:
	var img := blank()
	img.fill_rect(Rect2i(13, 4, 6, 6), SKIN)
	img.fill_rect(Rect2i(12, 10, 8, 10), SHIRT)
	img.fill_rect(Rect2i(13, 20, 2, 8), LEGS)
	img.fill_rect(Rect2i(17, 20, 2, 8), LEGS)
	img.fill_rect(Rect2i(10, 11, 2, 7), SKIN)
	img.fill_rect(Rect2i(20, 11 - raised, 2, 7), SKIN)
	return img


## A sword held in a hand, its blade turned [param angle] from pointing up
static func sword(angle: float) -> Image:
	var img := blank()
	var hand := Vector2(10, 22)
	var direction := Vector2.UP.rotated(angle)
	var across := direction.orthogonal()
	line(img, hand + direction * 4 + across * 3, hand + direction * 4 - across * 3, GOLD, 1)
	line(img, hand + direction * 5, hand + direction * 17, STEEL)
	img.fill_rect(Rect2i(Vector2i(hand) - Vector2i(2, 2), Vector2i(4, 4)), SKIN)
	return img


func test_identical_keys_give_themselves() -> void:
	var img := figure(0)
	var frames := InBetween.generate(key(img), key(img), 3)
	for frame in frames:
		for y in 32:
			for x in 32:
				assert_eq(pixel_at(frame, Vector2i(x, y)), img.get_pixel(x, y))


func test_an_arm_moves_on_its_own() -> void:
	var frame := InBetween.generate(key(figure(0)), key(figure(8)), 1)[0]
	assert_eq(where(frame, SHIRT), Rect2i(12, 10, 8, 10), "the body stays")
	assert_eq(where(frame, LEGS), Rect2i(13, 20, 6, 8), "the legs too")
	var arm := pixel_at(frame, Vector2i(20, 7))
	assert_eq(arm, SKIN, "the arm halfway up")
	assert_eq(pixel_at(frame, Vector2i(20, 16)).a, 0.0, "not left behind")
	assert_eq(pixel_at(frame, Vector2i(20, 3)).a, 0.0, "nor ahead")
	assert_eq(pixel_at(frame, Vector2i(10, 12)), SKIN, "the other arm stays")


func test_a_blade_swings_round_the_hand() -> void:
	var frames := InBetween.generate(key(sword(0.0)), key(sword(PI / 2)), 1)
	var frame := frames[0]
	assert_eq(where(frame, SKIN), Rect2i(8, 20, 4, 4), "the hand stays")
	var hand := Vector2(10, 22)
	var steel := where(frame, STEEL)
	assert_true(steel.has_area())
	# The tip, a quarter turn round from up to the right: up and to the right of the hand
	var tip := hand + Vector2.UP.rotated(PI / 4) * 16
	assert_true(
		Rect2(steel).grow(1.0).has_point(tip), "the blade swung halfway: %s %s" % [steel, tip]
	)
	assert_eq(pixel_at(frame, Vector2i(10, 8)).a, 0.0, "not still pointing up")
	assert_eq(pixel_at(frame, Vector2i(24, 22)).a, 0.0, "nor right already")


func test_squash_and_stretch() -> void:
	var wide := blank(Vector2i(40, 32))
	var tall := blank(Vector2i(40, 32))
	for y in 32:
		for x in 40:
			var at := Vector2(x + 0.5, y + 0.5) - Vector2(20, 16)
			if (at / Vector2(12, 4)).length() <= 1.0:
				wide.set_pixel(x, y, Color.SEA_GREEN)
			if (at / Vector2(4, 12)).length() <= 1.0:
				tall.set_pixel(x, y, Color.SEA_GREEN)
	var frame := InBetween.generate(key(wide), key(tall), 1)[0]
	var shape := (frame.image as Image).get_used_rect().size
	assert_true(shape.x >= 12 and shape.x <= 20, "narrower than the wide one" + ": %s" % [shape.x])
	assert_true(shape.y >= 12 and shape.y <= 20, "shorter than the tall one" + ": %s" % [shape.y])


func test_moving_keeps_the_pixels_and_colours() -> void:
	var a := figure(0)
	var frames := InBetween.generate(key(a), key(a, Vector2i(10, -4)), 1)
	assert_eq(frames[0].origin, Vector2i(10, 4) + Vector2i(5, -2), "the sprite halfway")
	var img: Image = frames[0].image
	var used := a.get_region(a.get_used_rect())
	assert_eq(img.get_data(), used.get_data(), "pixel for pixel")


func test_pieces_landing_well_are_not_bent() -> void:
	var morph := InBetween.prepare(key(figure(0)), key(figure(8)))
	assert_true(morph.meshes.is_empty(), "the arm just moves")


func test_shapes_the_pieces_dont_fit_are_bent() -> void:
	var wide := blank(Vector2i(40, 32))
	var tall := blank(Vector2i(40, 32))
	for y in 32:
		for x in 40:
			var at := Vector2(x + 0.5, y + 0.5) - Vector2(20, 16)
			if (at / Vector2(14, 3)).length() <= 1.0:
				wide.set_pixel(x, y, Color.SEA_GREEN)
			if (at / Vector2(5, 13)).length() <= 1.0:
				tall.set_pixel(x, y, Color.SEA_GREEN)
	var morph := InBetween.prepare(key(wide), key(tall))
	assert_eq(morph.meshes.size(), 2, "both keys cut into triangles")
	var mesh: KeyMesh = morph.meshes[0]
	assert_eq(mesh.at(0.0), mesh.rest, "as drawn at the start")
	assert_eq(mesh.at(1.0), mesh.target, "laid on the other key at the end")
	# Laid onto the tall one, and halfway there in between
	var heights := []
	for corners: PackedVector2Array in [mesh.rest, mesh.at(0.5), mesh.target]:
		var low := INF
		var high := -INF
		for corner: Vector2 in corners:
			low = minf(low, corner.y)
			high = maxf(high, corner.y)
		heights.append(high - low)
	assert_true(heights[2] > 20.0, "as tall as the other key: %s" % [heights])
	assert_true(heights[0] < heights[1] and heights[1] < heights[2], "growing: %s" % [heights])


func test_no_new_colours() -> void:
	var frames := InBetween.generate(key(sword(0.0)), key(sword(PI / 2)), 3)
	var allowed := colors_in(sword(0.0))
	for frame in frames:
		for color: String in colors_in(frame.image):
			assert_true(allowed.has(color), "%s comes from a key" % color)


func test_an_outline_is_drawn_round_each_frame() -> void:
	var outlined := func(raised: int) -> Image:
		var drawn := figure(raised)
		var out := drawn.duplicate()
		for y in 32:
			for x in 32:
				if drawn.get_pixel(x, y).a > 0:
					continue
				for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var at := Vector2i(x, y) + side
					if Rect2i(0, 0, 32, 32).has_point(at) and drawn.get_pixelv(at).a > 0:
						out.set_pixel(x, y, OUTLINE)
						break
		return out
	var a: Image = outlined.call(0)
	var frame := InBetween.generate(key(a), key(outlined.call(8)), 1)[0]
	var morph := InBetween.prepare(key(a), key(outlined.call(8)))
	assert_ne(morph.outline, null, "found in both keys")
	var img: Image = frame.image
	# Every pixel at the edge of what's shown is the outline's
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a == 0:
				continue
			var edge := x == 0 or y == 0 or x == img.get_width() - 1 or y == img.get_height() - 1
			for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var at := Vector2i(x, y) + side
				if not edge and img.get_pixelv(at).a == 0:
					edge = true
			if edge:
				assert_eq(img.get_pixel(x, y), OUTLINE, "outlined at %s" % Vector2i(x, y))


func test_working_it_out_can_be_cancelled() -> void:
	var a := key(figure(0))
	var b := key(figure(8))
	var progress := WorkProgress.new()
	assert_ne(InBetween.prepare(a, b, Vector2i.ZERO, progress), null)
	assert_true(progress.total > 0)
	assert_eq(progress.get_ratio(), 1.0, "all done")
	var cancelled := WorkProgress.new()
	cancelled.cancelled = true
	assert_eq(InBetween.prepare(a, b, Vector2i.ZERO, cancelled), null)


func test_an_empty_key() -> void:
	var frames := InBetween.generate(key(blank()), key(figure(0)), 3)
	assert_eq(frames.size(), 3)
	assert_eq((frames[0].image as Image).get_used_rect().size, Vector2i.ZERO, "nothing yet")
	assert_eq(pixel_at(frames[2], Vector2i(15, 15)), SHIRT, "the other key, near it")


func test_painted_keys_keep_their_colours() -> void:
	# A shaded ball with many colours, moving
	var ball := func(at: Vector2) -> Image:
		var img := blank(Vector2i(48, 32))
		for y in 32:
			for x in 48:
				var offset := Vector2(x + 0.5, y + 0.5) - at
				if offset.length() <= 9.0:
					var light := clampf(1.0 - (offset - Vector2(-3, -3)).length() / 14.0, 0.0, 1.0)
					img.set_pixel(x, y, Color(0.2, 0.4, 0.9).lerp(Color(0.8, 0.9, 1.0), light))
		return img
	var a: Image = ball.call(Vector2(12, 16))
	var b: Image = ball.call(Vector2(34, 14))
	var frame := InBetween.generate(key(a), key(b), 1)[0]
	var allowed := colors_in(a)
	allowed.merge(colors_in(b))
	for color: String in colors_in(frame.image):
		assert_true(allowed.has(color), "%s comes from a key" % color)
	var used := (frame.image as Image).get_used_rect()
	assert_true(
		used.size.x >= 17 and used.size.x <= 20, "whole, not torn apart" + ": %s" % [used.size.x]
	)
	assert_true(
		(
			frame.origin.x + used.position.x + used.size.x / 2 >= 21
			and frame.origin.x + used.position.x + used.size.x / 2 <= 25
		),
		"halfway across" + ": %s" % [frame.origin.x + used.position.x + used.size.x / 2]
	)


func test_keys_that_dont_match_up_hold() -> void:
	# A figure turning into something else altogether, a big ring
	var ring := blank(Vector2i(48, 48))
	for y in 48:
		for x in 48:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(24, 24))
			if d > 12 and d < 22:
				ring.set_pixel(x, y, Color.ORANGE_RED if x < 24 else Color.MEDIUM_PURPLE)
	var a := figure(0)
	var frames := InBetween.generate(key(a), key(ring, Vector2i(-8, -8)), 3)
	for i in 2:
		var img: Image = frames[i].image
		for color: String in colors_in(img):
			assert_true(colors_in(a).has(color), "the first key until halfway")
	for color: String in colors_in(frames[2].image):
		assert_true(colors_in(ring).has(color), "then the second")


func test_faint_pixels_go_with_their_piece() -> void:
	var glowing := func(at: Vector2i) -> Image:
		var img := blank(Vector2i(48, 32))
		img.fill_rect(Rect2i(at - Vector2i(5, 5), Vector2i(10, 10)), Color(1, 1, 1, 0.25))
		img.fill_rect(Rect2i(at - Vector2i(3, 3), Vector2i(6, 6)), Color.GOLD)
		return img
	var frame := (
		InBetween
		. generate(key(glowing.call(Vector2i(10, 16))), key(glowing.call(Vector2i(30, 16))), 1)[0]
	)
	assert_eq(pixel_at(frame, Vector2i(20, 16)), Color.GOLD, "halfway")
	var glow: Image = glowing.call(Vector2i(10, 16))
	assert_eq(pixel_at(frame, Vector2i(16, 12)), glow.get_pixel(6, 12), "with its glow")
	assert_eq(pixel_at(frame, Vector2i(10, 16)).a, 0.0, "nothing left behind")


func test_an_arm_of_the_body_colour_moves_on_its_own() -> void:
	var waving := func(angle: float) -> Image:
		var img := blank()
		img.fill_rect(Rect2i(13, 4, 6, 6), SKIN)
		img.fill_rect(Rect2i(12, 10, 8, 10), SHIRT)
		img.fill_rect(Rect2i(13, 20, 2, 8), LEGS)
		img.fill_rect(Rect2i(17, 20, 2, 8), LEGS)
		img.fill_rect(Rect2i(10, 11, 2, 7), SHIRT)
		line(img, Vector2(21, 11), Vector2(21, 11) + Vector2(0, 7).rotated(-angle), SHIRT)
		return img
	var frame := InBetween.generate(key(waving.call(0.0)), key(waving.call(2.4)), 1)[0]
	assert_eq(pixel_at(frame, Vector2i(21, 17)).a, 0.0, "not hanging down any more")
	assert_eq(where(frame, SHIRT).end.x > 22, true, "but out from the body")
	assert_eq(where(frame, LEGS), Rect2i(13, 20, 6, 8), "the legs stay")


func test_stretched_shapes_stay_smooth() -> void:
	var wide := blank(Vector2i(40, 32))
	var tall := blank(Vector2i(40, 32))
	for y in 32:
		for x in 40:
			var at := Vector2(x + 0.5, y + 0.5) - Vector2(20, 16)
			if (at / Vector2(14, 3)).length() <= 1.0:
				wide.set_pixel(x, y, Color.SEA_GREEN)
			if (at / Vector2(5, 13)).length() <= 1.0:
				tall.set_pixel(x, y, Color.SEA_GREEN)
	for frame in InBetween.generate(key(wide), key(tall), 3):
		var img: Image = frame.image
		# Round: across and down, one run each, growing then shrinking (give or take a pixel,
		# as it may turn on its way, and a slanted outline steps)
		for across: bool in [true, false]:
			var lines := img.get_height() if across else img.get_width()
			var length := img.get_width() if across else img.get_height()
			var runs := PackedInt32Array()
			for row in lines:
				var starts := 0
				var count := 0
				var was := false
				for k in length:
					var shown := (
						(img.get_pixel(k, row) if across else img.get_pixel(row, k)).a > 0
					)
					if shown and not was:
						starts += 1
					if shown:
						count += 1
					was = shown
				assert_true(starts <= 1, "one run")
				if count > 0:
					runs.append(count)
			var widest := 0
			for k in runs.size():
				if runs[k] > runs[widest]:
					widest = k
			for k in range(1, runs.size()):
				if k <= widest:
					assert_true(runs[k] >= runs[k - 1] - 1, "growing: %s" % runs)
				else:
					assert_true(runs[k] <= runs[k - 1] + 1, "shrinking: %s" % runs)


func test_a_round_outlined_shape_moved_keeps_its_outline() -> void:
	# A ball whose outline goes round its corners as an artist would draw it, neither
	# only round its sides nor all round its corners
	var ball := blank()
	for y in 32:
		for x in 32:
			var apart := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(10, 10))
			if apart <= 4.0:
				ball.set_pixel(x, y, Color.CORAL)
			elif apart <= 5.2:
				ball.set_pixel(x, y, OUTLINE)
	var frames := InBetween.generate(key(ball), key(ball, Vector2i(12, 8)), 3)
	var used := ball.get_region(ball.get_used_rect())
	for frame in frames:
		assert_eq((frame.image as Image).get_data(), used.get_data(), "pixel for pixel")


func test_soft_edged_keys_are_followed_pixel_by_pixel() -> void:
	# A painted blob with a soft edge, shaded, moving and leaning
	var blob := func(at: Vector2, lean: float) -> Image:
		var img := blank(Vector2i(48, 40))
		for y in 40:
			for x in 48:
				var offset := Vector2(x + 0.5, y + 0.5) - at
				offset.x -= offset.y * lean
				var reach := Vector2(offset.x / 7.0, offset.y / 11.0).length()
				if reach <= 1.1:
					var light := clampf(1.0 - (offset - Vector2(-2, -4)).length() / 14.0, 0.0, 1.0)
					var color := Color(0.8, 0.2, 0.2).lerp(Color(1.0, 0.8, 0.6), light)
					color.a = clampf((1.1 - reach) * 6.0, 0.0, 1.0)
					img.set_pixel(x, y, color)
		return img
	var a: Image = blob.call(Vector2(14, 20), 0.0)
	var b: Image = blob.call(Vector2(30, 18), 0.4)
	assert_true(FlowMorph.soft(a, b), "soft-edged")
	assert_false(FlowMorph.soft(figure(0), figure(8)), "pixel art")
	var prepared := InBetween.prepare(key(a), key(b))
	assert_ne(prepared.flow, null, "followed pixel by pixel")
	var frame := prepared.frame(0.5)
	var allowed := colors_in(a)
	allowed.merge(colors_in(b))
	for color: String in colors_in(frame.image):
		assert_true(allowed.has(color), "%s comes from a key" % color)
	var used := (frame.image as Image).get_used_rect()
	var middle: int = frame.origin.x + used.position.x + used.size.x / 2
	assert_true(middle >= 20 and middle <= 26, "halfway across: %s" % middle)
	assert_true(used.size.y >= 21 and used.size.y <= 27, "whole: %s" % used.size.y)
	# Hard-edged keys are still cut into pieces
	assert_eq(InBetween.prepare(key(figure(0)), key(figure(8))).flow, null)


func test_following_soft_keys_can_be_cancelled() -> void:
	var a := blank(Vector2i(24, 24))
	var b := blank(Vector2i(24, 24))
	a.fill_rect(Rect2i(4, 4, 8, 8), Color(0.5, 0.2, 0.9, 0.6))
	b.fill_rect(Rect2i(10, 6, 8, 8), Color(0.5, 0.2, 0.9, 0.6))
	var cancelled := WorkProgress.new()
	cancelled.cancelled = true
	assert_eq(InBetween.prepare(key(a), key(b), Vector2i.ZERO, cancelled), null)
