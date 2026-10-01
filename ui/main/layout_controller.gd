class_name LayoutController
extends Node
## The packed layout in the main window: the layout switch and the atlas settings in the
## sidebar, which replace the grid settings when packed, the list of sprites next to the
## history, and the actions for packing, pinning and pivots. Grid actions are left out of
## menus in the packed layout.

## Pivots the pivot presets put frames at, from 0 to 1 across each frame, with the icon
## of the action to borrow
const PIVOT_PRESETS := [  # L10n.mark
	[&"pivot_center", "Centre", Vector2(0.5, 0.5), &"align_center"],
	[&"pivot_top", "Top", Vector2(0.5, 0), &"align_top"],
	[&"pivot_bottom", "Bottom", Vector2(0.5, 1), &"align_bottom"],
	[&"pivot_left", "Left", Vector2(0, 0.5), &"align_left"],
	[&"pivot_right", "Right", Vector2(1, 0.5), &"align_right"],
	[&"pivot_top_left", "Top Left", Vector2(0, 0), &"pivot_top_left"],
	[&"pivot_bottom_left", "Bottom Left", Vector2(0, 1), &"pivot_bottom_left"],
]
## Actions that only make sense with cells, left out in the packed layout
const GRID_ONLY_ACTIONS: Array[StringName] = [
	&"insert_cell",
	&"remove_cell",
	&"insert_row",
	&"remove_row",
	&"move_row_up",
	&"move_row_down",
]
## What tooltips say after an action's name and shortcut, see [member AppAction.description]
const DESCRIPTIONS := {  # L10n.mark
	&"layout_grid": "Frames in the cells of a grid",
	&"layout_packed": "Frames packed tightly on pages",
	&"repack": "Pack every frame that isn't pinned again, as tightly as possible",
	&"pin_toggle":
	(
		"Pins the selected frames, or every frame when none are selected, so packing again "
		+ "keeps their place"
	),
}

var main: Control
var atlas_panel := AtlasPanel.new()
var sprites_panel := SpritesPanel.new()
## The sprites above the history, next to the preview
var side_split := VSplitContainer.new()
## Switches between the grid and the packed layout, above the grid or atlas settings
var layout_grid_btn := Button.new()
var layout_packed_btn := Button.new()
## Spacing, padding and extruded edges of the exported grid, in the grid section
var grid_gaps := SpacingDropdown.new()
## Sidebar parts only shown in the grid layout
var _grid_parts: Array[Control] = []


## Adds the sidebar parts to [param main_ui], the main window
func setup(main_ui: Control) -> void:
	main = main_ui
	_build_sidebar()
	_build_side_panels()
	_fit_sidebars()


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


## Keeps both sidebars as wide as their widest content, also the parts that are hidden
## (the settings of the other layout, a closed panel), so the preview doesn't move when
## switching layouts or opening a panel
func _fit_sidebars() -> void:
	var sections: Control = main.sheet_size.get_parent()
	sections.custom_minimum_size.x = _widest(sections.get_children())
	side_split.custom_minimum_size.x = _widest([sprites_panel, main.history_panel])


static func _widest(controls: Array[Node]) -> float:
	var widest := 0.0
	for control in controls:
		if control is Control:
			widest = maxf(widest, (control as Control).get_combined_minimum_size().x)
	return widest


## The layout switch and the atlas settings in the sidebar, which replace the grid
## settings in the packed layout
func _build_sidebar() -> void:
	var sections: Node = main.sheet_size.get_parent()
	# The scroll bar has room kept for it in the right margin, so the sidebar is as wide
	# whether it shows or not
	var margin: MarginContainer = sections.get_parent()
	var scroll: ScrollContainer = margin.get_parent()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	var bar_width := roundi(scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	var margin_width := margin.get_theme_constant("margin_right")
	margin.add_theme_constant_override("margin_right", maxi(0, margin_width - bar_width))
	var grid_heading: int = main.grid_rows.get_parent().get_index() - 1
	for index: int in [grid_heading, grid_heading + 1, grid_heading + 2]:
		_grid_parts.append(sections.get_child(index))
	_grid_parts.append(main.sprite_width.get_parent())
	var grid_row: Control = main.grid_rows.get_parent()
	grid_row.add_sibling(grid_gaps)
	_grid_parts.append(grid_gaps)
	grid_gaps.values_changed.connect(_on_grid_gaps_changed)

	var heading := Label.new()
	heading.theme_type_variation = &"HeaderSmall"
	heading.text = "Layout"
	var row := HBoxContainer.new()
	var group := ButtonGroup.new()
	for entry: Array in [
		[layout_grid_btn, L10n.mark("Grid"), &"layout_grid"],
		[layout_packed_btn, L10n.mark("Packed"), &"layout_packed"],
	]:
		var button: Button = entry[0]
		button.text = entry[1]
		button.icon = MainActions.ICONS[entry[2]]
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
				L10n.mark("Atlas settings"), Global.spritesheet.set_atlas_settings.bind(settings)
			)
	)
	atlas_panel.repack_requested.connect(Actions.run.bind(&"repack"))
	Global.spritesheet.layout_warning.connect(Notify.toast)
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key in [&"atlas_dedupe", &"atlas_power_of_two", &"atlas_square"]:
				var sheet := Global.spritesheet
				if sheet.layout == Spritesheet.Layout.PACKED:
					Global.document.perform(L10n.mark("Atlas settings"), sheet.refresh_layout)
	)


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
	else:
		var options := ExportOptions.from_sheet(sheet)
		grid_gaps.set_values(options.padding, options.spacing, options.extrude)
		grid_gaps.disabled = sheet.is_empty()
	_fit_sidebars()


## Stores the grid's spacing with the sheet's export settings, where exports take it from
func _on_grid_gaps_changed() -> void:
	var sheet := Global.spritesheet
	var options := ExportOptions.from_sheet(sheet)
	options.padding = int(grid_gaps.padding.value)
	options.spacing = int(grid_gaps.spacing.value)
	options.extrude = int(grid_gaps.extrude.value)
	Global.document.perform(
		L10n.mark("Spacing & padding"), sheet.set_export_settings.bind(options.to_dictionary())
	)


## Actions of the packed layout, pivots and the layout switch, and the tooltips of the
## buttons for them
func register_actions() -> void:
	var sheet := Global.spritesheet
	var has_frames := func() -> bool: return not sheet.is_empty()
	var packed := func() -> bool: return sheet.layout == Spritesheet.Layout.PACKED
	var pivots := func() -> bool: return Settings.get_value(&"use_pivots")
	var grid := func() -> bool: return sheet.layout == Spritesheet.Layout.GRID
	for id in GRID_ONLY_ACTIONS:
		Actions.get_action(id).is_available = grid
	Actions.add(
		&"layout_grid",
		L10n.mark("Grid Layout"),
		func() -> void:
			Global.document.perform(
				L10n.mark("Grid layout"), sheet.set_layout.bind(Spritesheet.Layout.GRID)
			),
		Callable(),
		MainActions.ICONS[&"layout_grid"],
		grid
	)
	var pack := func() -> void:
		Global.document.perform(
			L10n.mark("Pack frames"), sheet.set_layout.bind(Spritesheet.Layout.PACKED)
		)
		main.preview.fit_to_view()
		# Without cells, the list is the way to find frames
		Settings.set_value(&"show_sprites", true)
	Actions.add(
		&"layout_packed",
		L10n.mark("Packed Layout"),
		pack,
		Callable(),
		MainActions.ICONS[&"layout_packed"],
		packed
	)
	Actions.add(
		&"toggle_sprites",
		L10n.mark("Sprites"),
		func() -> void: Settings.set_value(&"show_sprites", not sprites_panel.visible),
		Callable(),
		preload("res://assets/icons/FileList.svg"),
		func() -> bool: return sprites_panel.visible
	)
	Actions.add(
		&"repack",
		L10n.mark("Pack Again"),
		func() -> void:
			Global.document.perform(
				L10n.mark("Pack again"),
				func() -> void: sheet.set_placements(PackedLayout.arrange(sheet, true).placements)
			),
		func() -> bool: return not sheet.is_empty(),
		MainActions.ICONS[&"repack"],
		Callable(),
		packed
	)
	var all_pinned := func() -> bool:
		var coords: Array[Vector2i] = main.get_target_coords()
		return (
			not coords.is_empty()
			and coords.all(
				func(c: Vector2i) -> bool: return sheet.placements.get(c, {}).get("pinned", false)
			)
		)
	var toggle_pins := func() -> void:
		var pin: bool = not all_pinned.call()
		Global.document.perform(
			L10n.mark("Pin frames") if pin else L10n.mark("Unpin frames"),
			sheet.set_pinned.bind(main.get_target_coords(), pin)
		)
	Actions.add(
		&"pin_toggle",
		L10n.mark("Pinned"),
		toggle_pins,
		has_frames,
		MainActions.ICONS[&"pin_toggle"],
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
			main.edit_targets.bind(L10n.mark("Set pivot"), set_pivots),
			has_frames,
			MainActions.ICONS.get(preset[3]),
			Callable(),
			pivots
		)
	Actions.add(
		&"pivot_clear",
		L10n.mark("Remove Pivot"),
		main.edit_targets.bind(
			L10n.mark("Remove pivot"),
			func(coords: Array[Vector2i]) -> void: sheet.set_pivots(coords, null)
		),
		has_frames,
		MainActions.ICONS[&"pivot_clear"],
		Callable(),
		pivots
	)
	for id: StringName in DESCRIPTIONS:
		Actions.get_action(id).description = DESCRIPTIONS[id]
	Actions.set_tooltip(layout_grid_btn, &"layout_grid")
	Actions.set_tooltip(layout_packed_btn, &"layout_packed")
	Actions.set_tooltip(atlas_panel.repack, &"repack")
