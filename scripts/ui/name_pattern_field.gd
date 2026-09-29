class_name NamePatternField
extends VBoxContainer
## A field for a name pattern (see [method SpritesheetExporter.format_sprite_name]) with a
## Tokens… button next to it, which lists every token with what it gives for a frame of
## the open sheet, to insert one at the caret. A warning under it names unknown tokens.
## Patterns of other names, like those of [AnimationFiles], have tokens of their own, see
## [method use_tokens].

signal text_changed(new_text: String)

## The tokens of the pattern, with what they give
var known_tokens: Dictionary = SpritesheetExporter.SPRITE_NAME_TOKENS
## Returns what each token gives for an example from the open sheet, by token name
var get_example_values := _sprite_example_values

## The field and the button, above [member warning]
var field_row := HBoxContainer.new()
var line_edit := LineEdit.new()
var tokens_button := Button.new()
var warning := Label.new()
var popup := PopupPanel.new()
## The token list in [member popup]: a button to insert each, what it gives, an example
var tokens := GridContainer.new()
## Says under [member tokens] how to pad numbers
var padding_hint := Label.new()

var text: String:
	get:
		return line_edit.text
	set(value):
		line_edit.text = value
		_update_warning()


func _init() -> void:
	add_theme_constant_override("separation", 4)
	add_child(field_row)
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_row.add_child(line_edit)
	tokens_button.text = "Tokens…"
	tokens_button.tooltip_text = "The tokens a name can have, to insert one"
	field_row.add_child(tokens_button)
	warning.theme_type_variation = &"ErrorLabel"
	warning.hide()
	add_child(warning)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	tokens.columns = 3
	tokens.add_theme_constant_override("h_separation", 12)
	tokens.add_theme_constant_override("v_separation", 2)
	content.add_child(tokens)
	_set_padding_hint("index")
	padding_hint.theme_type_variation = &"StatusLabel"
	content.add_child(padding_hint)
	popup.add_child(content)
	add_child(popup)

	line_edit.text_changed.connect(_on_text_changed)
	tokens_button.pressed.connect(open_tokens)


## Makes the pattern one of [param tokens_given] (each with what it gives), with examples
## from [param example_values] (see [member get_example_values]) and [param number_token]
## in the hint about padding numbers
func use_tokens(tokens_given: Dictionary, example_values: Callable, number_token: String) -> void:
	known_tokens = tokens_given
	get_example_values = example_values
	_set_padding_hint(number_token)
	_update_warning()


func _set_padding_hint(number_token: String) -> void:
	padding_hint.text = tr("Add :3 to pad numbers with zeros: {%s:3} gives 007") % number_token


## Opens the token list below the button, with examples from the open sheet: for sprite
## names, its first frame, or the first in an animation
func open_tokens() -> void:
	var values: Dictionary = get_example_values.call()
	for child in tokens.get_children():
		tokens.remove_child(child)
		child.queue_free()
	for token: String in known_tokens:
		var button := Button.new()
		button.text = "{%s}" % token
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(insert_token.bind(token))
		tokens.add_child(button)
		var about := Label.new()
		about.text = known_tokens[token]
		tokens.add_child(about)
		var example := Label.new()
		example.text = str(values.get(token, ""))
		example.theme_type_variation = &"StatusLabel"
		tokens.add_child(example)
	var below := tokens_button.get_screen_transform() * Rect2(0, tokens_button.size.y + 4, 0, 0)
	popup.reset_size()
	popup.popup(Rect2i(below))


## Inserts [code]{token}[/code] at the caret, in place of the selected text
func insert_token(token: String) -> void:
	popup.hide()
	if line_edit.has_selection():
		var from := line_edit.get_selection_from_column()
		line_edit.delete_text(from, line_edit.get_selection_to_column())
		line_edit.caret_column = from
	line_edit.insert_text_at_caret("{%s}" % token)
	line_edit.grab_focus()
	_on_text_changed(line_edit.text)


func _on_text_changed(new_text: String) -> void:
	_update_warning()
	text_changed.emit(new_text)


func _update_warning() -> void:
	var unknown := SpritesheetExporter.get_unknown_tokens(line_edit.text, known_tokens)
	warning.visible = not unknown.is_empty()
	if unknown.size() == 1:
		warning.text = tr("Unknown token: %s") % unknown[0]
	elif unknown:
		warning.text = tr("Unknown tokens: %s") % ", ".join(unknown)


## What each sprite name token gives for the open sheet's first frame, or the first in an
## animation
static func _sprite_example_values() -> Dictionary:
	var sheet := Global.spritesheet
	var examples := SpritesheetExporter.get_example_coords(sheet, 1)
	if examples.is_empty():
		return {}
	var index_start: int = Settings.get_value(&"index_start")
	return SpritesheetExporter.get_sprite_name_values(sheet, examples[0], index_start)
