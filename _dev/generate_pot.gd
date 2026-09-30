extends SceneTree
## Writes the template translations start from, translations/spritesheetbelli.pot, with the
## text of every file listed in Project Settings > Localization > POT Generation
## ([code]internationalization/locale/translations_pot_files[/code]).
## Usage: godot --headless --path . -s res://_dev/generate_pot.gd
##
## Godot's own Generate POT needs the editor, and misses text that's translated when it's
## shown rather than where it's written. This picks up:
## [br]- the text of [method Object.tr], [method Object.tr_n], [method Object.atr],
## [method Object.atr_n], [method TranslationServer.translate] and
## [method TranslationServer.translate_plural], with its context when it has one
## [br]- text marked with [method L10n.mark], which is translated later, when it's shown,
## and every string of a constant marked with the comment [code]# L10n.mark[/code], after
## its first line or on a line of its own right before it (or its documentation): ids in
## it are StringNames, paths aren't picked up, and of file dialog filters like
## [code]"*.png ; Images"[/code] only what comes after the ;
## [br]- like Godot's own, text set as a control's [code]text[/code], tooltip or title,
## or added as an item to a menu, list or tab bar, which the control translates itself
## [br]- in scenes, the same properties of the nodes that are translated
## [br]Only literal text is picked up, also when split in parts joined with +.

const POT_PATH := "res://translations/spritesheetbelli.pot"
const SETTING := "internationalization/locale/translations_pot_files"
## Marks every string of a constant, for text translated where it's shown
const CONST_TAG := "# L10n.mark"
## Calls whose first argument is the text, and the second its context
const CALLS: Array[String] = ["tr", "atr", "TranslationServer.translate", "L10n.mark"]
## Calls whose first two arguments are the singular and plural text, and the fourth the
## context
const PLURAL_CALLS: Array[String] = ["tr_n", "atr_n", "TranslationServer.translate_plural"]
## Properties that controls translate themselves
const PROPERTIES: Array[String] = [
	"text",
	"tooltip_text",
	"placeholder_text",
	"title",
	"ok_button_text",
	"cancel_button_text",
	"dialog_text",
]
## Methods that add or set text that controls translate themselves, as their first argument
const FIRST_ARG_METHODS: Array[String] = [
	"add_item",
	"add_check_item",
	"add_radio_check_item",
	"add_submenu_item",
	"add_submenu_node_item",
	"add_separator",
	"add_button",
	"add_cancel_button",
	"add_tab",
]
## Methods like the above whose text is their second argument, after an index or icon
const SECOND_ARG_METHODS: Array[String] = [
	"set_item_text",
	"set_item_tooltip",
	"add_icon_item",
	"add_icon_check_item",
	"add_icon_radio_check_item",
	"set_tab_title",
	"set_tab_tooltip",
	"set_tooltip_text",
]
## Scene properties that nodes translate: the above, and the items of menus and lists
const SCENE_PROPERTY := (
	"^(text|tooltip_text|placeholder_text|title|ok_button_text|cancel_button_text"
	+ "|dialog_text|(popup/)?item_\\d+/text)$"
)


func _init() -> void:
	var files: PackedStringArray = ProjectSettings.get_setting(SETTING, PackedStringArray())
	var pot := generate(files)
	DirAccess.make_dir_recursive_absolute(POT_PATH.get_base_dir())
	var file := FileAccess.open(POT_PATH, FileAccess.WRITE)
	file.store_string(pot)
	file.close()
	var count := pot.count("\nmsgid ") - 1
	print("Wrote %s: %d messages from %d files" % [POT_PATH, count, files.size()])
	quit()


## The POT file for [param files], .gd scripts and .tscn scenes
static func generate(files: PackedStringArray) -> String:
	# Messages by context and text, in the order they're first found
	var messages := {}
	for path in files:
		for message in extract(path):
			var key := "%s\u0004%s" % [message.context, message.msgid]
			if not messages.has(key):
				message.files = PackedStringArray()
				messages[key] = message
			var existing: Dictionary = messages[key]
			if path not in existing.files:
				existing.files.append(path)
			if message.plural and not existing.plural:
				existing.plural = message.plural

	var lines: PackedStringArray = [
		"# Template for translations of spritesheetbelli.",
		"# Made by _dev/generate_pot.gd from the files in Project Settings > Localization.",
		"#",
		"#, fuzzy",
		'msgid ""',
		'msgstr ""',
		'"Project-Id-Version: spritesheetbelli\\n"',
		'"MIME-Version: 1.0\\n"',
		'"Content-Type: text/plain; charset=UTF-8\\n"',
		'"Content-Transfer-Encoding: 8-bit\\n"',
	]
	for message: Dictionary in messages.values():
		lines.append("")
		for path: String in message.files:
			lines.append("#: " + path)
		if message.context:
			lines.append("msgctxt " + _po_string(message.context))
		lines.append("msgid " + _po_string(message.msgid))
		if message.plural:
			lines.append("msgid_plural " + _po_string(message.plural))
			lines.append('msgstr[0] ""')
			lines.append('msgstr[1] ""')
		else:
			lines.append('msgstr ""')
	return "\n".join(lines) + "\n"


## The messages of the script or scene at [param path]: [code]{msgid, plural, context}[/code]
static func extract(path: String) -> Array[Dictionary]:
	# Checked out with Windows line breaks, text on several lines would have them
	var source := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	return extract_scene(source) if path.ends_with(".tscn") else extract_script(source)


## The messages of a GDScript [param source]
static func extract_script(source: String) -> Array[Dictionary]:
	var tokens := _tokenize(source.replace("\r\n", "\n"))
	var messages: Array[Dictionary] = []
	for i in tokens.size():
		var token: Dictionary = tokens[i]
		if token.type != "name":
			continue
		var method: String = token.value
		if method == "const":
			_extract_tagged_const(tokens, i, messages)
			continue
		# With what it's called on, for qualified names like TranslationServer.translate
		var name := method
		if i >= 2 and tokens[i - 1].value == "." and tokens[i - 2].type == "name":
			name = tokens[i - 2].value + "." + method
		var is_call: bool = i + 1 < tokens.size() and tokens[i + 1].value == "("
		if is_call and (name in PLURAL_CALLS or method in ["tr_n", "atr_n"]):
			_extract_plural(tokens, i + 2, messages)
		elif is_call and (name in CALLS or method in ["tr", "atr"]):
			_extract_call(tokens, i + 2, 0, messages)
		elif is_call and method in FIRST_ARG_METHODS:
			_extract_call(tokens, i + 2, 0, messages, false)
		elif is_call and method in SECOND_ARG_METHODS:
			_extract_call(tokens, i + 2, 1, messages, false)
		elif (
			token.value in PROPERTIES
			and i + 1 < tokens.size()
			and tokens[i + 1].value == "="
			# Not a local variable
			and not (i > 0 and tokens[i - 1].value == "var")
		):
			_extract_assignment(tokens, i + 2, messages)
	return messages


## The messages of a scene's [param source]: the text properties of the nodes that are
## translated
static func extract_scene(source: String) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	var property := RegEx.create_from_string(SCENE_PROPERTY)
	var translated := true
	var pending: Array[String] = []
	for line in source.replace("\r\n", "\n").split("\n") + PackedStringArray(["["]):
		if line.begins_with("["):
			if translated:
				for text in pending:
					messages.append({"msgid": text, "plural": "", "context": ""})
			pending.clear()
			translated = true
			continue
		var equals := line.find(" = ")
		if equals < 0:
			continue
		var key := line.left(equals)
		var value := line.substr(equals + 3)
		if key == "auto_translate_mode" and value == "2":
			translated = false
		elif property.search(key) and value.begins_with('"') and value.ends_with('"'):
			var text := value.substr(1, value.length() - 2).c_unescape()
			if _has_letters(text):
				pending.append(text)
	return messages


## Picks up the text of a call's argument number [param index], and the context after it
## when [param with_context], when they're literal. [param start] is the first token after
## the opening parenthesis.
static func _extract_call(
	tokens: Array[Dictionary],
	start: int,
	index: int,
	messages: Array[Dictionary],
	with_context := true
) -> void:
	var args := _literal_args(tokens, start, index + 2)
	if args.size() > index and args[index] != null:
		var context: Variant = args[index + 1] if with_context and args.size() > index + 1 else ""
		_add(messages, args[index], "", context if context != null else "")


static func _extract_plural(
	tokens: Array[Dictionary], start: int, messages: Array[Dictionary]
) -> void:
	var args := _literal_args(tokens, start, 4)
	if args.size() >= 2 and args[0] != null and args[1] != null:
		var context: Variant = args[3] if args.size() > 3 and args[3] != null else ""
		_add(messages, args[0], args[1], context)


## Picks up every string of the constant starting at [param start] when it's marked with
## [constant CONST_TAG]: in a comment of its own right before it (or before its
## documentation), or anywhere in it
static func _extract_tagged_const(
	tokens: Array[Dictionary], start: int, messages: Array[Dictionary]
) -> void:
	var before := start - 1
	while before >= 0 and tokens[before].type == "end":
		before -= 1
	var tagged: bool = before >= 0 and tokens[before].type == "tag"
	var texts: Array[String] = []
	var depth := 0
	var i := start
	while i < tokens.size() and not (tokens[i].type == "end" and depth == 0):
		var token: Dictionary = tokens[i]
		if token.type == "tag":
			tagged = true
		elif token.type == "punct" and token.value in ["(", "[", "{"]:
			depth += 1
		elif token.type == "punct" and token.value in [")", "]", "}"]:
			depth -= 1
		elif token.type == "string" and not token.value.begins_with("res://"):
			var text: String = token.value
			# Joined with + to the next ones
			while true:
				var plus := _skip_lines(tokens, i + 1)
				var part := _skip_lines(tokens, plus + 1)
				if part >= tokens.size() or tokens[plus].value != "+":
					break
				if tokens[plus].type != "punct" or tokens[part].type != "string":
					break
				text += tokens[part].value
				i = part
			# File dialogs translate what their filters say after the patterns
			if text.begins_with("*") and ";" in text:
				text = text.get_slice(";", 1).strip_edges()
			texts.append(text)
		i += 1
	if tagged:
		for text in texts:
			_add(messages, text, "", "")


## Picks up [code]text = "Text"[/code], also both sides of [code]"A" if on else "B"[/code]
static func _extract_assignment(
	tokens: Array[Dictionary], start: int, messages: Array[Dictionary]
) -> void:
	var value := _literal(tokens, start)
	if value.is_empty():
		return
	var next: int = value.end
	# The end of the line, or of a lambda inside a call
	if next >= tokens.size() or tokens[next].type == "end":
		_add(messages, value.text, "", "")
	elif tokens[next].value in [")", "]", "}", ",", ";"]:
		_add(messages, value.text, "", "")
	elif tokens[next].value == "if":
		var j := next
		while j < tokens.size() and tokens[j].type != "end" and tokens[j].value != "else":
			j += 1
		if j < tokens.size() and tokens[j].value == "else":
			var other := _literal(tokens, j + 1)
			if not other.is_empty():
				_add(messages, value.text, "", "")
				_add(messages, other.text, "", "")


## The first [param count] arguments of a call starting at [param start]: their text when
## it's literal, else null
static func _literal_args(tokens: Array[Dictionary], start: int, count: int) -> Array:
	var args := []
	var i := start
	while args.size() < count and i < tokens.size():
		i = _skip_lines(tokens, i)
		var value := _literal(tokens, i)
		if not value.is_empty():
			var after := _skip_lines(tokens, value.end)
			if after < tokens.size() and tokens[after].value in [",", ")"]:
				args.append(value.text)
				if tokens[after].value == ")":
					return args
				i = after + 1
				continue
		args.append(null)
		# Skips to the next argument
		var depth := 0
		while i < tokens.size():
			var t: String = tokens[i].value
			if tokens[i].type == "punct" and t in ["(", "[", "{"]:
				depth += 1
			elif tokens[i].type == "punct" and t in [")", "]", "}"]:
				if depth == 0:
					return args
				depth -= 1
			elif tokens[i].type == "punct" and t == "," and depth == 0:
				break
			i += 1
		i += 1
	return args


## Literal text starting at [param start]: strings joined with +, maybe in parentheses.
## Returns [code]{text, end}[/code] with the index after it, or an empty dictionary.
static func _literal(tokens: Array[Dictionary], start: int) -> Dictionary:
	var i := start
	var open := 0
	while i < tokens.size() and tokens[i].type == "punct" and tokens[i].value == "(":
		open += 1
		i = _skip_lines(tokens, i + 1)
	if i >= tokens.size() or tokens[i].type != "string":
		return {}
	var text: String = tokens[i].value
	i += 1
	while true:
		# Only inside parentheses can the text go on on the next line
		var plus := _skip_lines(tokens, i) if open > 0 else i
		if not (
			plus < tokens.size() and tokens[plus].type == "punct" and tokens[plus].value == "+"
		):
			break
		var part := _skip_lines(tokens, plus + 1)
		if part >= tokens.size() or tokens[part].type != "string":
			break
		text += tokens[part].value
		i = part + 1
	while open > 0:
		i = _skip_lines(tokens, i)
		if i >= tokens.size() or tokens[i].value != ")":
			return {}
		open -= 1
		i += 1
	return {"text": text, "end": i}


## The first token from [param i] that isn't the end of a line
static func _skip_lines(tokens: Array[Dictionary], i: int) -> int:
	while i < tokens.size() and tokens[i].type == "end":
		i += 1
	return i


static func _add(
	messages: Array[Dictionary], msgid: String, plural: String, context: String
) -> void:
	if _has_letters(msgid):
		messages.append({"msgid": msgid, "plural": plural, "context": context})


static func _has_letters(text: String) -> bool:
	for c in text:
		if c.to_lower() != c.to_upper():
			return true
	return false


static func _is_name_char(c: String) -> bool:
	return c == "_" or c.to_lower() != c.to_upper() or (c >= "0" and c <= "9")


## Splits GDScript into names, strings (their text), punctuation, and "end" at the end of
## each line. Comments, StringNames and NodePaths are left out.
static func _tokenize(source: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var i := 0
	var n := source.length()
	while i < n:
		var c := source[i]
		var quoted := i + 1 < n and source[i + 1] in ['"', "'"]
		if c == "#":
			var start := i
			while i < n and source[i] != "\n":
				i += 1
			if source.substr(start, i - start).strip_edges() == CONST_TAG:
				tokens.append({"type": "tag", "value": CONST_TAG})
		elif c == "\n":
			if not tokens.is_empty() and tokens[-1].type != "end":
				tokens.append({"type": "end", "value": "\n"})
			i += 1
		elif c in [" ", "\t", "\r"]:
			i += 1
		elif c in ['"', "'"] or (c in ["&", "^", "r"] and quoted):
			var prefix := "" if c in ['"', "'"] else c
			i += prefix.length()
			var quote := source[i]
			var delimiter := quote.repeat(3) if source.substr(i, 3) == quote.repeat(3) else quote
			i += delimiter.length()
			var start := i
			while i < n and source.substr(i, delimiter.length()) != delimiter:
				i += 2 if source[i] == "\\" and prefix != "r" else 1
			var raw := source.substr(start, i - start)
			i += delimiter.length()
			if prefix in ["&", "^"]:
				tokens.append({"type": "other", "value": raw})
			else:
				var text := raw if prefix == "r" else raw.c_unescape()
				tokens.append({"type": "string", "value": text})
		elif _is_name_char(c):
			var start := i
			while i < n and _is_name_char(source[i]):
				i += 1
			tokens.append({"type": "name", "value": source.substr(start, i - start)})
		else:
			var two := source.substr(i, 2)
			if two in ["==", "!=", "<=", ">=", ":=", "+=", "-=", "*=", "/=", "->", "**", "%="]:
				tokens.append({"type": "punct", "value": two})
				i += 2
			else:
				tokens.append({"type": "punct", "value": c})
				i += 1
	return tokens


## [param text] as a PO string, split after line breaks
static func _po_string(text: String) -> String:
	var escaped := text.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")
	var lines := escaped.split("\n")
	if lines.size() == 1 or (lines.size() == 2 and lines[1].is_empty()):
		return '"%s"' % escaped.replace("\n", "\\n")
	var parts: PackedStringArray = ['""']
	for j in lines.size():
		if j < lines.size() - 1:
			parts.append('"%s\\n"' % lines[j])
		elif lines[j]:
			parts.append('"%s"' % lines[j])
	return "\n".join(parts)
