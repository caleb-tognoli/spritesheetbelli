class_name RecentFilesMenu
extends PopupMenu
## Lists recently opened and saved files. Picking one emits [signal file_chosen].

signal file_chosen(path: String)

const CLEAR_ID := 1000


func _ready() -> void:
	about_to_popup.connect(refresh)
	id_pressed.connect(_on_id_pressed)
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"recent_files":
				refresh()
	)
	refresh()


func refresh() -> void:
	clear()
	var files := Settings.get_recent_files()
	for i in files.size():
		add_item("%s  (%s)" % [files[i].get_file(), files[i].get_base_dir()], i)
		set_item_disabled(i, not FileAccess.file_exists(files[i]))
	if files.is_empty():
		add_item("No recent files")
		set_item_disabled(0, true)
	else:
		add_separator()
		add_item("Clear Recent Files", CLEAR_ID)


func _on_id_pressed(id: int) -> void:
	if id == CLEAR_ID:
		Settings.clear_recent_files()
		return
	var files := Settings.get_recent_files()
	if id < files.size():
		file_chosen.emit(files[id])
