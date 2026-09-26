class_name AtlasPanel
extends VBoxContainer
## The sidebar section for the packed layout: how frames are packed and how big the pages
## are, with a button to pack again. Shown instead of the grid settings.

## The user changed a setting
signal settings_changed(settings: AtlasSettings)
## The user asked to pack every frame that isn't pinned again
signal repack_requested

const PAGE_SIZES: Array[int] = [256, 512, 1024, 2048, 4096, 8192, 16384]
const PACK_MODES := {
	AtlasSettings.PackMode.KEEP: "Keep places",
	AtlasSettings.PackMode.AUTO: "Always tight",
}
const HEURISTICS := {
	AtlasSettings.Heuristic.BEST_SHORT_SIDE: "Best short side",
	AtlasSettings.Heuristic.BEST_LONG_SIDE: "Best long side",
	AtlasSettings.Heuristic.BEST_AREA: "Best area",
	AtlasSettings.Heuristic.BOTTOM_LEFT: "Bottom left",
	AtlasSettings.Heuristic.CONTACT: "Most contact",
}
const REPACK_TEXT := "Repack"

var page_size := OptionButton.new()
var pack_mode := OptionButton.new()
var heuristic := OptionButton.new()
## Spacing, padding and extruded edges, in a floating panel
var gaps := SpacingDropdown.new()
var spacing := gaps.spacing
var padding := gaps.padding
var extrude := gaps.extrude
var allow_rotation := Button.new()
var trim := Button.new()
var repack := Button.new()

var _updating := false
var _sheet: Spritesheet


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var heading := Label.new()
	heading.theme_type_variation = &"HeaderSmall"
	heading.text = "Atlas"
	add_child(heading)

	for pixels in PAGE_SIZES:
		page_size.add_item("%d px" % pixels)
	_add_row("Pages up to", page_size, "Neither side of a page is longer")
	_fill(pack_mode, PACK_MODES)
	_add_row(
		"Packing",
		pack_mode,
		(
			"Keep places: when frames are added or change, the others stay where they "
			+ "are, so the atlas stays the same between exports. Always tight: everything "
			+ "is packed again."
		),
	)
	_fill(heuristic, HEURISTICS)
	_add_row("Place by", heuristic, "How the free place for a frame is picked")
	gaps.values_changed.connect(_changed)
	add_child(gaps)

	# Two toggles, and packing again in the rest of the row
	var row := HBoxContainer.new()
	for entry: Array in [
		[
			allow_rotation,
			preload("res://assets/icons/ToolRotate.svg"),
			"Turn frames to fit: frames may be stored turned 90°"
		],
		[
			trim,
			preload("res://assets/icons/RegionEdit.svg"),
			"Trim transparent borders: frames are packed without their empty borders"
		],
	]:
		var toggle: Button = entry[0]
		toggle.icon = entry[1]
		toggle.tooltip_text = entry[2]
		toggle.toggle_mode = true
		toggle.custom_minimum_size = Vector2(32, 30)
		toggle.toggled.connect(_changed.unbind(1))
		row.add_child(toggle)
	repack.icon = preload("res://assets/icons/Reload.svg")
	repack.tooltip_text = "Pack every frame that isn't pinned again, as tightly as possible"
	repack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repack.custom_minimum_size = Vector2(0, 30)
	# The text only shows when it fits whole
	repack.clip_text = true
	repack.resized.connect(_fit_repack_text)
	repack.pressed.connect(repack_requested.emit)
	row.add_child(repack)
	add_child(row)
	for option: OptionButton in [page_size, pack_mode, heuristic]:
		option.item_selected.connect(_changed.unbind(1))


## Shows the settings and pages of [param sheet]
func refresh(sheet: Spritesheet) -> void:
	_sheet = sheet
	_updating = true
	var settings := sheet.atlas_settings
	var nearest := 0
	for i in PAGE_SIZES.size():
		if absi(PAGE_SIZES[i] - settings.max_size) < absi(PAGE_SIZES[nearest] - settings.max_size):
			nearest = i
	page_size.select(nearest)
	pack_mode.select(pack_mode.get_item_index(settings.pack_mode))
	heuristic.select(heuristic.get_item_index(settings.heuristic))
	gaps.set_values(settings.padding, settings.spacing, settings.extrude)
	allow_rotation.set_pressed_no_signal(settings.allow_rotation)
	trim.set_pressed_no_signal(settings.trim)
	repack.disabled = sheet.is_empty()
	_updating = false


## The settings as shown
func get_settings(sheet: Spritesheet) -> AtlasSettings:
	var settings := sheet.atlas_settings
	settings.max_size = PAGE_SIZES[maxi(page_size.selected, 0)]
	settings.pack_mode = pack_mode.get_selected_id() as AtlasSettings.PackMode
	settings.heuristic = heuristic.get_selected_id() as AtlasSettings.Heuristic
	settings.spacing = int(spacing.value)
	settings.padding = int(padding.value)
	settings.extrude = int(extrude.value)
	settings.allow_rotation = allow_rotation.button_pressed
	settings.trim = trim.button_pressed
	return settings


func _changed() -> void:
	if not _updating and _sheet:
		settings_changed.emit(get_settings(_sheet))


## Shows "Repack" next to the icon when the button is wide enough for all of it
func _fit_repack_text() -> void:
	var font := repack.get_theme_font(&"font")
	var font_size := repack.get_theme_font_size(&"font_size")
	var style := repack.get_theme_stylebox(&"normal")
	var needed := (
		font.get_string_size(tr(REPACK_TEXT), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		+ repack.icon.get_width()
		+ repack.get_theme_constant(&"h_separation")
		+ style.get_minimum_size().x
	)
	repack.text = REPACK_TEXT if repack.size.x >= needed else ""


func _add_row(text: String, control: Control, tooltip: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# One line: the tooltip says more
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	control.tooltip_text = tooltip
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	LabelLink.link(label, control)
	add_child(row)


static func _fill(option: OptionButton, items: Dictionary) -> void:
	for id: int in items:
		option.add_item(items[id], id)
