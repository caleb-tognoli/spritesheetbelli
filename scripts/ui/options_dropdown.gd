class_name OptionsDropdown
extends Button
## A button that drops down a floating panel of rarely needed fields, and shows what's set
## in them as its text, e.g. "Spacing 2 · Extrude 1", or [member placeholder] when nothing
## is. Fields are added with [method add_field]; call [method update_text] after changes.

const ARROW := preload("res://assets/icons/GuiTreeArrowDown.svg")

## Shown when nothing is set
var placeholder := ""
## Returns what's set, like "Spacing 2 · Extrude 1", or an empty string
var summarize := Callable()
var popup := PopupPanel.new()
var fields := GridContainer.new()


func _init(empty_text := "") -> void:
	placeholder = empty_text
	text = placeholder
	icon = ARROW
	icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Never wider than its place: the text is cut short instead
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 12)
	fields.add_theme_constant_override("v_separation", 8)
	popup.add_child(fields)
	add_child(popup)
	pressed.connect(open)


## Adds a labelled [param control] to the panel. Clicking the label focuses the control.
func add_field(label_text: String, control: Control, tooltip := "") -> void:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if tooltip:
		control.tooltip_text = tooltip
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(label)
	fields.add_child(control)
	LabelLink.link(label, control)


## Opens the panel below the button, at least as wide as it
func open() -> void:
	var below := get_global_rect()
	below.position.y += below.size.y + 4
	popup.popup_on_parent(Rect2i(Rect2(below.position, Vector2(below.size.x, 0))))


## Shows what's set, see [member summarize]
func update_text() -> void:
	var summary: String = summarize.call() if summarize.is_valid() else ""
	text = summary if summary else tr(placeholder)
