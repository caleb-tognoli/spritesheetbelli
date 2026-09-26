class_name ActionPopupMenu
extends PopupMenu
## A PopupMenu whose items are [code]Actions[/code], kept in sync with their state.
## An empty id adds a separator. Submenus of actions work the same way. Actions that aren't
## available are left out, and the menu is built again when that changes.

## Submenus made by [method set_actions], freed when it's called again
var _action_submenus: Array[ActionPopupMenu] = []
## What the menu was made from, and the ids shown, to tell when to make it again
var _ids: Array[StringName] = []
var _submenus := {}
var _shown: Array[StringName] = []


func _ready() -> void:
	index_pressed.connect(_on_index_pressed)
	about_to_popup.connect(update_items)
	Actions.state_changed.connect(update_items)


## Fills the menu. [param submenus] maps ids to [code][label, content, icon][/code]
## shown as submenus when hovered: the content is a PopupMenu, or the action ids of a
## menu like this one. The icon can be left out.
func set_actions(ids: Array[StringName], submenus := {}) -> void:
	clear()
	for child in _action_submenus:
		child.queue_free()
	_action_submenus.clear()
	_ids = ids.duplicate()
	_submenus = submenus
	_shown = _available(ids, submenus)
	for id in _shown:
		if id.is_empty():
			add_separator()
			continue
		if submenus.has(id):
			_add_submenu(submenus[id], submenus)
			continue
		var action: AppAction = Actions.get_action(id)
		if action == null:
			push_warning("Unknown action: %s" % id)
			continue
		var index := item_count
		if Actions.is_toggle(id):
			add_check_item(action.label)
		else:
			add_item(action.label)
		if action.icon:
			set_item_icon(index, action.icon)
			set_item_icon_modulate(index, _icon_modulate())
		set_item_metadata(index, id)
		var shortcut := Actions.get_shortcut(id)
		if shortcut:
			set_item_shortcut(index, shortcut)
	update_items()


func _add_submenu(entry: Array, submenus: Dictionary) -> void:
	var submenu: PopupMenu
	if entry[1] is PopupMenu:
		submenu = entry[1]
		if not submenu.get_parent():
			add_child(submenu)
	else:
		var actions := ActionPopupMenu.new()
		actions.theme = theme
		add_child(actions)
		var sub_ids: Array[StringName] = []
		sub_ids.assign(entry[1])
		actions.set_actions(sub_ids, submenus)
		_action_submenus.append(actions)
		submenu = actions
	var index := item_count
	add_submenu_node_item(entry[0], submenu)
	if entry.size() > 2 and entry[2] is Texture2D:
		set_item_icon(index, entry[2])
		set_item_icon_modulate(index, _icon_modulate())


## Icons are light grey; tinting them like the text keeps them visible on light themes
func _icon_modulate() -> Color:
	var text := get_theme_color("font_color")
	return Color(minf(text.r / 0.88, 1), minf(text.g / 0.88, 1), minf(text.b / 0.88, 1))


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		for i in item_count:
			if get_item_icon(i):
				set_item_icon_modulate(i, _icon_modulate())


## The ids to show: available actions, and submenus with any, without separators that
## would have nothing on one side
func _available(ids: Array[StringName], submenus: Dictionary) -> Array[StringName]:
	var shown: Array[StringName] = []
	for id in ids:
		if id.is_empty():
			if not shown.is_empty() and not shown[-1].is_empty():
				shown.append(id)
		elif submenus.has(id):
			var entry: Array = submenus[id]
			if not entry[1] is Array or _any_available(entry[1]):
				shown.append(id)
		elif Actions.is_available(id) or not Actions.has(id):
			shown.append(id)
	if not shown.is_empty() and shown[-1].is_empty():
		shown.pop_back()
	return shown


static func _any_available(ids: Array) -> bool:
	for id: StringName in ids:
		if not id.is_empty() and Actions.is_available(id):
			return true
	return false


## Refreshes enabled and checked states, and makes the menu again when other actions are
## available
func update_items() -> void:
	if not _ids.is_empty() and _available(_ids, _submenus) != _shown:
		set_actions(_ids, _submenus)
		return
	for i in item_count:
		var id: Variant = get_item_metadata(i)
		if id is StringName:
			set_item_disabled(i, not Actions.is_enabled(id))
			if is_item_checkable(i):
				set_item_checked(i, Actions.is_checked(id))


func _on_index_pressed(index: int) -> void:
	var id: Variant = get_item_metadata(index)
	if id is StringName:
		Actions.run(id)
