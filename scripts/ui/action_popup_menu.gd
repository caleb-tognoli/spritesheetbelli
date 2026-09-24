class_name ActionPopupMenu
extends PopupMenu
## A PopupMenu whose items are [code]Actions[/code], kept in sync with their state.
## An empty id adds a separator.


func _ready() -> void:
	index_pressed.connect(_on_index_pressed)
	about_to_popup.connect(update_items)
	Actions.state_changed.connect(update_items)


func set_actions(ids: Array[StringName]) -> void:
	clear()
	for id in ids:
		if id.is_empty():
			add_separator()
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
		set_item_metadata(index, id)
		var shortcut := Actions.get_shortcut(id)
		if shortcut:
			set_item_shortcut(index, shortcut)
	update_items()


## Refreshes enabled and checked states
func update_items() -> void:
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
