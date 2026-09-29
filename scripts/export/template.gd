class_name Template
extends RefCounted
## A Mustache-like template, filled with the values of an export (see [TemplateData]) to
## write its data file.
##
## [codeblock lang=text]
## {{name}}                  the value of name; nothing when there's none
## {{frame.x}}               a value inside another
## {{.}}                     the current item, in a section over a list of plain values
## {{name | json-escape}}    the value through filters, left to right; see FILTERS
## {{#name}}...{{/name}}     once for every item of a list, or once when the value is set
## {{^name}}...{{/name}}     once when the value isn't set or is an empty list
## {{! comment}}             left out
## [/codeblock]
## Values that aren't set: nothing, false, an empty text and an empty list; numbers
## always are, 0 too. Inside a section over a list, [code]@index[/code] is the item's
## position from 0 and [code]@first[/code] and [code]@last[/code] say whether it's the
## first or last: [code]{{#frames}}"{{name}}"{{^@last}},{{/@last}}{{/frames}}[/code]
## separates the names with commas. Names are looked up in the item, then in the sections
## around it, then in the values of the whole export.
##
## A line holding nothing but sections, section ends and comments is left out whole, so
## they can go on lines of their own without leaving empty lines. A single line break at
## the very end of the template is left out, so a file can end without one: end the
## template with an empty line for a file that ends with a line break. Values aren't
## escaped unless a filter says so. In a run of braces, a tag starts at the last two
## opening ones and ends at the first two closing ones: [code]{{{#frames}}[/code] is a
## "{" then a section.
##
## A template can start with a comment of [code]key: value[/code] lines saying what it
## writes, up to an empty line, see [member header].

## Filters by name, with how many arguments each takes. An argument is a whole number or
## the name of a value holding one.
const FILTERS := {
	## The value as JSON: text in quotes, numbers as Godot writes them in JSON
	"json": 0,
	## Text escaped for inside quotes in JSON
	"json-escape": 0,
	## Text escaped for XML, quotes too
	"xml-escape": 0,
	## Text as a CSS identifier, escaped where it has to be, like CSS.escape() in browsers:
	## "a&b" gives a\&b, which a selector like .sprite-{{name | css-ident}} can hold
	"css-ident": 0,
	## Text as a .tpsheet sprite name: %, #, : and ; written as %25, %23, %3A and %3B
	"tpsheet-escape": 0,
	"lower": 0,
	"upper": 0,
	## A number with zeros in front up to the given number of digits: {{index | pad 3}}
	"pad": 1,
	## A number plus the argument: {{index | plus 1}}, {{x | plus w}}
	"plus": 1,
	## A number minus the argument: {{image_h | minus y}}
	"minus": 1,
	## A number times the argument: {{row | times columns}}
	"times": 1,
	## A number divided by the argument, always with decimals: {{pivot_px_x | divide w}}
	"divide": 1,
	## A number the other way round: 3 gives -3
	"negate": 0,
	## A number with at most the given number of decimals and no trailing zeros
	"round": 1,
}
## The filters that work on any value; the others take numbers
const TEXT_FILTERS: Array[String] = [
	"json", "json-escape", "xml-escape", "css-ident", "tpsheet-escape", "lower", "upper"
]

## The parts a template is read into
enum Token { TEXT, VARIABLE, SECTION, INVERTED, CLOSE, COMMENT }

## What went wrong reading or filling the template, starting with the line it's on; empty
## when nothing did. Filling sets it again.
var error := ""
## The [code]key: value[/code] lines of the comment the template starts with, if any,
## with "true" and "false" as booleans. Bundled templates say "name", "extension",
## "per_page" (a file for each page of an atlas) and "rotation" (which way turned frames
## are stored: "clockwise", "counter-clockwise" or "none" when the format can't say).
var header := {}

## Text, and dictionaries for tags: [code]{"type": Token, "name": String, "line": int}[/code],
## with "filters" for variables and "children" for sections
var _nodes: Array = []
var _parse_error := ""

static var _name_regex := RegEx.create_from_string(
	"^(\\.|@?[A-Za-z_][A-Za-z0-9_-]*(\\.[A-Za-z0-9_-]+)*)$"
)
static var _number_regex := RegEx.create_from_string("^-?[0-9]+$")


static func parse(text: String) -> Template:
	var template := Template.new()
	template._parse(text)
	return template


## The template in the file at [param path], or one whose [member error] says why it
## couldn't be read
static func load_file(path: String) -> Template:
	if not FileAccess.file_exists(path):
		var missing := Template.new()
		missing._parse_error = "%s not found" % path
		missing.error = missing._parse_error
		return missing
	return parse(FileAccess.get_file_as_string(path))


## The template filled with [param values], usually a dictionary. When something goes
## wrong, [member error] says what and the text is as far as it got.
func render(values: Variant) -> String:
	error = _parse_error
	if error:
		return ""
	var out := PackedStringArray()
	_render_nodes(_nodes, [values], out)
	return "".join(out)


func _parse(text: String) -> void:
	if text.ends_with("\n"):
		text = text.trim_suffix("\n").trim_suffix("\r")
	var tokens := _tokenize(text)
	if _parse_error:
		error = _parse_error
		return
	if tokens and tokens[0].type == Token.COMMENT:
		header = _parse_header(tokens[0].name)
	_remove_standalone_lines(tokens)
	_build_tree(tokens)
	error = _parse_error


## The text split into tags and text that ends at most at one line break
func _tokenize(text: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var position := 0
	var line := 1
	while position < text.length():
		var open := text.find("{{", position)
		if open < 0:
			line = _add_text(tokens, text.substr(position), line)
			break
		while text.substr(open + 2, 1) == "{":
			open += 1
		line = _add_text(tokens, text.substr(position, open - position), line)
		var close := text.find("}}", open + 2)
		if close < 0:
			_fail(line, "{{ without }}")
			return tokens
		var content := text.substr(open + 2, close - open - 2)
		var token := _parse_tag(content, line)
		if _parse_error:
			return tokens
		tokens.append(token)
		line += content.count("\n")
		position = close + 2
	return tokens


func _add_text(tokens: Array[Dictionary], text: String, line: int) -> int:
	var start := 0
	while start < text.length():
		var end := text.find("\n", start)
		end = text.length() if end < 0 else end + 1
		tokens.append({"type": Token.TEXT, "text": text.substr(start, end - start), "line": line})
		if text[end - 1] == "\n":
			line += 1
		start = end
	return line


func _parse_tag(content: String, line: int) -> Dictionary:
	var tag := content.strip_edges()
	var types := {"#": Token.SECTION, "^": Token.INVERTED, "/": Token.CLOSE, "!": Token.COMMENT}
	var type: Token = types.get(tag.left(1), Token.VARIABLE)
	if type == Token.COMMENT:
		return {"type": type, "name": tag.substr(1), "line": line}
	var unsupported := type == Token.VARIABLE and tag.left(1) in [">", "="]
	if type != Token.VARIABLE or tag.begins_with("&"):
		tag = tag.substr(1).strip_edges()
	var parts := tag.split("|")
	var name := parts[0].strip_edges()
	if unsupported:
		_fail(line, "{{%s}} isn't supported" % tag)
	elif not name:
		_fail(line, "{{%s}} has no name" % content)
	elif not _name_regex.search(name):
		_fail(line, '"%s" isn\'t a name' % name)
	elif parts.size() > 1 and type != Token.VARIABLE:
		_fail(line, "{{%s}}: only values take filters, not sections" % content.strip_edges())
	var token := {"type": type, "name": name, "line": line}
	if type == Token.VARIABLE:
		token.filters = []
		for part in parts.slice(1):
			token.filters.append(_parse_filter(part, line))
	return {} if _parse_error else token


## [code]{"name": String, "arguments": Array}[/code] from "pad 3"
func _parse_filter(text: String, line: int) -> Dictionary:
	var words := text.strip_edges().split(" ", false)
	if words.is_empty():
		_fail(line, "empty filter after |")
		return {}
	var filter_name := words[0]
	if not FILTERS.has(filter_name):
		_fail(line, 'unknown filter "%s"' % filter_name)
		return {}
	var arguments := Array(words.slice(1))
	if arguments.size() != FILTERS[filter_name]:
		_fail(
			line,
			(
				"%s takes %d argument(s), not %d"
				% [filter_name, FILTERS[filter_name], arguments.size()]
			)
		)
		return {}
	for argument: String in arguments:
		if not (_number_regex.search(argument) or _name_regex.search(argument)):
			_fail(line, '%s: "%s" is neither a number nor a name' % [filter_name, argument])
			return {}
	return {"name": filter_name, "arguments": arguments}


func _parse_header(comment: String) -> Dictionary:
	var result := {}
	for line in comment.split("\n"):
		# An empty line ends the settings: what follows is for people
		if not line.strip_edges() and result:
			break
		var colon := line.find(":")
		if colon <= 0:
			continue
		var key := line.left(colon).strip_edges()
		var value: Variant = line.substr(colon + 1).strip_edges()
		if value in ["true", "false"]:
			value = value == "true"
		result[key] = value
	return result


## Leaves out the lines that hold only sections, section ends, comments and spaces
func _remove_standalone_lines(tokens: Array[Dictionary]) -> void:
	var start := 0
	for i in tokens.size():
		var token := tokens[i]
		var ends_line: bool = (
			i == tokens.size() - 1 or (token.type == Token.TEXT and token.text.ends_with("\n"))
		)
		if not ends_line:
			continue
		var line := tokens.slice(start, i + 1)
		start = i + 1
		var has_tag := false
		var standalone := true
		for part: Dictionary in line:
			if part.type == Token.VARIABLE:
				standalone = false
			elif part.type == Token.TEXT:
				standalone = standalone and part.text.strip_edges() == ""
			else:
				has_tag = true
		if has_tag and standalone:
			for part: Dictionary in line:
				if part.type == Token.TEXT:
					part.text = ""


func _build_tree(tokens: Array[Dictionary]) -> void:
	var stack: Array[Dictionary] = []
	var children := _nodes
	for token in tokens:
		match token.type:
			Token.TEXT:
				if token.text:
					children.append(token.text)
			Token.VARIABLE:
				children.append(token)
			Token.SECTION, Token.INVERTED:
				token.children = []
				children.append(token)
				stack.append(token)
				children = token.children
			Token.CLOSE:
				if stack.is_empty():
					_fail(token.line, "{{/%s}} closes no section" % token.name)
					return
				var open: Dictionary = stack.pop_back()
				if open.name != token.name:
					_fail(
						token.line,
						(
							"{{/%s}} doesn't close {{%s%s}} from line %d"
							% [
								token.name,
								"#" if open.type == Token.SECTION else "^",
								open.name,
								open.line
							]
						)
					)
					return
				children = stack[-1].children if stack else _nodes
	if stack:
		var open: Dictionary = stack[-1]
		_fail(
			open.line,
			"{{%s%s}} is never closed" % ["#" if open.type == Token.SECTION else "^", open.name]
		)


func _fail(line: int, message: String) -> void:
	if not _parse_error:
		_parse_error = "line %d: %s" % [line, message]


func _render_nodes(nodes: Array, stack: Array, out: PackedStringArray) -> void:
	for node: Variant in nodes:
		if node is String:
			out.append(node)
		elif node.type == Token.VARIABLE:
			var value: Variant = _lookup(node.name, stack)
			for filter: Dictionary in node.filters:
				value = _apply(filter, value, stack, node.line)
			out.append(_to_text(value))
		elif node.type == Token.INVERTED:
			if not _is_set(_lookup(node.name, stack)):
				_render_nodes(node.children, stack, out)
		else:
			_render_section(node, stack, out)


func _render_section(node: Dictionary, stack: Array, out: PackedStringArray) -> void:
	var value: Variant = _lookup(node.name, stack)
	if not _is_set(value):
		return
	if not _is_list(value):
		stack.push_back(value)
		_render_nodes(node.children, stack, out)
		stack.pop_back()
		return
	var items := Array(value)
	for i in items.size():
		stack.push_back({"@index": i, "@first": i == 0, "@last": i == items.size() - 1})
		stack.push_back(items[i])
		_render_nodes(node.children, stack, out)
		stack.pop_back()
		stack.pop_back()


func _lookup(name: String, stack: Array) -> Variant:
	if name == ".":
		return stack[-1]
	var parts := name.split(".")
	var value: Variant = null
	for i in range(stack.size() - 1, -1, -1):
		var scope: Variant = stack[i]
		if scope is Dictionary and scope.has(parts[0]):
			value = scope[parts[0]]
			break
	for part in parts.slice(1):
		if value is Dictionary:
			value = value.get(part)
		elif _is_list(value) and part.is_valid_int() and int(part) < value.size():
			value = value[int(part)]
		else:
			return null
	return value


func _apply(filter: Dictionary, value: Variant, stack: Array, line: int) -> Variant:
	var argument: Variant = null
	if filter.arguments:
		var text: String = filter.arguments[0]
		argument = int(text) if _number_regex.search(text) else _lookup(text, stack)
	if filter.name in TEXT_FILTERS:
		return _apply_text(filter.name, value)
	# The rest work on numbers, and leave out values that aren't set
	if value != null and (not _is_number(value) or (filter.arguments and not _is_number(argument))):
		if not error:
			error = (
				"line %d: %s needs numbers, not %s"
				% [line, filter.name, var_to_str(argument if _is_number(value) else value)]
			)
		return value
	if filter.name == "divide" and value != null and argument == 0:
		if not error:
			error = "line %d: divide by 0" % line
		return null
	return null if value == null else _apply_number(filter.name, value, argument)


static func _apply_text(filter_name: String, value: Variant) -> String:
	var text := _to_text(value)
	match filter_name:
		"json":
			text = JSON.stringify(value)
		"json-escape":
			text = text.json_escape()
		"xml-escape":
			text = text.xml_escape(true)
		"css-ident":
			text = _css_ident(text)
		"tpsheet-escape":
			text = text.replace("%", "%25").replace("#", "%23").replace(":", "%3A")
			text = text.replace(";", "%3B")
		"lower":
			text = text.to_lower()
		"upper":
			text = text.to_upper()
	return text


static func _apply_number(filter_name: String, value: Variant, argument: Variant) -> Variant:
	var result: Variant = value
	match filter_name:
		"pad":
			var digits := str(absi(value)) if value is int else str(absf(value))
			result = ("-" if value < 0 else "") + digits.lpad(argument, "0")
		"plus":
			result = value + argument
		"minus":
			result = value - argument
		"times":
			result = value * argument
		"divide":
			result = float(value) / argument
		"negate":
			result = -value
		"round":
			if is_equal_approx(value, roundf(value)):
				result = roundi(value)
			else:
				result = String.num(value, argument)
	return result


## [param text] as a CSS identifier, the way CSS.escape() serializes one
static func _css_ident(text: String) -> String:
	var out := PackedStringArray()
	for i in text.length():
		var code := text.unicode_at(i)
		var c := text[i]
		var digit := code >= 0x30 and code <= 0x39
		var letter := (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A)
		if code == 0:
			out.append(char(0xFFFD))
		elif (
			(code >= 0x01 and code <= 0x1F)
			or code == 0x7F
			or (i == 0 and digit)
			or (i == 1 and digit and text[0] == "-")
		):
			# A code point escape ends at a space, so a letter or digit after it isn't read too
			out.append("\\%x " % code)
		elif i == 0 and c == "-" and text.length() == 1:
			out.append("\\-")
		elif code >= 0x80 or c in ["-", "_"] or digit or letter:
			out.append(c)
		else:
			out.append("\\" + c)
	return "".join(out)


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_list(value: Variant) -> bool:
	return (
		value is Array
		or (typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY)
	)


## Whether a section shows: not for nothing, false, empty text and empty lists
static func _is_set(value: Variant) -> bool:
	if value == null or (value is bool and not value):
		return false
	if value is String or value is StringName or value is Dictionary or _is_list(value):
		return not value.is_empty()
	return true


static func _to_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is String:
		return value
	if value is Array or value is Dictionary or _is_list(value):
		return JSON.stringify(value)
	return str(value)
