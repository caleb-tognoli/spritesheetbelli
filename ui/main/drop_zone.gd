class_name DropZone
extends MarginContainer
## A box with a dashed outline where files can be dropped, like the upload zones of web
## pages. Files dropped anywhere in the window are opened too; the zone shows where to.

const DASH := 6.0
const RADIUS := 8.0
const WIDTH := 1.0


func _notification(what: int) -> void:
	if what in [NOTIFICATION_THEME_CHANGED, NOTIFICATION_RESIZED]:
		queue_redraw()


func _draw() -> void:
	var color := get_theme_color(&"font_color", &"StatusLabel")
	var rect := Rect2(Vector2.ONE * WIDTH / 2, size - Vector2.ONE * WIDTH)
	var r := minf(RADIUS, minf(rect.size.x, rect.size.y) / 2)
	var top_left := rect.position
	var bottom_right := rect.end
	var top_right := Vector2(bottom_right.x, top_left.y)
	var bottom_left := Vector2(top_left.x, bottom_right.y)
	# The sides, dashed between the rounded corners
	for side: Array in [
		[top_left + Vector2(r, 0), top_right - Vector2(r, 0)],
		[top_right + Vector2(0, r), bottom_right - Vector2(0, r)],
		[bottom_right - Vector2(r, 0), bottom_left + Vector2(r, 0)],
		[bottom_left - Vector2(0, r), top_left + Vector2(0, r)],
	]:
		draw_dashed_line(side[0], side[1], color, WIDTH, DASH, false, true)
	# The corners, clockwise from the top left
	var corners := [
		top_left + Vector2(r, r),
		top_right + Vector2(-r, r),
		bottom_right - Vector2(r, r),
		bottom_left + Vector2(r, -r),
	]
	for i in corners.size():
		var start := PI + i * PI / 2
		draw_arc(corners[i], r, start, start + PI / 2, 8, color, WIDTH, true)
