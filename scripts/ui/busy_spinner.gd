class_name BusySpinner
extends Control
## Turns while something is being worked on: an arc going round a faint ring, in the
## accent colour. It only turns while shown.

## Turns a second
const SPEED := 1.25
## How much of the ring the arc covers
const ARC := 0.3
const WIDTH := 2.0

var _angle := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(16, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_process(is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_angle = fmod(_angle + delta * TAU * SPEED, TAU)
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) / 2.0 - WIDTH
	if radius <= 0.0:
		return
	var center := size / 2.0
	var color := Global.accent_color
	draw_arc(center, radius, 0.0, TAU, 32, Color(color, 0.25), WIDTH, true)
	draw_arc(center, radius, _angle, _angle + TAU * ARC, 12, color, WIDTH, true)
