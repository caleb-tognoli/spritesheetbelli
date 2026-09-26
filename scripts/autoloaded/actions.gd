extends Node
## Every user command, shared by menus, buttons and shortcuts.
## An action's shortcut is the Input Map action with the same name (Project Settings > Input Map).

## Emitted when enabled or checked states may have changed
signal state_changed

var _actions: Dictionary[StringName, AppAction] = {}
var _refresh_queued := false


func _ready() -> void:
	Global.spritesheet.updated.connect(refresh)
	Global.document.changed.connect(refresh)
	# Toggles can follow settings
	Settings.changed.connect(refresh.unbind(1))


func add(
	id: StringName,
	label: String,
	on_run: Callable,
	can_run := Callable(),
	icon: Texture2D = null,
	checked := Callable(),
	available := Callable(),
) -> AppAction:
	var action := AppAction.new()
	action.id = id
	action.label = label
	action.run = on_run
	action.can_run = can_run
	action.icon = icon
	action.is_checked = checked
	action.is_available = available
	_actions[id] = action
	refresh()
	return action


func remove(id: StringName) -> void:
	_actions.erase(id)


func has(id: StringName) -> bool:
	return _actions.has(id)


func get_action(id: StringName) -> AppAction:
	return _actions.get(id)


func get_ids() -> Array[StringName]:
	return _actions.keys()


func is_enabled(id: StringName) -> bool:
	var action: AppAction = _actions.get(id)
	return (
		is_available(id)
		and action != null
		and (not action.can_run.is_valid() or action.can_run.call())
	)


## Whether the action belongs in menus and toolbars right now, see [member AppAction.is_available]
func is_available(id: StringName) -> bool:
	var action: AppAction = _actions.get(id)
	return action != null and (not action.is_available.is_valid() or action.is_available.call())


func is_toggle(id: StringName) -> bool:
	var action: AppAction = _actions.get(id)
	return action != null and action.is_checked.is_valid()


func is_checked(id: StringName) -> bool:
	return is_toggle(id) and _actions[id].is_checked.call()


## Runs the action if it's enabled. Returns whether it ran.
func run(id: StringName) -> bool:
	if not is_enabled(id):
		return false
	_actions[id].run.call()
	refresh()
	return true


func get_shortcut(id: StringName) -> Shortcut:
	if not InputMap.has_action(id):
		return null
	var event := InputEventAction.new()
	event.action = id
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	return shortcut


## The first key of the action's shortcut, e.g. "Ctrl+Shift+S"
func get_shortcut_text(id: StringName) -> String:
	if not InputMap.has_action(id):
		return ""
	for event in InputMap.action_get_events(id):
		if event is InputEventKey:
			return event.as_text().replace(" (Physical)", "")
	return ""


## Notifies menus and buttons that enabled states may have changed. Coalesced per frame.
func refresh() -> void:
	if not is_queued_for_deletion() and not _refresh_queued:
		_refresh_queued = true
		_emit_state_changed.call_deferred()


func _emit_state_changed() -> void:
	_refresh_queued = false
	state_changed.emit()
