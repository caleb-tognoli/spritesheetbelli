class_name DropOverlay
extends MarginContainer
## Over the canvas while files are dragged over the window and a document is open, says
## they can be dropped, like the start screen's drop zone does while nothing is (see
## [FileDrag]). It doesn't take the mouse.

const HINT := "Drop to add"  # L10n.mark
## Around the zone, inside the canvas
const MARGIN := 12

## Shows instead of this while it's visible
var start_screen: Control
var zone := DropZone.new()
var hint := Label.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + side, MARGIN)
	zone.highlighted = true
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zone)
	# On a panel, to be read over the sprites
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BusyPanel"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(panel)
	hint.text = HINT
	hint.theme_type_variation = &"EmptyHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hint)
	FileDrag.entered.connect(_update)
	FileDrag.exited.connect(_update)
	if start_screen:
		start_screen.visibility_changed.connect(_update)
	_update()


func _update() -> void:
	visible = FileDrag.dragging and not (start_screen and start_screen.visible)
