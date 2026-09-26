class_name AtlasSettings
extends RefCounted
## How frames are packed into an atlas: the size of its pages, the space around frames and
## how they're placed. Stored per sheet, see [member Spritesheet.atlas_settings].

## How the packer picks a free place, from the MaxRects rules
enum Heuristic {
	BEST_SHORT_SIDE,  ## Where the shorter leftover side is smallest; usually the tightest
	BEST_LONG_SIDE,  ## Where the longer leftover side is smallest
	BEST_AREA,  ## In the smallest free space
	BOTTOM_LEFT,  ## As high, then as far left, as possible
	CONTACT,  ## Touching as much of the other frames and the edges as possible
}
## What happens to the frames already placed when frames are added or change
enum PackMode {
	AUTO,  ## Everything is packed again, as tightly as possible
	KEEP,  ## Frames stay where they are; new and grown ones go in the free space
}
## The size data files give for each frame, which engines use to line frames up
enum SourceSize {
	CELL,  ## The cell, so the frames of an animation line up like in the grid
	SPRITE,  ## The frame itself, for sprites that have nothing to do with each other
}

## Neither side of a page is longer. Frames that don't fit alone get a page of their own.
var max_size := 4096
var heuristic := Heuristic.BEST_SHORT_SIDE
## Frames may be stored turned 90° clockwise when they fit better that way
var allow_rotation := false
## Frames are packed without their transparent borders
var trim := true
## Frames that look the same are packed once and share their place
var dedupe := true
## Empty pixels around each page
var padding := 0
## Empty pixels between frames
var spacing := 0
## Pixels by which each frame's edges are repeated outward, against texture bleeding
var extrude := 0
var power_of_two := false
var square := false
var pack_mode := PackMode.AUTO
var source_size := SourceSize.CELL
## The pivot of frames without one, from 0 to 1 across the frame
var default_pivot := Vector2(0.5, 0.5)

const _KEYS: Array[StringName] = [
	&"max_size",
	&"heuristic",
	&"allow_rotation",
	&"trim",
	&"dedupe",
	&"padding",
	&"spacing",
	&"extrude",
	&"power_of_two",
	&"square",
	&"pack_mode",
	&"source_size",
	&"default_pivot",
]


static func from_dictionary(values: Dictionary) -> AtlasSettings:
	var settings := AtlasSettings.new()
	for key in _KEYS:
		if not values.has(key):
			continue
		var value: Variant = values[key]
		var expected := typeof(settings.get(key))
		if typeof(value) != expected and (value is float or value is int):
			value = type_convert(value, expected)
		if typeof(value) == expected:
			settings.set(key, value)
	settings.max_size = clampi(settings.max_size, 16, AtlasPacker.MAX_SIZE)
	return settings


## The values that aren't the defaults
func to_dictionary() -> Dictionary:
	var result := {}
	var defaults := AtlasSettings.new()
	for key in _KEYS:
		if get(key) != defaults.get(key):
			result[key] = get(key)
	return result


func duplicate() -> AtlasSettings:
	return from_dictionary(to_dictionary())


## Space each frame takes besides its own pixels, on its right and bottom
func get_margin() -> int:
	return spacing + extrude * 2
