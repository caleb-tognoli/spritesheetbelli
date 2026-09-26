class_name LayoutController
extends Node
## The packed layout in the main window: the layout switch and the atlas settings in the
## sidebar, which replace the grid settings when packed, the list of sprites next to the
## history, and the actions for packing, pinning and pivots. Grid actions are left out of
## menus in the packed layout.

## Pivots the pivot presets put frames at, from 0 to 1 across each frame, with the icon
## of the action to borrow
const PIVOT_PRESETS := [
	[&"pivot_center", "Centre", Vector2(0.5, 0.5), &"align_center"],
	[&"pivot_top", "Top", Vector2(0.5, 0), &"align_top"],
	[&"pivot_bottom", "Bottom", Vector2(0.5, 1), &"align_bottom"],
	[&"pivot_left", "Left", Vector2(0, 0.5), &"align_left"],
	[&"pivot_right", "Right", Vector2(1, 0.5), &"align_right"],
	[&"pivot_top_left", "Top Left", Vector2(0, 0), &""],
	[&"pivot_bottom_left", "Bottom Left", Vector2(0, 1), &""],
]
## Actions that only make sense with cells, left out in the packed layout
const GRID_ONLY_ACTIONS: Array[StringName] = [
	&"insert_cell",
	&"remove_cell",
	&"insert_row",
	&"remove_row",
	&"move_row_up",
	&"move_row_down",
	&"name_row",
]

var main: Control
var atlas_panel := AtlasPanel.new()
var sprites_panel := SpritesPanel.new()
## The sprites above the history, next to the preview
var side_split := VSplitContainer.new()
## Switches between the grid and the packed layout, above the grid or atlas settings
var layout_grid_btn := Button.new()
var layout_packed_btn := Button.new()
## Sidebar parts only shown in the grid layout
var _grid_parts: Array[Control] = []


## Adds the sidebar parts to [param main_ui], the main window
func setup(main_ui: Control) -> void:
	main = main_ui
	_build_sidebar()
	_build_side_panels()


## Puts the sprites panel above the history panel
func _build_side_panels() -> void:
	var history: Control = main.history_panel
	var preview_split: Node = history.get_parent()
	preview_split.add_child(side_split)
	preview_split.move_child(side_split, history.get_index())
	history.reparent(side_split)
	sprites_panel.preview = main.preview
	sprites_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_split.add_child(sprites_panel)
	side_split.move_child(sprites_panel, 0)
	sprites_panel.visible = Settings.get_value(&"show_sprites")
	history.visibility_changed.connect(_update_side_split)
	sprites_panel.visibility_changed.connect(_update_side_split)
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"show_sprites":
				sprites_panel.visible = Settings.get_value(key)
				Actions.refresh()
	)
	_update_side_split()


func _update_side_split() -> void:
	side_split.visible = sprites_panel.visible or main.history_panel.visible


## The layout switch and the atlas settings in the sidebar, which replace the grid
## settings in the packed layout
func _build_sidebar() -> void:
	var sections: Node = main.sheet_size.get_parent()
	var grid_heading: int = main.grid_rows.get_parent().get_index() - 1
	for index: int in [grid_heading, grid_heading + 1, grid_heading + 2]:
		_grid_parts.append(sections.get_child(index))
	_grid_parts.append(main.sprite_width.get_parent())

	var heading := Label.new()
	heading.theme_type_variation = &"HeaderSmall"
	heading.text = "Layout"
	var row := HBoxContainer.new()
	var group := ButtonGroup.new()
	for entry: Array in [
		[layout_grid_btn, "Grid", &"layout_grid", "Frames in the cells of a grid"],
		[layout_packed_btn, "Packed", &"layout_packed", "Frames packed tightly on pages"],
	]:
		var button: Button = entry[0]
		button.text = entry[1]
		button.icon = main.ICONS[entry[2]]
		button.tooltip_text = entry[3]
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 30)
		button.pressed.connect(Actions.run.bind(entry[2]))
		row.add_child(button)
	var parts: Array[Control] = [heading, row, HSeparator.new(), atlas_panel]
	for i in parts.size():
		sections.add_child(parts[i])
		sections.move_child(parts[i], grid_heading + i)
	var after_atlas := HSeparator.new()
	sections.add_child(after_atlas)
	sections.move_child(after_atlas, atlas_panel.get_index() + 1)
	atlas_panel.set_meta(&"separator", after_atlas)
	atlas_panel.settings_changed.connect(
		func(settings: AtlasSettings) -> void:
			Global.document.perform(
				"Atlas settings", Global.spritesheet.set_atlas_settings.bind(settings)
			)
	)
	atlas_panel.repack_requested.connect(Actions.run.bind(&"repack"))
	Global.spritesheet.layout_warning.connect(Notify.toast)


## Shows the grid or the atlas settings, whichever the layout uses
func update() -> void:
	var sheet := Global.spritesheet
	var packed := sheet.layout == Spritesheet.Layout.PACKED
	for part in _grid_parts:
		part.visible = not packed
	atlas_panel.visible = packed
	atlas_panel.get_meta(&"separator").visible = packed
	layout_grid_btn.set_pressed_no_signal(not packed)
	layout_packed_btn.set_pressed_no_signal(packed)
	if packed:
		atlas_panel.refresh(sheet)


## Actions of the packed layout, pivots and the layout switch
func register_actions() -> void:
	var sheet := Global.spritesheet
	var has_selection := func() -> bool: return not main.preview.get_selected_coords().is_empty()
	var packed := func() -> bool: return sheet.layout == Spritesheet.Layout.PACKED
	var grid := func() -> bool: return sheet.layout == Spritesheet.Layout.GRID
	for id in GRID_ONLY_ACTIONS:
		Actions.get_action(id).is_available = grid
	Actions.add(
		&"layout_grid",
		"Grid Layout",
		func() -> void:
			Global.document.perform("Grid layout", sheet.set_layout.bind(Spritesheet.Layout.GRID)),
		Callable(),
		main.ICONS[&"layout_grid"],
		grid
	)
	var pack := func() -> void:
		Global.document.perform("Pack frames", sheet.set_layout.bind(Spritesheet.Layout.PACKED))
		main.preview.fit_to_view()
		# Without cells, the list is the way to find frames
		Settings.set_value(&"show_sprites", true)
	Actions.add(
		&"layout_packed", "Packed Layout", pack, Callable(), main.ICONS[&"layout_packed"], packed
	)
	Actions.add(
		&"toggle_sprites",
		"Sprites",
		func() -> void: Settings.set_value(&"show_sprites", not sprites_panel.visible),
		Callable(),
		null,
		func() -> bool: return sprites_panel.visible
	)
	Actions.add(
		&"tool_pivot",
		"Pivot Mode",
		main.preview_area.set_tool.bind(SpritesheetPreview.Tool.PIVOT),
		Callable(),
		main.ICONS[&"tool_pivot"],
		func() -> bool: return main.preview.tool == SpritesheetPreview.Tool.PIVOT
	)
	Actions.add(
		&"repack",
		"Pack Again",
		func() -> void:
			Global.document.perform(
				"Pack again",
				func() -> void: sheet.set_placements(PackedLayout.arrange(sheet, true).placements)
			),
		func() -> bool: return not sheet.is_empty(),
		main.ICONS[&"repack"],
		Callable(),
		packed
	)
	var all_pinned := func() -> bool:
		var coords: Array[Vector2i] = main.preview.get_selected_coords()
		return (
			not coords.is_empty()
			and coords.all(
				func(c: Vector2i) -> bool: return sheet.placements.get(c, {}).get("pinned", false)
			)
		)
	var toggle_pins := func() -> void:
		var pin: bool = not all_pinned.call()
		var changes := PackedLayout.pinned(sheet, main.preview.get_selected_coords(), pin)
		Global.document.perform(
			"Pin frames" if pin else "Unpin frames", sheet.set_placements.bind(changes)
		)
	Actions.add(
		&"pin_toggle",
		"Pinned",
		toggle_pins,
		has_selection,
		main.ICONS[&"pin_toggle"],
		all_pinned,
		packed
	)
	for preset: Array in PIVOT_PRESETS:
		var anchor: Vector2 = preset[2]
		var set_pivots := func(coords: Array[Vector2i]) -> void:
			for coord in coords:
				var size := Vector2(sheet.frames[coord].get_size())
				sheet.set_pivots([coord] as Array[Vector2i], (size * anchor).round())
		Actions.add(
			preset[0],
			preset[1],
			main.edit_selection.bind("Set pivot", set_pivots),
			has_selection,
			main.ICONS.get(preset[3])
		)
	Actions.add(
		&"pivot_clear",
		"Remove Pivot",
		main.edit_selection.bind(
			"Remove pivot", func(coords: Array[Vector2i]) -> void: sheet.set_pivots(coords, null)
		),
		has_selection,
		main.ICONS[&"pivot_clear"]
	)
