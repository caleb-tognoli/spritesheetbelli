class_name PixelZoom
## Zoom levels that keep pixel art even: whole zooms from 100% up, and 1/2, 1/3, 1/4…
## below it, so every pixel of a sprite covers the same number of pixels on screen.
## For every view that zooms, when [method is_on].
##
## Zooms are in interface pixels, as views show them, but the levels are whole in screen
## pixels. With the interface scaled, a level is as many screen pixels as the whole part
## of the scale, see [method unit]: at 150%, a sprite pixel is 1, 2, 3… screen pixels at
## 67%, 133%, 200%…; at 100% and 200% the levels are 100%, 200%, 300%…

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


## How many screen pixels an interface pixel covers where [param item] is drawn: the
## interface's scale, as its window draws it
static func screen_scale(item: CanvasItem) -> float:
	var window := item.get_window() if item.is_inside_tree() else null
	return window.get_final_transform().get_scale().x if window else 1.0


## The first whole zoom from 100% up, with [param scale] screen pixels to an interface
## pixel: as many screen pixels as the whole part of the scale, e.g. 1 at 150% (67%) and 2
## at 200% (100%)
static func unit(scale: float) -> float:
	return maxf(floorf(scale + EPSILON), 1.0) / scale


## [param zoom] for [param item]'s view to fit something in: rounded down to a whole zoom
## when [method is_on]
static func fitting(item: CanvasItem, zoom: float) -> float:
	return round_down(zoom, screen_scale(item)) if is_on() else zoom


## [param zoom] times [param factor] for [param item]'s view, or the whole zoom a step
## that way when [method is_on], see [method step]
static func zoom_by(item: CanvasItem, zoom: float, factor: float) -> float:
	return step(zoom, factor, screen_scale(item)) if is_on() else zoom * factor


## 100% for [param item]'s view, or the whole zoom nearest it when [method is_on]
static func actual_size(item: CanvasItem) -> float:
	return nearest(1.0, screen_scale(item)) if is_on() else 1.0


## The largest whole zoom up to [param zoom], to fit a sheet in a view, with
## [param scale] screen pixels to an interface pixel
static func round_down(zoom: float, scale := 1.0) -> float:
	var size := unit(scale)
	var units := zoom / size
	if units >= 1 - EPSILON:
		return floorf(units + EPSILON) * size
	return size / ceilf(1 / units - EPSILON)


## The whole zoom a step from [param zoom] towards [param zoom] × [param factor]: the
## nearest whole zoom to that, but at least the next one, so steps grow with the zoom
## as they do without whole levels. With [param scale] screen pixels to an interface pixel.
static func step(zoom: float, factor: float, scale := 1.0) -> float:
	var size := unit(scale)
	var level := _to_level(zoom / size)
	var target := roundf(_to_level(zoom * factor / size))
	if factor > 1:
		return _from_level(maxf(floorf(level + EPSILON) + 1, target)) * size
	return _from_level(minf(ceilf(level - EPSILON) - 1, target)) * size


## The whole zoom nearest [param zoom], the bigger one halfway, with [param scale] screen
## pixels to an interface pixel
static func nearest(zoom: float, scale := 1.0) -> float:
	var size := unit(scale)
	return _from_level(roundf(_to_level(zoom / size))) * size


## Numbers whole zooms one after another: 1, 2, 3… are 100%, 200%, 300%…, and 0, -1,
## -2… are 1/2, 1/3, 1/4…, in units, see [method unit]
static func _to_level(zoom: float) -> float:
	return zoom if zoom >= 1 else 2 - 1 / zoom


static func _from_level(level: float) -> float:
	return level if level >= 1 else 1 / (2 - level)
