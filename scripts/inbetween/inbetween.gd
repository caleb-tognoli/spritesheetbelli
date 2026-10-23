class_name InBetween
extends RefCounted
## Frames between two key frames, to smooth an animation: the sprite moved part of the way
## from one to the other. Keys are frames with where they're placed, see [method key_of],
## and in-betweens come out the same way, ready for [method Spritesheet.set_cell].
##
## Each key is cut into pieces, like an arm, a leg, a blade or the body, each followed to
## where it went in the other key; then each key is bent onto the other, as rigidly as it
## can, and frames bend it part of the way, turning pieces about their joints (see
## [PieceMorph]). Painted keys with soft edges are followed pixel by pixel instead (see
## [FlowMorph]). Every pixel is taken from a key, so no new colours appear.
##
## In-betweens added to a sheet remember how they were made (see [method add]), so they can
## tell when a key changed since (see [method is_stale]) and be made again in their place
## (see [method replace]).

## How the frames are spread between the keys: evenly, or bunched up near a key so the
## sprite starts or ends slowly
enum Spacing { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT }
## Where new frames go in the sheet
enum Place {
	AFTER_FIRST,  ## Right after the first key, moving the frames after it along
	FIRST_FREE,  ## In the first free cell
	APPEND,  ## After the last frame
	NEW_ROW,  ## At the start of a new row
}

const SPACING_NAMES := {  # L10n.mark
	Spacing.LINEAR: "Even",
	Spacing.EASE_IN: "Ease in",
	Spacing.EASE_OUT: "Ease out",
	Spacing.EASE_IN_OUT: "Ease in and out",
}
const PLACE_NAMES := {  # L10n.mark
	Place.AFTER_FIRST: "After the first key frame",
	Place.FIRST_FREE: "In the first free cell",
	Place.APPEND: "After the last frame",
	Place.NEW_ROW: "In a new row",
}
const MAX_COUNT := 16

## Hashes of frame pixels by image, see [method fingerprint]: [code][WeakRef, int][/code],
## as images are never changed once in a sheet
static var _pixel_hashes: Dictionary[int, Array] = {}


## The frame at [param coord] of [param sheet] as a key: its image and where it's placed
## (see [method Spritesheet.get_frame_origin]), with its pivot when it has one
static func key_of(sheet: Spritesheet, coord: Vector2i) -> Dictionary:
	var key := {"image": sheet.frames[coord], "origin": sheet.get_frame_origin(coord)}
	if sheet.has_pivot(coord):
		key.pivot = sheet.get_pivot(coord)
	return key


## What's worked out about keys [param a] and [param b] once, for every frame made from
## them: their pieces and where they went, the whole sprite moving by [param motion], a
## [Vector2i] (zero for not at all), or as found when null (see
## [method SpriteMotion.detect]). Null when [param progress] is cancelled. Slow: run it on a
## worker thread, see [WorkProgress].
static func prepare(
	a: Dictionary, b: Dictionary, motion: Variant = null, progress: WorkProgress = null
) -> PieceMorph:
	return PieceMorph.find(a, b, motion, progress)


## [param count] frames between keys [param a] and [param b], spread as [param spacing]
## says (see [method time_of]), the whole sprite moving by [param motion] from [param a]
## to [param b] (found when null, see [method prepare]), steered by [param pins] (see
## [method PieceMorph.frame])
static func generate(
	a: Dictionary,
	b: Dictionary,
	count: int,
	motion: Variant = null,
	spacing := Spacing.LINEAR,
	pins: Array[Dictionary] = [],
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var prepared := prepare(a, b, motion)
	for i in count:
		frames.append(generate_one(a, b, i, count, prepared, spacing, pins))
	return frames


## The frame halfway between the keys, from [param prepared] (see [method prepare]),
## steered by [param pins]: the frame pins are placed on, see [method PieceMorph.frame]
static func middle(prepared: PieceMorph, pins: Array[Dictionary] = []) -> Dictionary:
	return prepared.frame(0.5, pins)


## The frame at [param index] of [method generate], from [param prepared], what
## [method prepare] worked out about the same keys, steered by [param pins] (see
## [method PieceMorph.frame])
static func generate_one(
	a: Dictionary,
	b: Dictionary,
	index: int,
	count: int,
	prepared: PieceMorph,
	spacing := Spacing.LINEAR,
	pins: Array[Dictionary] = [],
) -> Dictionary:
	var t := time_of(index, count, spacing)
	return finish(a, b, prepared.frame(t, pins), index, t)


## [param frame], made [param t] of the way from key [param a] to key [param b] (see
## [method PieceMorph.frame]), made in-between [param index]: named after the first key,
## with a pivot of its own when a key has one, as far along as the frame. Changes
## [param frame] and its image, and returns it.
static func finish(
	a: Dictionary, b: Dictionary, frame: Dictionary, index: int, t: float
) -> Dictionary:
	var img: Image = frame.image
	var base := (a.image as Image).resource_name.get_basename()
	img.resource_name = (
		("%s_inbetween%d" % [base, index + 1]) if base else "inbetween%d" % [index + 1]
	)
	if a.has("pivot") or b.has("pivot"):
		var a_pivot := Vector2(a.origin) + _pivot(a)
		var b_pivot := Vector2(b.origin) + _pivot(b)
		frame.pivot = a_pivot.lerp(b_pivot, t) - Vector2(frame.origin)
	return frame


## How far from the first key to the second (0 to 1) the frame at [param index] of
## [param count] between them is. Evenly spaced, they're 1/3 and 2/3 of the way for two.
## Eased in, they bunch up near the first key so the sprite starts slowly, eased out near
## the second so it ends slowly, or both.
static func time_of(index: int, count: int, spacing := Spacing.LINEAR) -> float:
	var t := float(index + 1) / (count + 1)
	match spacing:
		Spacing.EASE_IN:
			return t * t
		Spacing.EASE_OUT:
			return 1.0 - (1.0 - t) * (1.0 - t)
		Spacing.EASE_IN_OUT:
			return 2.0 * t * t if t < 0.5 else 1.0 - 2.0 * (1.0 - t) * (1.0 - t)
	return t


static func _pivot(key: Dictionary) -> Vector2:
	return key.get("pivot", Vector2((key.image as Image).get_size()) / 2.0)


## Adds [param frames] (from [method generate]) between keys [param a] and [param b] of
## [param sheet], put in cells as [param place] says. They're also played between the keys
## in the animations of [param animations], by index, wherever they play them one after
## the other, see [method SheetAnimation.insert_between]: each index maps to whether they
## take their time from the key before them, keeping the animation's length. Each
## remembers how it was made, see [method replace]: the keys, and [param how] they were
## made, [code]{"spacing": Spacing, "motion": Vector2i, "pins": Array[Dictionary]}[/code]
## (see [method generate]). Returns the cells they went to.
static func add(
	sheet: Spritesheet,
	a: Vector2i,
	b: Vector2i,
	frames: Array[Dictionary],
	place: Place,
	animations := {},
	how := {},
) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	if frames.is_empty():
		return coords
	sheet.begin_batch()
	if place == Place.AFTER_FIRST:
		var start := sheet.index_of(a) + 1
		for i in frames.size():
			sheet.insert_empty_cell(sheet.coord_of(start))
		# The second key moved along when it came after the first
		if sheet.index_of(b) >= start:
			b = sheet.coord_of(sheet.index_of(b) + frames.size())
		for i in frames.size():
			var coord := sheet.coord_of(start + i)
			sheet.set_cell(coord, frames[i])
			coords.append(coord)
	else:
		var modes := {
			Place.FIRST_FREE: Spritesheet.AddMode.FIRST_FREE,
			Place.APPEND: Spritesheet.AddMode.APPEND,
			Place.NEW_ROW: Spritesheet.AddMode.NEW_ROW,
		}
		coords = sheet.add_cells(frames, modes[place])
	# Made together, so they're made again together
	var run := 1
	for recipe: Dictionary in sheet.inbetweens.values():
		run = maxi(run, recipe.run + 1)
	_remember(sheet, coords, a, b, run, how)
	var all := sheet.animations
	for i: int in animations:
		if i < all.size() and all[i].insert_between(a, b, coords, animations[i]) > 0:
			sheet.set_animation(i, all[i])
	sheet.end_batch()
	return coords


## Makes the in-betweens at [param cells], made together (see [method run_of]), again with
## [param frames] in their places, made [param how] (see [method add]) from their keys as
## they are now. Everything else about them stays: their cells, the animations playing them
## and how long they're shown.
static func replace(
	sheet: Spritesheet, cells: Array[Vector2i], frames: Array[Dictionary], how := {}
) -> void:
	if cells.is_empty() or cells.size() != frames.size():
		return
	var recipe: Dictionary = sheet.inbetweens.get(cells[0], {})
	if recipe.is_empty():
		return
	sheet.begin_batch()
	for i in cells.size():
		sheet.set_cell(cells[i], frames[i])
	_remember(sheet, cells, recipe.keys[0], recipe.keys[1], recipe.run, how)
	sheet.end_batch()


## Gives each of [param cells] how it was made: between keys [param a] and [param b] of
## [param sheet] as they are now, [param how], in [param run] (see [method run_of])
static func _remember(
	sheet: Spritesheet, cells: Array[Vector2i], a: Vector2i, b: Vector2i, run: int, how: Dictionary
) -> void:
	var pins: Array = how.get("pins", [])
	for i in cells.size():
		var recipe := {
			"run": run,
			"index": i,
			"count": cells.size(),
			"keys": [a, b] as Array[Vector2i],
			"fingerprints": [fingerprint(sheet, a), fingerprint(sheet, b)],
			"spacing": how.get("spacing", Spacing.LINEAR),
			"motion": how.get("motion", Vector2i.ZERO),
			"pins": pins.duplicate(true),
			"made": fingerprint(sheet, cells[i]),
		}
		sheet.set_inbetween(cells[i], recipe)


## The in-betweens made together with the one at [param coord] of [param sheet], in order,
## or none when it isn't one
static func run_of(sheet: Spritesheet, coord: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not sheet.inbetweens.has(coord):
		return cells
	var run: int = sheet.inbetweens[coord].run
	var by_index := {}
	for cell in sheet.inbetweens:
		if sheet.inbetweens[cell].run == run:
			by_index[sheet.inbetweens[cell].index] = cell
	var indices := by_index.keys()
	indices.sort()
	for index: int in indices:
		cells.append(by_index[index])
	return cells


## Whether both keys of the in-between at [param coord] are still in [param sheet], so it
## can be made again
static func has_keys(sheet: Spritesheet, coord: Vector2i) -> bool:
	var recipe: Dictionary = sheet.inbetweens.get(coord, {})
	if recipe.is_empty():
		return false
	return recipe.keys.all(func(key: Vector2i) -> bool: return sheet.has_frame(key))


## Whether a key of the in-between at [param coord] changed since it was made: its pixels,
## where it's placed or its pivot. False when a key is gone.
static func is_stale(sheet: Spritesheet, coord: Vector2i) -> bool:
	if not has_keys(sheet, coord):
		return false
	var recipe: Dictionary = sheet.inbetweens[coord]
	for i in 2:
		if fingerprint(sheet, recipe.keys[i]) != recipe.fingerprints[i]:
			return true
	return false


## Whether any in-between at [param cells] was changed since it was made, so making it
## again loses that
static func is_edited(sheet: Spritesheet, cells: Array[Vector2i]) -> bool:
	for cell in cells:
		var recipe: Dictionary = sheet.inbetweens.get(cell, {})
		if recipe and fingerprint(sheet, cell) != recipe.made:
			return true
	return false


## Says which in-between the frame at [param coord] is, like "In-between 2 of 3", and
## whether it's out of date. Empty when it isn't one.
static func describe(sheet: Spritesheet, coord: Vector2i) -> String:
	var recipe: Dictionary = sheet.inbetweens.get(coord, {})
	if recipe.is_empty():
		return ""
	var text := (
		TranslationServer.translate("In-between %d of %d") % [recipe.index + 1, recipe.count]
	)
	if not has_keys(sheet, coord):
		return text + " · " + TranslationServer.translate("a key frame was removed")
	if is_stale(sheet, coord):
		return text + " · " + TranslationServer.translate("out of date: a key frame changed")
	return text


## A number that changes when the frame at [param coord] of [param sheet] does, as a key
## (see [method key_of]): its pixels, where it's placed and its pivot. 0 without a frame.
static func fingerprint(sheet: Spritesheet, coord: Vector2i) -> int:
	if not sheet.has_frame(coord):
		return 0
	var key := key_of(sheet, coord)
	var img: Image = key.image
	return [_pixels_hash(img), img.get_size(), key.origin, key.get("pivot")].hash()


## The hash of [param img]'s pixels, worked out once for each image
static func _pixels_hash(img: Image) -> int:
	var id := img.get_instance_id()
	var known: Array = _pixel_hashes.get(id, [])
	if known and (known[0] as WeakRef).get_ref() == img:
		return known[1]
	if _pixel_hashes.size() > 1024:
		_pixel_hashes.clear()
	var hashed := hash(img.get_data())
	_pixel_hashes[id] = [weakref(img), hashed]
	return hashed
