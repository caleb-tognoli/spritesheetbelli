class_name ActionReasons
extends RefCounted
## Why actions can't run, in a few words, for the command palette: sets
## [member AppAction.why_disabled] and [member AppAction.unavailable_reason] of the actions
## the main window registers. An action whose conditions don't hold says why the first one
## doesn't, like "No frames yet" before "No frames selected". Actions left out say "No
## frames yet" while the sheet is empty (see [method Actions.get_disabled_reason]).


## Gives the actions registered by [param main] (the main window) and its helpers their
## reasons
static func apply(main: Control) -> void:
	var sheet := Global.spritesheet
	var preview: SpritesheetPreview = main.preview
	var clipboard: FrameClipboard = main.clipboard
	var panel: AnimationPanel = main.animation_panel
	var commands: AnimationCommands = main.animation_commands
	var selected := func() -> Array[Vector2i]: return preview.get_selected_coords()
	var has_frames := func() -> bool: return not sheet.is_empty()
	var has_selection := func() -> bool: return not selected.call().is_empty()
	var one_selected := func() -> bool: return selected.call().size() == 1
	var linked := func() -> bool: return not main.get_selected_linked_coords().is_empty()
	var not_top := func() -> bool: return selected.call()[0].y > 0
	var not_bottom := func() -> bool: return selected.call()[0].y < sheet.grid_size.y - 1
	var has_animations := func() -> bool: return not sheet.animations.is_empty()
	var has_current := func() -> bool: return panel.get_selected() >= 0
	var has_target := func() -> bool: return commands.target_cell() != AnimationCommands.NO_CELL
	var line_has_frames := func(column: bool) -> bool:
		var cells := AnimationCommands.line_cells(sheet, commands.target_cell(), column)
		return not cells.is_empty()

	# Pairs of a condition and what's said when it doesn't hold, in order
	var frames := [has_frames, L10n.mark("No frames yet")]
	var selection := frames + [has_selection, L10n.mark("No frames selected")]
	var target := frames + [has_target, L10n.mark("No frames selected")]
	var animations := [has_animations, L10n.mark("No animations yet")]
	var chosen := animations + [has_current, L10n.mark("No animation chosen")]
	var needs := {
		&"paste": [clipboard.has_content, L10n.mark("Nothing copied")],
		&"undo": [Global.document.can_undo, L10n.mark("Nothing to undo")],
		&"redo": [Global.document.can_redo, L10n.mark("Nothing to redo")],
		&"replace_image": selection + [one_selected, L10n.mark("Select a single frame")],
		&"reload_source": selection + [linked, L10n.mark("Not loaded from a file")],
		&"move_row_up": selection + [not_top, L10n.mark("Already the top row")],
		&"move_row_down": selection + [not_bottom, L10n.mark("Already the bottom row")],
		&"animation_from_row":
		target + [line_has_frames.bind(false), L10n.mark("No frames in this row")],
		&"animation_from_column":
		target + [line_has_frames.bind(true), L10n.mark("No frames in this column")],
		&"duplicate_animation": chosen,
		&"mirror_animation": chosen,
		&"delete_animation": chosen,
		&"animation_labels": animations,
	}
	for id: StringName in [
		&"select_none",
		&"flip_h",
		&"flip_v",
		&"rotate_cw",
		&"rotate_ccw",
		&"delete_frames",
		&"copy",
		&"cut",
		&"duplicate",
		&"add_outline",
		&"insert_cell",
		&"remove_cell",
		&"insert_row",
		&"remove_row",
		&"animation_from_selection",
	]:
		needs[id] = selection
	for id: StringName in needs:
		if Actions.has(id):
			Actions.get_action(id).why_disabled = first_failing.bind(needs[id])

	var grid_only: Array[StringName] = LayoutController.GRID_ONLY_ACTIONS.duplicate()
	grid_only.append_array([&"animation_from_row", &"animation_from_column", &"animation_labels"])
	var pivots: Array[StringName] = [&"pivot_clear"]
	for preset: Array in LayoutController.PIVOT_PRESETS:
		pivots.append(preset[0])
	for group: Array in [
		[grid_only, L10n.mark("Only in the grid layout")],
		[[&"repack", &"pin_toggle"], L10n.mark("Only in the packed layout")],
		[pivots, L10n.mark("Pivots are off")],
	]:
		for id: StringName in group[0]:
			if Actions.has(id):
				Actions.get_action(id).unavailable_reason = group[1]


## What [param needs] says for the first of its conditions that doesn't hold: it has pairs
## of a condition and what's said when it doesn't. Empty when they all hold.
static func first_failing(needs: Array) -> String:
	for i in range(0, needs.size(), 2):
		if not (needs[i] as Callable).call():
			return needs[i + 1]
	return ""
