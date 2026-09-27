class_name PixelZoom
## Zoom levels that keep pixel art even: whole zooms from 100% up, and 1/2, 1/3, 1/4…
## below it, so every pixel of a sprite covers the same number of pixels on screen.
## For every view that zooms, when [method is_on].

## Leeway for zooms that are whole but for rounding errors
const EPSILON := 0.0001


## Whether the views zoom by whole levels, following the pixel_perfect_zoom setting and
## the open sheet's resize filter
static func is_on() -> bool:
	return applies(Settings.get_value(&"pixel_perfect_zoom"), Global.spritesheet.scale_filter)


## Whether zooms are whole with [param setting] ("auto", "on" or "off") for a sheet that
## resizes sprites with [param filter]. Auto takes Nearest, the filter for pixel art, to
## mean the sheet is pixel art.
static func applies(setting: String, filter: Image.Interpolation) -> bool:
	match setting:
		"on":
			return true
		"off":
			return false
	return filter == Image.INTERPOLATE_NEAREST


## The largest whole zoom up to [param zoom], to fit a sheet in a view
static func round_down(zoom: float) -> float:
	if zoom >= 1 - EPSILON:
		return floorf(zoom + EPSILON)
	return 1 / ceilf(1 / zoom - EPSILON)


## The whole zoom a step from [param zoom] towards [param zoom] × [param factor]: the
## nearest whole zoom to that, but at least the next one, so steps grow with the zoom
## as they do without whole levels
static func step(zoom: float, factor: float) -> float:
	var level := _to_level(zoom)
	var target := roundf(_to_level(zoom * factor))
	if factor > 1:
		return _from_level(maxf(floorf(level + EPSILON) + 1, target))
	return _from_level(minf(ceilf(level - EPSILON) - 1, target))


## Numbers whole zooms one after another: 1, 2, 3… are 100%, 200%, 300%…, and 0, -1,
## -2… are 1/2, 1/3, 1/4…
static func _to_level(zoom: float) -> float:
	return zoom if zoom >= 1 else 2 - 1 / zoom


static func _from_level(level: float) -> float:
	return level if level >= 1 else 1 / (2 - level)
