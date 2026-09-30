class_name RecoveryNotice
extends VBoxContainer
## Offers the work left unsaved when spritesheetbelli last closed unexpectedly, on the
## start screen: each copy of [member Recovery.leftovers] with its name, file and time, to
## recover or discard. Hidden while there's none.

const ROW_WIDTH := 560

var recovery: Recovery
var heading := Label.new()
var list := VBoxContainer.new()
## The row of each copy, in the order of [member Recovery.leftovers]
var rows: Array[Control] = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	heading.text = "Recover Unsaved Work"
	heading.theme_type_variation = &"HeaderSmall"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(heading)
	list.add_theme_constant_override("separation", 6)
	add_child(list)


## Lists the copies of [param from], and follows them
func setup(from: Recovery) -> void:
	recovery = from
	recovery.leftovers_changed.connect(refresh)
	refresh()


## Lists the copies again
func refresh() -> void:
	for row in rows:
		row.queue_free()
	rows.clear()
	for leftover in recovery.leftovers:
		var row := _make_row(leftover)
		list.add_child(row)
		rows.append(row)
	visible = not rows.is_empty()


## A copy's name, file and time, with buttons to recover and discard it
func _make_row(leftover: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = ROW_WIDTH
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = _name_of(leftover)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_label)
	var file := Label.new()
	var where: String = leftover.path if leftover.path else tr("Never saved")
	file.text = "%s · %s" % [Recovery.describe_time(leftover.time), where]
	file.theme_type_variation = &"StatusLabel"
	file.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	file.tooltip_text = leftover.path
	file.mouse_filter = Control.MOUSE_FILTER_PASS if leftover.path else Control.MOUSE_FILTER_IGNORE
	text.add_child(file)

	var recover := Button.new()
	recover.text = "Recover"
	recover.tooltip_text = "Open it with its unsaved changes"
	recover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	recover.pressed.connect(
		func() -> void:
			recovery.files.confirm_unsaved_changes(
				"recovering unsaved work", recovery.recover.bind(leftover)
			)
	)
	row.add_child(recover)
	var discard := Button.new()
	discard.text = "Discard"
	discard.tooltip_text = "Delete this copy"
	discard.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	discard.pressed.connect(
		func() -> void:
			Notify.confirm(
				"Discard unsaved work",
				tr("Delete the unsaved changes to %s? This can't be undone.") % _name_of(leftover),
				recovery.discard.bind(leftover),
				"Discard"
			)
	)
	row.add_child(discard)
	return panel


static func _name_of(leftover: Dictionary) -> String:
	return leftover.name if leftover.name else TranslationServer.translate("Untitled")
