class_name OptionsDropdown
extends Button
## A button that drops down a floating panel of rarely needed fields, and shows what's set
## in them as its text, e.g. "Spacing 2 · Extrude 1", or [member placeholder] when nothing
## is. Fields are added with [method add_field]; call [method update_text] after changes.
## A field can have a button that resets it, shown while it isn't at its default.

const ARROW := preload("res://assets/icons/GuiTreeArrowDown.svg")
const RESET_ICON := preload("res://assets/icons/Reload.svg")

## Shown when nothing is set
var placeholder := ""
## Returns what's set, like "Spacing 2 · Extrude 1", or an empty string
var summarize := Callable()
var popup := PopupPanel.new()
var fields := GridContainer.new()
## Reset buttons, with whether their field is at its default
var _resets: Dictionary[Button, Callable] = {}


func _init(empty_text := "") -> void:
	placeholder = empty_text
	text = placeholder
	icon = ARROW
	icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Never wider than its place: the text is cut short instead
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fields.columns = 3
	fields.add_theme_constant_override("h_separation", 12)
	fields.add_theme_constant_override("v_separation", 8)
	popup.add_child(fields)
	add_child(popup)
	pressed.connect(open)


## Adds a labelled [param control] to the panel. Clicking the label focuses the control.
## With [param reset], a button after it calls that while [param is_default] is false.
func add_field(
	label_text: String,
	control: Control,
	tooltip := "",
	reset := Callable(),
	is_default := Callable(),
) -> void:
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
	# The slot keeps its width without a button, so fields don't move when it hides
	var slot := CenterContainer.new()
	slot.custom_minimum_size = Vector2(24, 0)
	fields.add_child(slot)
	if reset.is_valid():
		var button := Button.new()
		button.icon = RESET_ICON
		button.flat = true
		button.tooltip_text = tr("Reset %s") % label_text
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(reset)
		button.pressed.connect(update_text)
		slot.add_child(button)
		_resets[button] = is_default


## Opens the panel below the button, at least as wide as it
func open() -> void:
	var below := get_global_rect()
	below.position.y += below.size.y + 4
	popup.popup_on_parent(Rect2i(Rect2(below.position, Vector2(below.size.x, 0))))


## Shows what's set, see [member summarize]
func update_text() -> void:
	var summary: String = summarize.call() if summarize.is_valid() else ""
	text = summary if summary else tr(placeholder)
	for button in _resets:
		button.visible = not _resets[button].call()
