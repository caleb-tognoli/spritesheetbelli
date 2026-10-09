class_name InBetween
extends RefCounted
## Frames between two key frames, to smooth an animation: the sprite moved part of the way
## from one to the other. Keys are frames with where they're placed, see [method key_of],
## and in-betweens come out the same way, ready for [method Spritesheet.set_cell].
##
## Each key is cut into pieces, like an arm, a leg, a blade or the body, each followed to
## where it went in the other key, turning about its joint along the way (see
## [PieceMorph]). Every pixel is taken from a key, so no new colours appear.

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


## The frame at [param coord] of [param sheet] as a key: its image and where it's placed
## (see [method Spritesheet.get_frame_origin]), with its pivot when it has one
static func key_of(sheet: Spritesheet, coord: Vector2i) -> Dictionary:
	var key := {"image": sheet.frames[coord], "origin": sheet.get_frame_origin(coord)}
	if sheet.has_pivot(coord):
		key.pivot = sheet.get_pivot(coord)
	return key


## What's worked out about keys [param a] and [param b] once, for every frame made from
## them: their pieces and where they went, the whole sprite moving by [param motion] (see
## [method SpriteMotion.detect]). Null when [param progress] is cancelled. Slow: run it on a
## worker thread, see [WorkProgress].
static func prepare(
	a: Dictionary, b: Dictionary, motion := Vector2i.ZERO, progress: WorkProgress = null
) -> PieceMorph:
	return PieceMorph.find(a, b, motion, progress)


## [param count] frames between keys [param a] and [param b], spread as [param spacing]
## says (see [method time_of]), the whole sprite moving by [param motion] from [param a]
## to [param b] (found when zero)
static func generate(
	a: Dictionary, b: Dictionary, count: int, motion := Vector2i.ZERO, spacing := Spacing.LINEAR
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var prepared := prepare(a, b, motion)
	for i in count:
		frames.append(generate_one(a, b, i, count, prepared, spacing))
	return frames


## The frame at [param index] of [method generate], from [param prepared], what
## [method prepare] worked out about the same keys
static func generate_one(
	a: Dictionary,
	b: Dictionary,
	index: int,
	count: int,
	prepared: PieceMorph,
	spacing := Spacing.LINEAR,
) -> Dictionary:
	var t := time_of(index, count, spacing)
	var frame := prepared.frame(t)
	var img: Image = frame.image
	var base := (a.image as Image).resource_name.get_basename()
	img.resource_name = (
		("%s_inbetween%d" % [base, index + 1]) if base else "inbetween%d" % [index + 1]
	)
	# A pivot of their own when a key has one, as far along as the frame
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
## [param sheet], put in cells as [param place] says. With [param to_animations], they're
## also played between the keys wherever an animation plays them one after the other, see
## [method SheetAnimation.insert_between], with [param keep_length] taking their time
## from the key before them. Returns the cells they went to.
static func add(
	sheet: Spritesheet,
	a: Vector2i,
	b: Vector2i,
	frames: Array[Dictionary],
	place: Place,
	to_animations: bool,
	keep_length := false,
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
	if to_animations:
		var animations := sheet.animations
		for i in animations.size():
			if animations[i].insert_between(a, b, coords, keep_length) > 0:
				sheet.set_animation(i, animations[i])
	sheet.end_batch()
	return coords
