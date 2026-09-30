class_name CommandPalette
extends PopupPanel
## Runs any action found by typing part of its name (see [method fuzzy_score]), plays the
## sheet's animations and writes its exports. Opens over the preview, see [method open].
## What it ran last comes first, remembered in the [code]command_palette_recent[/code]
## setting.

## The action that opens it
const ID := &"command_palette"
## How many entries run last are remembered
const MAX_RECENT := 10
## How wide it is at most, and how tall its list, in interface units
const WIDTH := 560
const LIST_HEIGHT := 320
## What a letter scores in [method fuzzy_score]: any, at the start of a word, and next to
## the letter before it
const LETTER_SCORE := 1
const WORD_START_SCORE := 6
const NEXT_LETTER_SCORE := 8
## Added to the score of an entry whose own name matches, rather than its menu
const NAME_SCORE := 4


## Something the palette can run: an action, an animation to play or an export to write
class Entry:
	extends RefCounted
	## Remembered when it runs, see [method get_recent]
	var key: String
	## What the list says, like "Frame › Flip Horizontally"
	var text: String
	## The part of [member text] that names it, like "Flip Horizontally"
	var name: String
	var shortcut: String
	var tooltip: String
	var icon: Texture2D
	var run: Callable
	## Why it can't run, or empty when it can
	var disabled_reason: String


var search := LineEdit.new()
var list := Tree.new()
## Plays animations, see [method play_animation]
var animation_panel: AnimationPanel
## Writes export targets, see [method export_target]
var exports: ExportController
var _no_match := Label.new()
## Every entry when it opened, and those listed, in order
var _entries: Array[Entry] = []
var _shown: Array[Entry] = []


func _init() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	search.placeholder_text = "Search actions, animations and exports"
	search.right_icon = preload("res://assets/icons/Search.svg")
	search.keep_editing_on_text_submit = true
	box.add_child(search)
	list.columns = 2
	# Entries are translated when listed, and have names of animations and exports
	list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	list.hide_root = true
	list.select_mode = Tree.SELECT_ROW
	list.focus_mode = Control.FOCUS_NONE
	list.scroll_horizontal_enabled = false
	list.set_column_expand(0, true)
	list.set_column_expand(1, false)
	list.set_column_custom_minimum_width(1, 150)
	list.add_theme_constant_override(&"draw_guides", 0)
	list.custom_minimum_size.y = LIST_HEIGHT
	box.add_child(list)
	_no_match.text = "Nothing matches"
	_no_match.theme_type_variation = &"StatusLabel"
	_no_match.hide()
	box.add_child(_no_match)
	add_child(box)
	search.text_changed.connect(filter.unbind(1))
	search.text_submitted.connect(run_selected.unbind(1))
	search.gui_input.connect(_on_search_input)
	list.item_mouse_selected.connect(
		func(_position: Vector2, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				run_selected()
	)


func _ready() -> void:
	if WebFiles.is_web():
		use_other_key()


## Browsers keep Ctrl+Shift+P for themselves (Firefox opens a private window with it), so
## there the palette's shortcut is its other key, Ctrl+K, shown first. Calling it again
## puts them back.
static func use_other_key() -> void:
	var events := InputMap.action_get_events(ID)
	if events.size() < 2:
		return
	InputMap.action_erase_events(ID)
	events.push_front(events.pop_back())
	for event in events:
		InputMap.action_add_event(ID, event)


## Opens at the top of [param over], in the middle, with every entry listed
func open(over: Control) -> void:
	_entries = get_entries()
	search.clear()
	filter()
	var width := minf(WIDTH, over.size.x - 32)
	list.custom_minimum_size.x = maxf(width, 240)
	reset_size()
	var top := over.get_screen_transform() * Vector2(over.size.x / 2, 12)
	popup(Rect2i(Vector2i(top) - Vector2i(size.x / 2, 0), size))
	search.grab_focus.call_deferred()


## Every entry: the available actions (in the order of the menus, named after where they
## are in them), then the animations to play and the exports to write
func get_entries() -> Array[Entry]:
	var entries: Array[Entry] = []
	var paths := get_menu_paths()
	var ids: Array[StringName] = []
	ids.assign(paths.keys())
	for id in Actions.get_ids():
		if id not in ids:
			ids.append(id)
	for id in ids:
		if id == ID or not Actions.has(id) or not Actions.is_available(id):
			continue
		var action := Actions.get_action(id)
		var entry := Entry.new()
		entry.key = id
		entry.name = tr(action.label)
		entry.text = "%s › %s" % [paths[id], entry.name] if paths.has(id) else entry.name
		entry.shortcut = Actions.get_shortcut_text(id)
		entry.tooltip = Actions.get_tooltip(id)
		entry.icon = action.icon
		entry.run = Actions.run.bind(id)
		entry.disabled_reason = Actions.get_disabled_reason(id)
		entries.append(entry)
	var sheet := Global.spritesheet
	for i in sheet.animations.size():
		var entry := Entry.new()
		entry.name = sheet.animations[i].name
		entry.key = "play:" + entry.name
		entry.text = tr("Play: %s") % entry.name
		entry.icon = AppTheme.swatch(sheet.animations[i].color)
		entry.run = play_animation.bind(i)
		entries.append(entry)
	for target in ExportTarget.list(sheet):
		var entry := Entry.new()
		entry.name = ExportDialog.describe_target(target)
		entry.key = "export:" + entry.name
		entry.text = tr("Export: %s") % entry.name
		entry.icon = ExportDialog.get_type_icon(target.options.target)
		entry.run = export_target.bind(target)
		entry.disabled_reason = Actions.get_disabled_reason(&"export")
		entries.append(entry)
	return entries


## Where each action is in the main menu, translated, like "Frame › Align in Cell" for Top,
## by id, in the order of the menus
static func get_menu_paths() -> Dictionary:
	var paths := {}
	for menu: String in MainMenuBar.MENUS:
		var menu_name := TranslationServer.translate(menu)
		for id: StringName in MainMenuBar.MENUS[menu]:
			if MainMenuBar.SUBMENUS.has(id):
				var submenu: Array = MainMenuBar.SUBMENUS[id]
				var submenu_name := TranslationServer.translate(submenu[0])
				for inside: StringName in submenu[1]:
					if inside and not paths.has(inside):
						paths[inside] = "%s › %s" % [menu_name, submenu_name]
			elif id and not paths.has(id):
				paths[id] = menu_name
	return paths


## Lists the entries that match the search: those run last first, then the best matches
func filter() -> void:
	var query := search.text.strip_edges()
	_shown = rank(_entries, query, get_recent())
	list.clear()
	var root := list.create_item()
	var muted := get_theme_color(&"font_color", &"StatusLabel")
	var disabled := list.get_theme_color(&"font_disabled_color")
	for i in _shown.size():
		var entry := _shown[i]
		var item := list.create_item(root)
		item.set_text(0, entry.text)
		item.set_icon(0, entry.icon)
		item.set_tooltip_text(0, entry.tooltip)
		item.set_metadata(0, i)
		item.set_text(1, entry.disabled_reason if entry.disabled_reason else entry.shortcut)
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_custom_color(1, muted)
		if entry.disabled_reason:
			item.set_custom_color(0, disabled)
	_no_match.visible = _shown.is_empty()
	list.visible = not _shown.is_empty()
	if not _shown.is_empty():
		select(0)


## [param entries] that match [param query], best first, those whose keys are in
## [param recent] before the others, in its order
static func rank(entries: Array[Entry], query: String, recent: PackedStringArray) -> Array[Entry]:
	var scored: Array[Array] = []
	for i in entries.size():
		var entry := entries[i]
		var score := 0
		if query:
			score = fuzzy_score(query, entry.text)
			if score < 0:
				continue
			var name_score := fuzzy_score(query, entry.name)
			if name_score >= 0:
				score = maxi(score, name_score + NAME_SCORE)
		var recent_index := recent.find(entry.key)
		scored.append([recent_index if recent_index >= 0 else recent.size(), -score, i, entry])
	scored.sort()
	var ranked: Array[Entry] = []
	for item in scored:
		ranked.append(item[3])
	return ranked


## How well [param query] matches [param text]: its letters in the same order, not
## necessarily next to each other, like "flh" in "Flip Horizontally". Spaces and case
## don't matter. Letters starting words and next to each other count more (see
## [constant WORD_START_SCORE]). -1 when it doesn't match.
static func fuzzy_score(query: String, text: String) -> int:
	var wanted := query.to_lower().replace(" ", "")
	var lower := text.to_lower()
	if wanted.is_empty():
		return 0
	# The best score of the letters so far with the last one at each place, -1 for none
	var best := PackedInt32Array()
	best.resize(lower.length())
	for q in wanted.length():
		var next := PackedInt32Array()
		next.resize(lower.length())
		next.fill(-1)
		# The best score of the letters before, ending two places or more before this one
		var best_apart := -1
		for i in lower.length():
			if q > 0 and i >= 2:
				best_apart = maxi(best_apart, best[i - 2])
			if lower[i] != wanted[q]:
				continue
			var from := 0
			if q > 0:
				from = best_apart
				if i >= 1 and best[i - 1] >= 0:
					from = maxi(from, best[i - 1] + NEXT_LETTER_SCORE)
				if from < 0:
					continue
			var starts_word := lower.length() == text.length() and _starts_word(text, i)
			next[i] = from + LETTER_SCORE + (WORD_START_SCORE if starts_word else 0)
		best = next
	var score := -1
	for value in best:
		score = maxi(score, value)
	return score


## Whether the letter at [param index] starts a word
static func _starts_word(text: String, index: int) -> bool:
	if index == 0:
		return true
	var before := text[index - 1]
	if not (before.is_valid_identifier() or before.is_valid_int()):
		return true
	# "S" in "ShowIndices"
	return text[index] != text[index].to_lower() and before == before.to_lower()


## Selects the entry at [param index] and scrolls to it
func select(index: int) -> void:
	var items := list.get_root().get_children() if list.get_root() else []
	if items.is_empty():
		return
	var item: TreeItem = items[clampi(index, 0, items.size() - 1)]
	item.select(0)
	list.scroll_to_item(item)


func get_selected_index() -> int:
	var item := list.get_selected()
	return item.get_metadata(0) if item else -1


## The selected entry, or null
func get_selected() -> Entry:
	var index := get_selected_index()
	return _shown[index] if index >= 0 else null


## Closes and runs the selected entry, unless it can't run. Returns whether it ran.
func run_selected() -> bool:
	var entry := get_selected()
	if entry == null or entry.disabled_reason:
		return false
	hide()
	remember(entry.key)
	entry.run.call()
	return true


## Keys of the entries run last, the latest first
static func get_recent() -> PackedStringArray:
	return PackedStringArray(Settings.get_value(&"command_palette_recent"))


## Puts [param key] first in the entries run last
static func remember(key: String) -> void:
	var recent := get_recent()
	var existing := recent.find(key)
	if existing >= 0:
		recent.remove_at(existing)
	recent.insert(0, key)
	if recent.size() > MAX_RECENT:
		recent.resize(MAX_RECENT)
	Settings.set_value(&"command_palette_recent", Array(recent))


## Opens the animation panel playing the animation at [param index]
func play_animation(index: int) -> void:
	animation_panel.set_expanded(true)
	animation_panel.select_animation(index)


## Writes [param target], or when it doesn't know where to, opens the Export dialog
func export_target(target: ExportTarget) -> void:
	if ExportController.has_place(target):
		exports.export_targets([target] as Array[ExportTarget])
	else:
		exports.open_dialog.call()


func _on_search_input(event: InputEvent) -> void:
	var moves := {&"ui_up": -1, &"ui_down": 1, &"ui_page_up": -10, &"ui_page_down": 10}
	for move: StringName in moves:
		if event.is_action_pressed(move, true, true):
			select(get_selected_index() + moves[move])
			search.accept_event()
			return
