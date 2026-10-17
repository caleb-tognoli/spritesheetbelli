extends "res://tests/test_case.gd"
## In-betweens steered by pins on the middle frame (PinWarp): no pins changes nothing, a
## pin left where it was holds, a dragged pin takes its point where it's dragged halfway
## and fades out at the keys

const GREEN := Color.SEA_GREEN
const SKIN := Color("f2c094")
const SHIRT := Color("3b6fd1")
const LEGS := Color("2b2b40")


static func key(img: Image, origin := Vector2i.ZERO) -> Dictionary:
	return {"image": img, "origin": origin}


static func blank(size := Vector2i(32, 32)) -> Image:
	return Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)


## A figure with its right arm raised by [param raised] pixels: drawn as pieces
static func figure(raised: int) -> Image:
	var img := blank()
	img.fill_rect(Rect2i(13, 4, 6, 6), SKIN)
	img.fill_rect(Rect2i(12, 10, 8, 10), SHIRT)
	img.fill_rect(Rect2i(13, 20, 2, 8), LEGS)
	img.fill_rect(Rect2i(17, 20, 2, 8), LEGS)
	img.fill_rect(Rect2i(10, 11, 2, 7), SKIN)
	img.fill_rect(Rect2i(20, 11 - raised, 2, 7), SKIN)
	return img


## An ellipse [param across] × [param down] pixels round the middle: wide to tall is bent
static func ellipse(across: float, down: float) -> Image:
	var img := blank(Vector2i(40, 32))
	for y in 32:
		for x in 40:
			var at := Vector2(x + 0.5, y + 0.5) - Vector2(20, 16)
			if (at / Vector2(across, down)).length() <= 1.0:
				img.set_pixel(x, y, GREEN)
	return img


## A painted blob with a soft edge round [param at]: followed pixel by pixel
static func blob(at: Vector2) -> Image:
	var img := blank(Vector2i(48, 40))
	for y in 40:
		for x in 48:
			var offset := Vector2(x + 0.5, y + 0.5) - at
			var reach := Vector2(offset.x / 7.0, offset.y / 11.0).length()
			if reach <= 1.1:
				var light := clampf(1.0 - (offset - Vector2(-2, -4)).length() / 14.0, 0.0, 1.0)
				var color := Color(0.8, 0.2, 0.2).lerp(Color(1.0, 0.8, 0.6), light)
				color.a = clampf((1.1 - reach) * 6.0, 0.0, 1.0)
				img.set_pixel(x, y, color)
	return img


## The three kinds of in-betweens: drawn as pieces, bent, followed pixel by pixel
static func morphs() -> Array[PieceMorph]:
	return [
		InBetween.prepare(key(figure(0)), key(figure(8))),
		InBetween.prepare(key(ellipse(14, 3)), key(ellipse(5, 13))),
		InBetween.prepare(key(blob(Vector2(14, 20))), key(blob(Vector2(30, 18)))),
	]


## Where [param frame] shows anything, placed
static func shown(frame: Dictionary) -> Rect2i:
	var used := (frame.image as Image).get_used_rect()
	return Rect2i(used.position + frame.origin, used.size)


## Whether [param frame] shows anything at [param point], placed
static func shows(frame: Dictionary, point: Vector2) -> bool:
	var local := Vector2i(point.floor()) - Vector2i(frame.origin)
	var img: Image = frame.image
	return Rect2i(Vector2i.ZERO, img.get_size()).has_point(local) and img.get_pixelv(local).a > 0


## The middle of the lowest pixel [param frame] shows, placed
static func lowest(frame: Dictionary) -> Vector2:
	var img: Image = frame.image
	var found := Vector2.ZERO
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0:
				found = Vector2(frame.origin) + Vector2(x + 0.5, y + 0.5)
	return found


## The colour [param frame] shows at [param point], placed
static func color(frame: Dictionary, point: Vector2) -> Color:
	if not shows(frame, point):
		return Color(0, 0, 0, 0)
	return (frame.image as Image).get_pixelv(Vector2i(point.floor()) - Vector2i(frame.origin))


static func same(x: Dictionary, y: Dictionary) -> bool:
	return x.origin == y.origin and (x.image as Image).get_data() == (y.image as Image).get_data()


func test_the_three_kinds() -> void:
	var kinds := morphs()
	assert_true(kinds[0].meshes.is_empty() and kinds[0].flow == null, "pieces")
	assert_eq(kinds[1].meshes.size(), 2, "bent")
	assert_ne(kinds[2].flow, null, "followed pixel by pixel")


func test_no_pins_changes_nothing() -> void:
	for morph in morphs():
		for t in [0.25, 0.5, 0.75]:
			var none: Array[Dictionary] = []
			assert_true(same(morph.frame(t), morph.frame(t, none)))
		assert_true(same(InBetween.middle(morph), morph.frame(0.5)))


func test_the_keys_stay_as_they_are() -> void:
	var pins: Array[Dictionary] = [
		{"at": Vector2(20, 14), "to": Vector2(26, 8)},
		{"at": Vector2(12, 24), "to": Vector2(12, 24)}
	]
	for morph in morphs():
		for t in [0.0, 1.0]:
			assert_true(same(morph.frame(t, pins), morph.frame(t)), "at %s" % t)


func test_one_dragged_pin_moves_the_part_round_it() -> void:
	for morph in morphs():
		var plain := InBetween.middle(morph)
		var before := shown(plain)
		# The bottom dragged down: the bottom goes with it, the top stays
		var at := lowest(plain) + Vector2(0, -1)
		var pins: Array[Dictionary] = [{"at": at, "to": at + Vector2(0, 4)}]
		var pinned := morph.frame(0.5, pins)
		var after := shown(pinned)
		assert_true(after.end.y >= before.end.y + 3, "the bottom down: %s, %s" % [before, after])
		assert_eq(after.position.y, before.position.y, "the top stays")
		assert_true(shows(pinned, at + Vector2(0, 4)), "the dragged spot there")
		for y in range(before.position.y, before.position.y + 3):
			for x in range(before.position.x, before.end.x):
				var spot := Vector2(x + 0.5, y + 0.5)
				assert_eq(color(pinned, spot), color(plain, spot), "the top unchanged at %s" % spot)
		# A quarter of the way, three quarters as far
		var quarter := shown(morph.frame(0.25, pins))
		var unpinned := shown(morph.frame(0.25))
		assert_true(absi(quarter.end.y - unpinned.end.y - 3) <= 1, "%s, %s" % [quarter, unpinned])


func test_a_held_head_stays_upright_while_the_hip_drags() -> void:
	# Held on the face, the hip dragged up and out: the head doesn't turn
	var morph := InBetween.prepare(key(figure(0)), key(figure(8)))
	var plain := InBetween.middle(morph)
	var pins: Array[Dictionary] = [
		{"at": Vector2(16, 7), "to": Vector2(16, 7)},
		{"at": Vector2(19, 18), "to": Vector2(24, 12)},
	]
	var pinned := morph.frame(0.5, pins)
	for y in range(4, 8):
		for x in range(12, 20):
			var spot := Vector2(x + 0.5, y + 0.5)
			assert_eq(color(pinned, spot), color(plain, spot), "the head unchanged at %s" % spot)
	assert_true(shows(pinned, Vector2(24, 12)), "the hip there")


func test_an_anchored_pin_holds_while_another_drags() -> void:
	var morph := InBetween.prepare(key(ellipse(14, 3)), key(ellipse(5, 13)))
	var plain := InBetween.middle(morph)
	# The left end held, the right end dragged up, both a pixel in from the ends
	var img: Image = plain.image
	var left := Vector2(INF, 0)
	var right := Vector2(-INF, 0)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0:
				var point := Vector2(plain.origin) + Vector2(x + 0.5, y + 0.5)
				left = point if point.x < left.x else left
				right = point if point.x > right.x else right
	var held := left + Vector2(1, 0)
	var dragged := right - Vector2(1, 0)
	var to := dragged + Vector2(0, -6)
	var pins: Array[Dictionary] = [{"at": held, "to": held}, {"at": dragged, "to": to}]
	var pinned := morph.frame(0.5, pins)
	for frame in [plain, pinned]:
		assert_true(shows(frame, held), "the held end shown")
	assert_true(shown(pinned).position.y <= shown(plain).position.y - 3, "the dragged end up")
	# The triangles: the held point stays, the dragged one lands where it's dragged, and a
	# quarter of the way, three quarters as far
	var mesh: KeyMesh = morph.meshes[0]
	var placed := Vector2(morph.rect.position)
	var from := PackedVector2Array([(held - placed) / morph.zoom, (dragged - placed) / morph.zoom])
	var goals := PackedVector2Array([from[0], (to - placed) / morph.zoom])
	var half := mesh.at(0.5)
	var located := MeshTools.Located.new()
	for point in from:
		var place := mesh._nearest_place(half, point)
		located.points.append(point)
		located.pixels.append(0)
		located.triangles.append(int(place.x))
		located.weights.append(Vector3(place.y, place.z, 1.0 - place.y - place.z))
	var after := located.at(mesh.pinned(half, 0.5, from, goals), mesh.triangles)
	assert_true(after[0].distance_to(from[0]) < 0.5, "held: %s, %s" % [after[0], from[0]])
	assert_true(after[1].distance_to(goals[1]) < 0.5, "dragged: %s, %s" % [after[1], goals[1]])
	var quarter := mesh.at(0.25)
	var bent := mesh.pinned(quarter, 0.25, from, goals)
	var moved := located.at(bent, mesh.triangles)[1] - located.at(quarter, mesh.triangles)[1]
	assert_true(moved.distance_to((goals[1] - from[1]) * 0.75) < 0.5, "a quarter: %s" % moved)


func test_a_pin_on_pieces_moves_its_point() -> void:
	# The raised arm's hand, dragged further out halfway, with the body held
	var morph := InBetween.prepare(key(figure(0)), key(figure(8)))
	var pins: Array[Dictionary] = [
		{"at": Vector2(16, 14), "to": Vector2(16, 14)},
		{"at": Vector2(21, 9), "to": Vector2(27, 9)},
	]
	var frame := morph.frame(0.5, pins)
	var img: Image = frame.image
	var local: Vector2i = Vector2i(16, 14) - frame.origin
	assert_eq(img.get_pixelv(local), SHIRT, "the body held")
	assert_true(shown(frame).end.x >= 26, "the arm out: %s" % shown(frame))


func test_pinned_frames_can_be_drawn_on_several_threads() -> void:
	for morph in morphs():
		var middle := InBetween.middle(morph)
		var at := Vector2(shown(middle).get_center())
		var pins: Array[Dictionary] = [
			{"at": at, "to": at + Vector2(3, 2)},
			{"at": at + Vector2(4, 4), "to": at + Vector2(4, 4)}
		]
		var times := [0.2, 0.4, 0.5, 0.6, 0.8]
		var alone := []
		for t in times:
			alone.append(morph.frame(t, pins))
		var together := []
		together.resize(times.size())
		var work := func(i: int) -> void: together[i] = morph.frame(times[i], pins)
		var task := WorkerThreadPool.add_group_task(work, times.size())
		WorkerThreadPool.wait_for_group_task_completion(task)
		for i in times.size():
			assert_true(same(together[i], alone[i]), "the same at %s" % times[i])
