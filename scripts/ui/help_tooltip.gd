class_name HelpTooltip
extends Control
## Tooltips like the Godot editor's: an option's name in bold over what it does, wrapped to
## a readable width. [method explain] gives one to an option's label and its controls, so
## hovering any of them explains the option. It works by giving them this script, so it's
## only for controls without one.

## Widest an explanation gets before it wraps
const WIDTH := 360.0
const TITLE_META := &"help_title"


## Explains the option [param title] with [param text] while any of [param controls] is
## hovered. Both are translated when shown.
static func explain(title: String, text: String, controls: Array[Control]) -> void:
	for control in controls:
		control.tooltip_text = text
		control.set_meta(TITLE_META, title)
		if control.get_script() == null:
			control.set_script(HelpTooltip)
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			control.mouse_filter = Control.MOUSE_FILTER_STOP


## What a tooltip shows: [param title] in bold over [param text], as wide as the longest
## line up to [constant WIDTH], in the fonts [param control] would use
static func make(title: String, text: String, control: Control) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bbcode := _escaped(text)
	if title:
		bbcode = "[b]%s[/b]\n%s" % [_escaped(title), bbcode]
	label.text = bbcode
	var font := control.get_theme_font(&"bold_font", &"RichTextLabel")
	var font_size := control.get_theme_font_size(&"bold_font_size", &"RichTextLabel")
	var widest := 0.0
	for line: String in [title] + Array(text.split("\n")):
		widest = maxf(
			widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	label.custom_minimum_size.x = minf(WIDTH, ceilf(widest) + 2.0)
	return label


func _make_custom_tooltip(for_text: String) -> Object:
	return make(atr(get_meta(TITLE_META, "")), for_text, self)


static func _escaped(text: String) -> String:
	return text.replace("[", "[lb]")
