extends Control

const LINK_ICON := preload("res://assets/icons/Link.svg")
const UNLINK_ICON := preload("res://assets/icons/Unlink.svg")
## Pixels to scale before it's done on worker threads behind a progress bar
const SLOW_SCALE_WORK := 1_000_000
## Action buttons in the toolbar, in groups, and the view toggles next to the zoom. The
## first group works on every frame when none are selected.
const TOOLBAR_GROUPS := [
	[&"align_menu", &"pivot_menu", &"trim", &"pin_toggle", &"color_key"],
	[&"flip_h", &"flip_v", &"rotate_ccw", &"rotate_cw"],
]
const TOOLBAR_TOGGLES: Array[StringName] = [
	&"toggle_grid", &"toggle_indices", &"toggle_sprites", &"toggle_history"
]
## Actions offered when right-clicking frames
const CONTEXT_ACTIONS: Array[StringName] = [
	&"cut",
	&"copy",
	&"paste",
	&"duplicate",
	&"",
	&"transform_menu",
	&"align_menu",
	&"pivot_menu",
	&"",
	&"insert_cell",
	&"remove_cell",
	&"rows_menu",
	&"pin_toggle",
	&"",
	&"animation_menu",
	&"",
	&"delete_frames",
]

@onready var files: FileController = $Files
@onready var preview_area: PreviewArea = %PreviewArea
@onready var grid_rows: SpinBox = %GridRows
@onready var grid_columns: SpinBox = %GridColumns
@onready var sprite_width: SpinBox = %SpriteWidth
@onready var sprite_height: SpinBox = %SpriteHeight
@onready var keep_ratio_btn: Button = %KeepRatio
@onready var half_size_btn: Button = %HalfSize
@onready var double_size_btn: Button = %DoubleSize
@onready var triple_size_btn: Button = %TripleSize
@onready var original_size_btn: Button = %OriginalSize
@onready var resize_filter: OptionButton = %ResizeFilter
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var add_sprites_btn: Button = %AddSprites
@onready var add_folder_btn: Button = %AddFolder
@onready var sheet_size: Label = %SheetSize
@onready var export_btn: Button = %Export
@onready var split: HSplitContainer = %Split
@onready var preview_split: HSplitContainer = %PreviewSplit
@onready var history_panel: HistoryPanel = %HistoryPanel
@onready var status_bar: Control = %StatusBar
@onready var sheet_info: Label = %SheetInfo
@onready var cell_info: Label = %CellInfo
@onready var legend: Label = %Legend
@onready var preview: SpritesheetPreview = preview_area.spritesheet_preview
@onready var animation_panel: AnimationPanel = %AnimationPanel

var shortcuts_dialog := ShortcutsDialog.new()
var command_palette := CommandPalette.new()
var settings_window := SettingsWindow.new()
var clipboard := FrameClipboard.new()
var color_key := ColorKeyPreview.new()
var outline_dialog := OutlineDialog.new()
var export_dialog := ExportDialog.new()
var about_dialog := AboutDialog.new()
var source_watcher := SourceWatcher.new()
var layout_controller := LayoutController.new()
var animation_commands := AnimationCommands.new()
var start_screen := StartScreen.new()
## The linked folders, under Add Sprite(s)
var linked_folders := LinkedFolders.new()
## The sidebars, the canvas and the status bar, under the start screen while it shows
var editor := VBoxContainer.new()
var recovery := Recovery.new()
## The settings and export on the left, and the sprites and history on the right
var sidebar_split: SidebarSplit
var panels_split: SidebarSplit
var _was_empty := true
## The view to show once the sheet is laid out (see [method SpritesheetPreview.get_view]),
## empty to show the whole sheet, or null when there's none, see [method _queue_view]
var _queued_view: Variant = null


func _ready() -> void:
	# The command line doesn't need the window
	if Global.cli_mode:
		Global.free_unused_nodes(self)
		queue_free()
		return
	# 0 is only shown while the spritesheet is empty
	for field: SpinBox in [grid_rows, grid_columns, sprite_width, sprite_height]:
		field.min_value = 0
		SpinScroll.enable(field)
	preview_area.spritesheet_preview.spritesheet = Global.spritesheet
	add_child(layout_controller)
	layout_controller.setup(self)
	set_text_params(Global.spritesheet)
	disable_if_empty()

	Global.spritesheet.updated.connect(set_text_params.bind(Global.spritesheet))
	Global.spritesheet.updated.connect(disable_if_empty)
	Global.spritesheet.updated.connect(_prepare_scaled_images)
	add_spritesheet_btn.pressed.connect(Actions.run.bind(&"add_spritesheet"))
	add_sprites_btn.pressed.connect(Actions.run.bind(&"add_sprites"))
	add_folder_btn.pressed.connect(Actions.run.bind(&"add_folder"))
	%AddSpritesRow.add_sibling(linked_folders)
	export_btn.pressed.connect(Actions.run.bind(&"export"))
	export_btn.icon = MainActions.ICONS[&"export"]
	sidebar_split = SidebarSplit.new(split, %Sidebar, &"sidebar_width")
	panels_split = SidebarSplit.new(preview_split, layout_controller.side_split, &"panels_width")
	status_bar.visible = Settings.get_value(&"show_status_bar")
	history_panel.visible = Settings.get_value(&"show_history")
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"show_status_bar":
				status_bar.visible = Settings.get_value(key)
			elif key == &"show_history":
				history_panel.visible = Settings.get_value(key)
				Actions.refresh()
	)
	preview.hover_changed.connect(update_cell_info)
	preview.pixel_hovered.connect(func() -> void: update_cell_info(preview.hovered_cell))
	grid_rows.value_changed.connect(
		func(rows: float) -> void:
			set_spritesheet_grid_size(Global.spritesheet.grid_size.x, int(rows))
	)
	grid_columns.value_changed.connect(
		func(columns: float) -> void:
			set_spritesheet_grid_size(int(columns), Global.spritesheet.grid_size.y)
	)
	sprite_width.value_changed.connect(func(width: float) -> void: set_sprite_size(int(width), -1))
	sprite_height.value_changed.connect(
		func(height: float) -> void: set_sprite_size(-1, int(height))
	)
	half_size_btn.pressed.connect(scale_sprites.bind(0.5))
	double_size_btn.pressed.connect(scale_sprites.bind(2.0))
	triple_size_btn.pressed.connect(scale_sprites.bind(3.0))
	original_size_btn.pressed.connect(
		func() -> void:
			Global.document.perform(
				L10n.mark("Original size"), Global.spritesheet.set_frame_scale.bind(Vector2.ONE)
			)
	)
	resize_filter.item_selected.connect(
		func(filter: int) -> void:
			var sheet := Global.spritesheet
			Global.document.perform(
				L10n.mark("Resize filter"), sheet.set_frame_scale.bind(sheet.frame_scale, filter)
			)
	)
	# Clicking the Filter label opens the list, like clicking the list itself
	LabelLink.link(resize_filter.get_parent().get_child(0) as Label, resize_filter)
	keep_ratio_btn.toggled.connect(
		func(on: bool) -> void: keep_ratio_btn.icon = LINK_ICON if on else UNLINK_ICON
	)
	get_tree().auto_accept_quit = false
	add_child(shortcuts_dialog)
	add_child(command_palette)
	command_palette.animation_panel = animation_panel
	command_palette.exports = files.exports
	add_child(settings_window)
	add_child(color_key)
	color_key.setup(preview_area, edit_selection_in_background)
	add_child(outline_dialog)
	add_child(export_dialog)
	export_dialog.exports = files.exports
	files.exports.open_dialog = Actions.run.bind(&"export")
	add_child(about_dialog)
	add_child(source_watcher)
	animation_panel.setup(preview)
	outline_dialog.outline_chosen.connect(add_outline)
	files.exports.get_selected_coords = preview.get_selected_coords
	export_dialog.get_selected_coords = preview.get_selected_coords
	files.get_view = preview.get_view
	(%MenuBar as MainMenuBar).recent_files.file_chosen.connect(files.open_recent)
	MainActions.register(self)
	layout_controller.register_actions()
	add_child(animation_commands)
	animation_commands.setup(self)
	ActionReasons.apply(self)
	# With buttons for the actions registered above
	_add_start_screen()
	start_screen.file_chosen.connect(files.open_recent)
	add_child(recovery)
	recovery.setup(files, start_screen)
	# Opened from the file manager. Else work left unsaved by a crash is offered on the
	# start screen instead.
	var opened := FileController.files_from_arguments(OS.get_cmdline_args())
	if not opened.is_empty():
		files.open_files.call_deferred(opened)
	elif recovery.leftovers.is_empty():
		files.restore_session.call_deferred()
	Actions.set_tooltip(add_spritesheet_btn, &"add_spritesheet")
	Actions.set_tooltip(add_sprites_btn, &"add_sprites")
	Actions.set_tooltip(add_folder_btn, &"add_folder")
	_update_export_button(ExportTarget.list(Global.spritesheet).size())
	preview_area.set_context_actions(CONTEXT_ACTIONS, MainMenuBar.SUBMENUS)
	preview_area.set_toolbar_actions(
		TOOLBAR_GROUPS, TOOLBAR_TOGGLES, MainMenuBar.SUBMENUS, {&"color_key": color_key.dropdown}
	)
	preview_area.empty_hint.text = "Drop images, folders or a .sbelli project here"
	preview_area.update_ui()
	preview.preview_updated.connect(Actions.refresh)
	preview.selection_changed.connect(update_sheet_info)
	# Another document starts with nothing selected or described; undo and redo keep the
	# selection
	Global.document.loaded.connect(preview.clear_selection.unbind(1))
	Global.document.loaded.connect(preview.clear_hover.unbind(1))
	# Show the whole sheet when frames first appear, e.g. after adding or opening
	Global.spritesheet.updated.connect(
		func() -> void:
			if _was_empty and not Global.spritesheet.is_empty():
				_queue_view({})
			_was_empty = Global.spritesheet.is_empty()
	)
	# A new or opened sheet shows the view saved with it, or else the whole sheet
	Global.document.loaded.connect(_queue_view)
	preview.move_requested.connect(
		func(coords: Array[Vector2i], offset: Vector2i) -> void:
			var targets: Array[Vector2i] = Global.document.perform(
				L10n.mark("Move frames"), Global.spritesheet.move_frames.bind(coords, offset)
			)
			preview.set_selected_coords(targets)
	)
	preview.nudge_requested.connect(
		func(coords: Array[Vector2i], offset: Vector2i) -> void:
			Global.document.perform(
				L10n.mark("Nudge frames"), FrameEdits.nudge.bind(Global.spritesheet, coords, offset)
			)
	)
	preview.lock_requested.connect(
		func(coord: Vector2i, locked: bool) -> void:
			Global.document.perform(
				L10n.mark("Lock cell") if locked else L10n.mark("Unlock cell"),
				Global.spritesheet.set_locked.bind(coord, locked)
			)
	)
	preview.placement_move_requested.connect(
		func(coords: Array[Vector2i], page: int, offset: Vector2i) -> void:
			var sheet := Global.spritesheet
			var places := PackedLayout.moved(sheet, coords, page, offset)
			if places:
				Global.document.perform(L10n.mark("Move frames"), sheet.set_placements.bind(places))
	)
	preview.pivot_requested.connect(
		func(coords: Array[Vector2i], pivot: Vector2) -> void:
			Global.document.perform(
				L10n.mark("Set pivot"),
				FrameEdits.set_pivots_inside.bind(Global.spritesheet, coords, pivot)
			)
	)


## Puts the start screen over the editor and the status bar, which stay laid out under it
## so that a sheet opened from it is shown where it was, fitting the canvas. Its text is
## sized like the canvas's.
func _add_start_screen() -> void:
	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_sibling(body)
	editor.add_theme_constant_override("separation", 0)
	body.add_child(editor)
	split.reparent(editor)
	status_bar.reparent(editor)
	start_screen.theme = preview_area.theme
	body.add_child(start_screen)
	start_screen.visibility_changed.connect(_cover_editor)
	start_screen.cover_actions()
	_cover_editor()


## While the start screen shows, the editor under it can't take focus
func _cover_editor() -> void:
	var covered := start_screen.visible
	editor.focus_behavior_recursive = (
		Control.FOCUS_BEHAVIOR_DISABLED if covered else Control.FOCUS_BEHAVIOR_INHERITED
	)
	var focused := get_viewport().gui_get_focus_owner()
	if covered and focused and editor.is_ancestor_of(focused):
		focused.release_focus()
	Actions.refresh()


## Shows [param view] once the current changes are laid out, or the whole sheet when it's
## empty. When several are queued, the last one is shown: opening a project shows its
## saved view rather than fitting its first frames.
func _queue_view(view: Dictionary) -> void:
	if _queued_view == null:
		_show_queued_view.call_deferred()
	_queued_view = view


func _show_queued_view() -> void:
	var view: Dictionary = _queued_view
	_queued_view = null
	if not is_inside_tree():
		return
	# An empty sheet always shows at 100%
	if view and not Global.spritesheet.is_empty():
		preview.set_view(view)
	else:
		preview.fit_to_view()


## Selected frames that came from a file, see [FrameSource]
func get_selected_linked_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in preview.get_selected_coords():
		if Global.spritesheet.frame_sources.has(coord):
			coords.append(coord)
	return coords


## The selected frames with what they hold, but not where they are in the packed layout,
## see [method Spritesheet.get_cell_data]
func get_selected_cells() -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for coord in preview.get_selected_coords():
		var data := Global.spritesheet.get_cell_data(coord)
		data.erase("placement")
		cells.append(data)
	return cells


func copy_selection() -> void:
	clipboard.copy(get_selected_cells())
	Actions.refresh()


## Adds frames with what they hold to free cells as one undoable step and selects them
func add_cells(action_name: String, cells: Array[Dictionary]) -> void:
	if cells.is_empty():
		return
	var mode: Spritesheet.AddMode = Settings.get_value(&"add_mode")
	var coords: Array[Vector2i] = Global.document.perform(
		action_name, Global.spritesheet.add_cells.bind(cells, mode)
	)
	preview.set_selected_coords(coords)


## Outlines the selected frames, see [method FrameEdits.outline]
func add_outline(color: Color, thickness: int, corners: bool) -> void:
	await edit_selection_in_background(
		L10n.mark("Outline"),
		tr("Adding outlines"),
		func(img: Image) -> Image: return ImageUtils.outline(img, color, thickness, corners),
		FrameEdits.outline_move(thickness),
		FrameEdits.outline_op(color, thickness, corners)
	)


## Replaces each selected frame (or each of [param coords]) with
## [code]edit.call(copy_of_it)[/code], worked out on worker threads with a progress bar when
## it takes a while, then applied as one undoable step. [param move] and [param op] are as
## in [method Spritesheet.edit_frames].
func edit_selection_in_background(
	action_name: String,
	progress_text: String,
	edit: Callable,
	move := Callable(),
	op := {},
	coords: Array[Vector2i] = [],
) -> void:
	var sheet := Global.spritesheet
	if coords.is_empty():
		coords = preview.get_selected_coords()
	var sources: Array[Image] = []
	for coord in coords:
		sources.append(sheet.frames[coord])
	var results := await Parallel.map(
		sources.size(),
		func(i: int) -> Image: return edit.call(sources[i].duplicate()),
		func(done: int, total: int) -> void: Notify.progress(progress_text, done, total)
	)
	Notify.hide_progress()
	Global.document.perform(
		action_name,
		func() -> void:
			for i in coords.size():
				# Skip frames that changed in the meantime
				if sheet.frames.get(coords[i]) == sources[i]:
					var result: Image = results[i]
					sheet.edit_frames(
						[coords[i]] as Array[Vector2i],
						func(_copy: Image) -> Image: return result,
						move,
						false,
						op
					)
	)


## Runs [param edit] with the coordinates of the selected frames, as one undoable step
func edit_selection(action_name: String, edit: Callable) -> void:
	var coords := preview.get_selected_coords()
	if not coords.is_empty():
		Global.document.perform(action_name, edit.bind(coords))


## The selected frames, or every frame when none are
func get_target_coords() -> Array[Vector2i]:
	var coords := preview.get_selected_coords()
	return coords if not coords.is_empty() else Global.spritesheet.get_sorted_coords()


## Like [method edit_selection], but on every frame when none are selected
func edit_targets(action_name: String, edit: Callable) -> void:
	var coords := get_target_coords()
	if not coords.is_empty():
		Global.document.perform(action_name, edit.bind(coords))


## Resizes sprites to the given width or height (-1 = unchanged). With the size linked,
## the other side follows the current proportions, so a deliberate stretch is kept.
func set_sprite_size(width: int, height: int) -> void:
	var sheet := Global.spritesheet
	var base := sheet.get_base_sprite_size()
	if base.x <= 0 or base.y <= 0:
		return
	# Scale factors are exact, unlike the rounded sprite size
	var aspect := sheet.frame_scale.y / sheet.frame_scale.x
	var new_size := sheet.sprite_size
	if width >= 0:
		new_size.x = width
		if keep_ratio_btn.button_pressed:
			new_size.y = roundi(base.y * width / float(base.x) * aspect)
	if height >= 0:
		new_size.y = height
		if keep_ratio_btn.button_pressed:
			new_size.x = roundi(base.x * height / float(base.y) / aspect)
	resize_sprites(new_size)


func resize_sprites(new_size: Vector2i) -> void:
	if new_size.x <= 0 or new_size.y <= 0 or not _check_sprite_size(new_size):
		set_text_params(Global.spritesheet)
		return
	Global.document.perform(
		L10n.mark("Resize sprites"),
		Global.spritesheet.resize_sprites.bind(new_size, get_resize_filter())
	)


## Multiplies the current scale, e.g. 2 to double the size
func scale_sprites(factor: float) -> void:
	var sheet := Global.spritesheet
	if not _check_sprite_size(Vector2i((Vector2(sheet.sprite_size) * factor).round())):
		return
	Global.document.perform(
		L10n.mark("Resize sprites"),
		sheet.set_frame_scale.bind(sheet.frame_scale * factor, get_resize_filter())
	)


## Shows an error and returns false when sprites would be too big to show
func _check_sprite_size(new_size: Vector2i) -> bool:
	var limit := ImageUtils.MAX_TEXTURE_SIZE
	if new_size.x <= limit and new_size.y <= limit:
		return true
	Notify.error(
		(
			tr("Sprites can be at most %d×%d px, and these would be %d×%d px.")
			% [limit, limit, new_size.x, new_size.y]
		)
	)
	return false


## The sheet's filter once it has been resized, otherwise the default from the settings
## Scaling many or big frames takes a while, e.g. after resizing, changing the filter or
## undoing either: scale them on worker threads while a progress bar shows
func _prepare_scaled_images() -> void:
	var sheet := Global.spritesheet
	if (
		sheet.scaled_frames.is_preparing()
		or sheet.scaled_frames.get_pending_work() < SLOW_SCALE_WORK
	):
		return
	await sheet.scaled_frames.prepare(
		func(done: int, total: int) -> void: Notify.progress(tr("Resizing sprites"), done, total)
	)
	Notify.hide_progress()
	if not is_inside_tree():
		return
	preview.queue_redraw()
	# The scale may have changed again in the meantime
	_prepare_scaled_images()


## The sheet's filter. New sheets start with the one chosen in the settings.
func get_resize_filter() -> Image.Interpolation:
	return Global.spritesheet.scale_filter


func set_text_params(spritesheet: Spritesheet) -> void:
	grid_rows.set_value_no_signal(spritesheet.grid_size.y)
	grid_columns.set_value_no_signal(spritesheet.grid_size.x)
	sprite_width.set_value_no_signal(spritesheet.sprite_size.x)
	sprite_height.set_value_no_signal(spritesheet.sprite_size.y)
	var image_size := SpritesheetExporter.get_image_size(
		spritesheet, ExportOptions.from_sheet(spritesheet)
	)
	sheet_size.text = "%d × %d px" % [image_size.x, image_size.y]
	if spritesheet.layout == Spritesheet.Layout.PACKED:
		sheet_size.text = PackedLayout.describe(spritesheet)
	_update_export_button(ExportTarget.list(spritesheet).size())
	layout_controller.update()
	update_sheet_info()
	resize_filter.select(get_resize_filter())


## The export button says how many exports the project has, which Export Again writes
func _update_export_button(count: int) -> void:
	export_btn.text = tr("Export… (%d)") % count if count else tr("Export…")
	export_btn.tooltip_text = Actions.get_tooltip(&"export")
	if count:
		var again := Actions.get_shortcut_text(&"export_again")
		export_btn.tooltip_text += (
			"\n"
			+ (
				tr_n(
					"%d export, written by Export Again (%s)",
					"%d exports, written by Export Again (%s)",
					count
				)
				% [count, again]
			)
		)


## Frame count, grid and image size in the status bar
func update_sheet_info() -> void:
	var sheet := Global.spritesheet
	var count := sheet.frames.size()
	var selected := preview.get_selected_coords().size()
	if sheet.is_empty():
		sheet_info.text = tr("No frames. Add sprites or drop images here.")
	elif sheet.layout == Spritesheet.Layout.PACKED:
		sheet_info.text = (
			tr_n("%d frame · %s", "%d frames · %s", count) % [count, PackedLayout.describe(sheet)]
		)
	else:
		var image_size := SpritesheetExporter.get_image_size(sheet, ExportOptions.from_sheet(sheet))
		sheet_info.text = (
			tr_n("%d frame · %d×%d grid · %d×%d px", "%d frames · %d×%d grid · %d×%d px", count)
			% [count, sheet.grid_size.x, sheet.grid_size.y, image_size.x, image_size.y]
		)
	if selected:
		sheet_info.text += " · " + tr_n("%d selected", "%d selected", selected) % selected
	legend.text = (
		tr("Cells with a lock stay empty") if not sheet.locked_coordinates.is_empty() else ""
	)
	legend.tooltip_text = "Locked cells are kept empty when adding sprites. Click one to unlock it."


## Describes the cell under the mouse in the status bar, with only the folder and name of
## the file its frame comes from: the preview's tooltip has the whole path. Being last, the
## path is cut first when the status bar is full. The pixel under the mouse comes after
## the cell's name, see [method PixelGrid.describe].
func update_cell_info(coord: Vector2i) -> void:
	var lines := PreviewArea.describe_cell(Global.spritesheet, coord, true).split("\n")
	var pixel := PixelGrid.describe(PixelGrid.probe(preview, coord, preview.hovered_pixel))
	if pixel:
		lines.insert(1, pixel)
	cell_info.text = " · ".join(lines)


func disable_if_empty() -> void:
	var is_empty := Global.spritesheet.is_empty()
	grid_rows.editable = not is_empty
	grid_columns.editable = not is_empty
	sprite_width.editable = not is_empty
	sprite_height.editable = not is_empty
	for button: BaseButton in [
		half_size_btn, double_size_btn, triple_size_btn, original_size_btn, resize_filter
	]:
		button.disabled = is_empty
	original_size_btn.disabled = is_empty or Global.spritesheet.frame_scale == Vector2.ONE


func set_spritesheet_grid_size(columns: int, rows: int) -> void:
	var frames_outside_count := Global.spritesheet.count_frames_outside(Vector2i(columns, rows))
	var spritesheet_set_size := Global.document.perform.bind(
		L10n.mark("Resize grid"), Global.spritesheet.set_grid_size.bind(Vector2i(columns, rows))
	)

	if frames_outside_count > 0 and Settings.get_value(&"confirm_grid_shrink"):
		Notify.confirm(
			tr("Confirm resize"),
			(
				tr_n(
					"Resizing the grid to %d×%d would delete %d sprite.",
					"Resizing the grid to %d×%d would delete %d sprites.",
					frames_outside_count
				)
				% [columns, rows, frames_outside_count]
			),
			spritesheet_set_size,
			tr("Resize")
		)
	else:
		spritesheet_set_size.call()
	# Show the current size again if the change was canceled or not possible
	set_text_params(Global.spritesheet)


func _notification(what: int) -> void:
	# Text put together here says it in the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		set_text_params(Global.spritesheet)
		# The names of pages in the packed layout
		preview.queue_redraw()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		files.confirm_unsaved_changes(
			L10n.mark("Save changes to %s before closing?"), get_tree().quit
		)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		clipboard.on_focus_in()
		source_watcher.on_focus_in()
		Actions.refresh()
