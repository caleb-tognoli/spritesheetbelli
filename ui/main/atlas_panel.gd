class_name AtlasPanel
extends VBoxContainer
## The sidebar section for the packed layout: how frames are packed and how big the pages
## are. Shown instead of the grid settings.

## The user changed a setting
signal settings_changed(settings: AtlasSettings)

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

var page_size := OptionButton.new()
var pack_mode := OptionButton.new()
var heuristic := OptionButton.new()
var spacing := SpinBox.new()
var padding := SpinBox.new()
var extrude := SpinBox.new()
var allow_rotation := CheckBox.new()

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
	_add_row("Place frames by", heuristic, "How the free place for a frame is picked")
	for spin: SpinBox in [spacing, padding, extrude]:
		spin.max_value = 256
		spin.suffix = "px"
		spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		spin.select_all_on_focus = true
		spin.value_changed.connect(_changed.unbind(1))
	_add_row("Spacing", spacing, "Empty pixels between frames")
	_add_row("Padding", padding, "Empty pixels around each page")
	_add_row("Extrude edges", extrude, "Repeats each frame's edge pixels outward")
	allow_rotation.text = "Turn frames to fit"
	allow_rotation.tooltip_text = "Frames may be stored turned 90°"
	allow_rotation.toggled.connect(_changed.unbind(1))
	add_child(allow_rotation)
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
	spacing.set_value_no_signal(settings.spacing)
	padding.set_value_no_signal(settings.padding)
	extrude.set_value_no_signal(settings.extrude)
	allow_rotation.set_pressed_no_signal(settings.allow_rotation)
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
	return settings


func _changed() -> void:
	if not _updating and _sheet:
		settings_changed.emit(get_settings(_sheet))


func _add_row(text: String, control: Control, tooltip: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
