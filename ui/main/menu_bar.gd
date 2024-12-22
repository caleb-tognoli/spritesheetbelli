extends Control


@onready var file_menu: PopupMenu = %FileMenuButton.get_popup()
@onready var file_new_index: int = file_menu.get_item_index(0)
@onready var file_open_index: int = file_menu.get_item_index(1)
@onready var file_save_index: int = file_menu.get_item_index(10)
@onready var file_save_as_index: int = file_menu.get_item_index(11)
@onready var file_export_sprites_index: int = file_menu.get_item_index(12)


func _ready() -> void:
	file_menu.index_pressed.connect(file_menu_index_pressed)
	
	Global.spritesheet.updated.connect(disable_items_on_spritesheet_update)
	disable_items_on_spritesheet_update()
	
	var file_new_shortcut: Shortcut = Shortcut.new()
	var file_new_shortcut_event: InputEventAction = InputEventAction.new()
	file_new_shortcut_event.action = "new"
	file_new_shortcut.events.append(file_new_shortcut_event)
	file_menu.set_item_shortcut(file_new_index, file_new_shortcut)
	
	var file_open_shortcut: Shortcut = Shortcut.new()
	var file_open_shortcut_event: InputEventAction = InputEventAction.new()
	file_open_shortcut_event.action = "open"
	file_open_shortcut.events.append(file_open_shortcut_event)
	file_menu.set_item_shortcut(file_open_index, file_open_shortcut)
	
	var file_save_shortcut: Shortcut = Shortcut.new()
	var file_save_shortcut_event: InputEventAction = InputEventAction.new()
	file_save_shortcut_event.action = "save"
	file_save_shortcut.events.append(file_save_shortcut_event)
	file_menu.set_item_shortcut(file_save_index, file_save_shortcut)
	
	var file_save_as_shortcut: Shortcut = Shortcut.new()
	var file_save_as_shortcut_event: InputEventAction = InputEventAction.new()
	file_save_as_shortcut_event.action = "save_as"
	file_save_as_shortcut.events.append(file_save_as_shortcut_event)
	file_menu.set_item_shortcut(file_save_as_index, file_save_as_shortcut)


func disable_items_on_spritesheet_update() -> void:
	var is_empty := Global.spritesheet.is_empty()
	file_menu.set_item_disabled(file_save_index, is_empty)
	file_menu.set_item_disabled(file_save_as_index, is_empty)
	file_menu.set_item_disabled(file_export_sprites_index, is_empty)


func file_menu_index_pressed(index: int) -> void:
	match index:
		file_new_index: 
			owner.new_spritesheet()
		file_open_index:
			owner.open_spritesheet()
		file_save_index: 
			if Global.filepath.is_empty():
				owner.save_spritesheet_dialog.popup()
			else:
				owner.save_spritesheet(Global.filepath)
		file_save_as_index: 
			owner.save_spritesheet_dialog.popup()
		file_export_sprites_index: 
			owner.save_sprites_dialog.popup()
