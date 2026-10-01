class_name ColorKeyDropdown
extends OptionsDropdown
## An eyedropper button that drops down a colour to make transparent, like a sheet's
## background, and how close a pixel must be to it: the colour as a long field that opens
## the colour picker, an eyedropper at its end that picks it by clicking a preview (see
## [method add_picker]), a tolerance, then Confirm and Cancel.
##
## Changes are told with [signal changed] as they're made, to preview them. Confirm keeps
## them and remembers the tolerance; Cancel, Escape or clicking away puts back what was set
## when it opened. The panel isn't a popup that closes on any click outside: that would
## eat the click that picks a colour, or one let through to a preview, see
## [method let_clicks_through]. Clicking away is handled here instead, see [method _input].

## It was turned on or off, or its colour or tolerance changed. Changes can come many at
## once, e.g. while dragging in the picker.
signal changed
## The eyedropper was turned on or off
signal picking_changed(on: bool)
## About to open, e.g. to suggest a colour, see [method set_key]
signal opening
signal confirmed
## Closed without Confirm, with what was set when it opened put back
signal canceled

const EYEDROPPER_ICON := preload("res://assets/icons/ColorPick.svg")
## Mouse buttons whose clicks outside the panel close it
const CLICKS: Array[MouseButton] = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
## Height of the colour strip under the icon, see [member shows_color]
const STRIP_HEIGHT := 3.0

## Makes the colour transparent when pressed. Hidden unless it can be turned off, see
## [method _init].
var enabled_check := CheckBox.new()
## The colour, across the panel with its hex code on it. Clicking it opens the picker.
var swatch := ColorPickerButton.new()
var eyedropper := Button.new()
## How different a pixel can be from the colour, in percent
var tolerance_field := SpinBox.new()
## Says what the colour is removed from, when there's something to say
var note := Label.new()
var confirm_button := Button.new()
var cancel_button := Button.new()
## Shows the colour in a strip under the icon while it's on
var shows_color := false

## Where clicks pick a colour while picking, rather than close the panel
var _pick_areas: Array[Control] = []
## Where clicks go through to what's under them, rather than close the panel
var _open_areas: Array[Control] = []
## What was set when it opened: on, colour and tolerance
var _opened_with := []
## Whether it's being closed here, rather than by the panel going away
var _closing := false


## With [param optional], it can be turned off, and the button shows the colour while on
func _init(optional := false) -> void:
	super()
	icon = EYEDROPPER_ICON
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	theme_type_variation = &"ToolbarButton"
	focus_mode = Control.FOCUS_NONE
	shows_color = optional
	popup.popup_window = false
	popup.popup_hide.connect(_on_popup_hide)
	popup.window_input.connect(_on_popup_input)

	enabled_check.text = "Make transparent"
	enabled_check.tooltip_text = "Makes this colour transparent before cutting"
	enabled_check.visible = optional
	enabled_check.toggled.connect(
		func(_on: bool) -> void:
			_update_state()
			changed.emit()
	)
	content.add_child(enabled_check)
	content.move_child(enabled_check, 0)

	swatch.custom_minimum_size = Vector2(180, 0)
	swatch.edit_alpha = false
	swatch.color_changed.connect(
		func(_color: Color) -> void:
			enabled_check.set_pressed_no_signal(true)
			_update_state()
			changed.emit()
	)
	swatch.draw.connect(_draw_hex)
	var slot := add_field(
		L10n.mark("Colour"),
		swatch,
		L10n.mark("The colour to make transparent. Click to choose it.")
	)
	eyedropper.icon = EYEDROPPER_ICON
	eyedropper.flat = true
	eyedropper.toggle_mode = true
	eyedropper.focus_mode = Control.FOCUS_NONE
	eyedropper.tooltip_text = "Pick the colour by clicking the preview"
	eyedropper.toggled.connect(picking_changed.emit)
	slot.add_child(eyedropper)

	tolerance_field.max_value = 100
	tolerance_field.suffix = "%"
	tolerance_field.select_all_on_focus = true
	tolerance_field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tolerance_field.value_changed.connect(
		func(_value: float) -> void:
			update_text()
			if is_on():
				changed.emit()
	)
	var default_percent := roundf(SheetBackground.DEFAULT_TOLERANCE * 100.0)
	add_field(
		L10n.mark("Tolerance"),
		tolerance_field,
		L10n.mark("How different a pixel can be and still be made transparent"),
		func() -> void: tolerance_field.value = default_percent,
		func() -> bool: return tolerance_field.value == default_percent
	)

	note.theme_type_variation = &"StatusLabel"
	note.visible = false
	content.add_child(note)
	var row := HBoxContainer.new()
	content.add_child(row)
	confirm_button.text = "Apply"
	cancel_button.text = "Cancel"
	for button: Button in [confirm_button, cancel_button]:
		row.add_child(button)
	DialogButtons.arrange(row, confirm_button, cancel_button, [])
	row.alignment = BoxContainer.ALIGNMENT_END
	confirm_button.pressed.connect(confirm)
	cancel_button.pressed.connect(cancel)
	set_key(false, Color.MAGENTA)


func _ready() -> void:
	SpinScroll.enable(tolerance_field)


func is_on() -> bool:
	return enabled_check.button_pressed


func get_color() -> Color:
	return swatch.color


## How different a pixel can be from the colour, from 0 to 1, see [method ImageUtils.color_key]
func get_tolerance() -> float:
	return tolerance_field.value / 100.0


## Shows [param color] with [param tolerance] (0 to 1), made transparent when [param on],
## without [signal changed]
func set_key(on: bool, color: Color, tolerance := SheetBackground.DEFAULT_TOLERANCE) -> void:
	enabled_check.set_pressed_no_signal(on)
	swatch.color = Color(color, 1.0)
	tolerance_field.set_value_no_signal(roundf(tolerance * 100.0))
	update_text()
	_update_state()


## Whether something changed since it opened
func has_changed() -> bool:
	return _opened_with != [is_on(), get_color(), get_tolerance()]


func is_open() -> bool:
	return popup.visible


func is_picking() -> bool:
	return eyedropper.button_pressed


## Turns the eyedropper on or off, with [signal picking_changed]
func set_picking(on: bool) -> void:
	eyedropper.button_pressed = on


## Makes [param color] transparent, as picked with the eyedropper, and puts the eyedropper
## away. Transparent pixels have no colour to pick, so the eyedropper stays out for another
## click.
func pick(color: Color) -> void:
	if color.a <= 0.0:
		return
	set_key(true, color, get_tolerance())
	set_picking(false)
	changed.emit()


## Lets the eyedropper pick colours by clicking [param view], which has a
## [code]picking[/code] property and a [code]color_picked[/code] signal, like
## [SpritesheetPreview]. Clicks in [param area], in this button's window, go to the view
## while picking, rather than closing the panel.
func add_picker(view: CanvasItem, area: Control) -> void:
	picking_changed.connect(func(on: bool) -> void: view.set(&"picking", on))
	view.connect(&"color_picked", pick)
	_pick_areas.append(area)


## Lets clicks in [param area], in this button's window, through to what's under it while
## the panel is open, like selecting frames in a preview, rather than closing the panel.
## Right-clicks still close it: they open menus.
func let_clicks_through(area: Control) -> void:
	_open_areas.append(area)


## Opens the panel below the button, or closes it as Cancel does when it's open
func open() -> void:
	if is_open():
		cancel()
		return
	opening.emit()
	_opened_with = [is_on(), get_color(), get_tolerance()]
	super()


## Keeps what's set, remembering the tolerance for next time, and closes the panel
func confirm() -> void:
	Settings.set_value(&"background_tolerance", get_tolerance())
	_close()
	confirmed.emit()


## Puts back what was set when it opened, and closes the panel
func cancel() -> void:
	if not _opened_with.is_empty():
		set_key(_opened_with[0], _opened_with[1], _opened_with[2])
	_close()
	canceled.emit()


func _close() -> void:
	_closing = true
	set_picking(false)
	popup.hide()
	_closing = false
	queue_redraw()


## Gone some other way, like its window closing
func _on_popup_hide() -> void:
	if not _closing:
		cancel()


## Clicks outside the panel close it, as Cancel does, and are kept from what's under them,
## like a popup's, unless let through, see [method let_clicks_through]. While picking,
## clicks on a preview pick instead. Escape puts the eyedropper away, or cancels.
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var click := event as InputEventMouseButton
	# The wheel scrolls and zooms what's under the mouse, as with popups
	if click and click.pressed and click.button_index in CLICKS:
		if is_picking() and _is_in(_pick_areas, click.position):
			return
		if click.button_index != MOUSE_BUTTON_RIGHT and _is_in(_open_areas, click.position):
			return
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		_escape()
		get_viewport().set_input_as_handled()


## Whether [param point] is in one of [param areas], shown
static func _is_in(areas: Array[Control], point: Vector2) -> bool:
	for area in areas:
		if area.is_visible_in_tree() and area.get_global_rect().has_point(point):
			return true
	return false


## Keys pressed in the panel, while it has the focus
func _on_popup_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		_escape()
		popup.set_input_as_handled()


func _escape() -> void:
	if is_picking():
		set_picking(false)
	else:
		cancel()


## The colour and the tolerance only matter when the colour is made transparent
func _update_state() -> void:
	tolerance_field.editable = is_on()
	queue_redraw()


## The hex code of the colour, over it, in black or white, whichever shows
func _draw_hex() -> void:
	var font := swatch.get_theme_font(&"font")
	var font_size := swatch.get_theme_font_size(&"font_size")
	var hex := "#" + get_color().to_html(false)
	var ink := Color.BLACK if get_color().get_luminance() > 0.5 else Color.WHITE
	var baseline := (swatch.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2
	swatch.draw_string(
		font,
		Vector2(0, baseline),
		hex,
		HORIZONTAL_ALIGNMENT_CENTER,
		swatch.size.x,
		font_size,
		Color(ink, 0.85 if is_on() else 0.4)
	)


func _draw() -> void:
	if not shows_color or not is_on():
		return
	# Under the icon, like a colour button's
	var width := minf(size.x - 8.0, 16.0)
	var strip := Rect2((size.x - width) / 2, size.y - STRIP_HEIGHT - 2.0, width, STRIP_HEIGHT)
	draw_rect(strip, get_color())
