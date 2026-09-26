class_name HistoryPanel
extends PanelContainer
## Lists every undoable step. Clicking one undoes or redoes up to it; steps that were
## undone are dimmed until a new edit replaces them.

var list := ItemList.new()
var close_button := Button.new()


func _init() -> void:
	theme_type_variation = &"SidebarPanel"
	custom_minimum_size = Vector2(200, 0)
	var box := VBoxContainer.new()
	add_child(box)

	var header := HBoxContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_child(header)
	box.add_child(margin)
	var title := Label.new()
	title.text = "History"
	title.theme_type_variation = &"HeaderSmall"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_button.flat = true
	close_button.icon = preload("res://assets/icons/Close.svg")
	close_button.tooltip_text = "Hide the history (Ctrl+H)"
	header.add_child(close_button)

	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 13)
	list.tooltip_text = "Click a step to go back or forward to it"
	box.add_child(list)


func _ready() -> void:
	# Only clicks: the wheel scrolls
	list.item_clicked.connect(
		func(index: int, _at: Vector2, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				Global.document.go_to_history(index)
	)
	close_button.pressed.connect(func() -> void: Settings.set_value(&"show_history", false))
	Global.document.changed.connect(refresh)
	visibility_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not visible:
		return
	var document := Global.document
	var steps := document.get_history()
	var current := document.get_history_position()
	list.clear()
	list.add_item(tr(document.history_start))
	for step in steps:
		list.add_item(tr(step))
	var muted := get_theme_color("font_color", &"StatusLabel")
	for i in range(current + 1, list.item_count):
		list.set_item_custom_fg_color(i, Color(muted, 0.6))
	list.select(current)
	list.ensure_current_is_visible()
