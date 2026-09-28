class_name AnimationCommands
extends Node
## Makes animations quickly from the frames of a row, a column or the selection, asking
## for a name that starts as what the frames' names share. When an animation already has
## exactly those frames, it's renamed instead. Also the actions on the animation chosen
## in the animation panel: mirroring and deleting it, and onion skin. Names animations on
## the grid, see [AnimationLabelControls], and does what their right-click menu asks.
## Rows and columns are the ones of the right-clicked cell for the preview's menu, and of
## the first selected frame otherwise.

const NO_CELL := SpritesheetPreview.NO_CELL
const ICONS := {
	&"mirror_animation": preload("res://assets/icons/MirrorX.svg"),
	&"delete_animation": preload("res://assets/icons/Remove.svg"),
	&"toggle_onion_skin": preload("res://assets/icons/Onion.svg"),
	&"animation_labels": AnimationLabelControls.ICON,
}
## Actions offered when right-clicking frames in the Sprites panel
const SPRITES_CONTEXT_ACTIONS: Array[StringName] = [&"animation_from_selection"]

var main: Control
var dialog := AnimationNameDialog.new()
## The cell right-clicked for the preview's menu while it's open, or [constant NO_CELL]
var menu_cell := NO_CELL
## The frames being named, and the animation that has them or -1 for a new one
var _cells: Array[Vector2i] = []
var _renaming := -1


## Adds the actions and the name dialog to [param main_ui], the main window
func setup(main_ui: Control) -> void:
	main = main_ui
	add_child(dialog)
	dialog.name_chosen.connect(_on_name_chosen)
	var menu: PopupMenu = main.preview_area.options_menu
	menu.about_to_popup.connect(
		func() -> void:
			var cell: Vector2i = main.preview.hovered_cell
			menu_cell = cell if Global.spritesheet.is_inside(cell) else NO_CELL
			Actions.refresh()
	)
	# Deferred, as the menu hides before running the chosen action
	menu.popup_hide.connect(func() -> void: menu_cell = NO_CELL, CONNECT_DEFERRED)
	_register_actions()
	main.layout_controller.sprites_panel.set_context_actions(SPRITES_CONTEXT_ACTIONS)
	_setup_labels()


func _register_actions() -> void:
	var sheet := Global.spritesheet
	var grid := func() -> bool: return sheet.layout == Spritesheet.Layout.GRID
	for line: Array in [
		[&"animation_from_row", "Animation from Row…", false],
		[&"animation_from_column", "Animation from Column…", true],
	]:
		var column: bool = line[2]
		var cells := func() -> Array[Vector2i]: return line_cells(sheet, _target_cell(), column)
		Actions.add(
			line[0],
			line[1],
			func() -> void: name_frames(cells.call()),
			func() -> bool: return not cells.call().is_empty(),
			null,
			Callable(),
			grid
		)
	Actions.add(
		&"animation_from_selection",
		"Animation from Selection…",
		func() -> void: name_frames(main.preview.get_selected_coords()),
		func() -> bool: return not main.preview.get_selected_coords().is_empty()
	)
	# The buttons in the animation panel's details do the same
	var detail: AnimationDetail = main.animation_panel.detail
	var has_current := func() -> bool: return detail.get_animation_index() >= 0
	Actions.add(
		&"mirror_animation",
		"Mirror Animation",
		detail.mirror_animation,
		has_current,
		ICONS[&"mirror_animation"]
	)
	Actions.add(
		&"delete_animation",
		"Delete Animation",
		detail.remove_animation,
		has_current,
		ICONS[&"delete_animation"]
	)
	Actions.add(
		&"animation_labels",
		"Animation Labels…",
		func() -> void: main.preview_area.label_controls.open_flyover(),
		func() -> bool: return not sheet.animations.is_empty(),
		ICONS[&"animation_labels"],
		Callable(),
		grid
	)
	Actions.get_action(&"animation_labels").description = "Name animations on the grid"
	Actions.add(
		&"toggle_onion_skin",
		"Onion Skin",
		func() -> void: Settings.set_value(&"onion_skin", not Settings.get_value(&"onion_skin")),
		Callable(),
		ICONS[&"toggle_onion_skin"],
		func() -> bool: return Settings.get_value(&"onion_skin")
	)


## Names animations on the grid, and makes the animation panel do what names ask
func _setup_labels() -> void:
	var controls: AnimationLabelControls = main.preview_area.enable_animation_labels()
	var panel: AnimationPanel = main.animation_panel
	controls.labels.get_playing = panel.get_selected
	controls.button.tooltip_text = Actions.get_tooltip(&"animation_labels")
	controls.animation_chosen.connect(
		func(index: int) -> void:
			var animation := Global.spritesheet.animations[index]
			main.preview.set_selected_coords(animation.get_frame_cells(Global.spritesheet))
			_choose_animation(index)
	)
	controls.edit_requested.connect(
		func(index: int) -> void:
			_choose_animation(index)
			panel.edit()
	)
	controls.mirror_requested.connect(
		func(index: int) -> void:
			_choose_animation(index)
			panel.detail.mirror_animation()
	)
	controls.delete_requested.connect(
		func(index: int) -> void:
			_choose_animation(index)
			panel.detail.remove_animation()
	)


## The cell whose row or column the actions use: the right-clicked one while the preview's
## menu is open, otherwise the first selected frame's
func _target_cell() -> Vector2i:
	if menu_cell != NO_CELL:
		return menu_cell
	var selected: Array[Vector2i] = main.preview.get_selected_coords()
	return selected[0] if not selected.is_empty() else NO_CELL


## The frames in the row of [param cell], left to right, or with [param column] in its
## column, top to bottom. Empty cells are left out.
static func line_cells(sheet: Spritesheet, cell: Vector2i, column := false) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if cell == NO_CELL:
		return cells
	for coord in sheet.get_sorted_coords():
		if (coord.x == cell.x) if column else (coord.y == cell.y):
			cells.append(coord)
	return cells


## The index of the first animation of [param sheet] that shows exactly [param cells], in
## that order, or -1
static func find_animation(sheet: Spritesheet, cells: Array[Vector2i]) -> int:
	var animations := sheet.animations
	for i in animations.size():
		if animations[i].get_frame_cells(sheet) == cells:
			return i
	return -1


## Asks for the name of an animation of [param cells], or of the one that has them
func name_frames(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var sheet := Global.spritesheet
	_cells = cells.duplicate()
	_renaming = find_animation(sheet, cells)
	if _renaming >= 0:
		dialog.open(sheet.animations[_renaming].name, true)
		return
	var frame_names := PackedStringArray()
	for cell in cells:
		frame_names.append(sheet.frames[cell].resource_name)
	dialog.open(SheetAnimation.default_name(frame_names, sheet.get_animation_names()))


## Makes the animation, or renames it, as one undoable step, and chooses it in the
## animation panel
func _on_name_chosen(animation_name: String) -> void:
	var sheet := Global.spritesheet
	var index := _renaming
	if index >= 0 and index < sheet.animations.size():
		var animation := sheet.animations[index]
		animation.name = animation_name
		Global.document.perform("Rename animation", sheet.set_animation.bind(index, animation))
	else:
		index = Global.document.perform(
			"New animation", sheet.add_animation.bind(SheetAnimation.create(animation_name, _cells))
		)
	_choose_animation(index)


## Chooses the animation at [param index] in the animation panel, to play and edit it
func _choose_animation(index: int) -> void:
	main.animation_panel.select_animation(index)
	Actions.refresh()
