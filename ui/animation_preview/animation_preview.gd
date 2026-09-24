class_name AnimationPreview
extends PanelContainer
## A small player over the preview. Plays one of the sheet's animations, or the selected
## frames (every frame when fewer than two are selected).

## The details button was pressed: open the animation editor at this animation (-1: none)
signal details_requested(animation_index: int)

const DETAILS_ICON := preload("res://assets/icons/DistractionFree.svg")
## Speed of the selection, which isn't an animation of its own
const SELECTION_FPS := 12.0

var preview: SpritesheetPreview
var player := FramePlayer.new()
var selector := OptionButton.new()
var details_button := Button.new()

## Index of the animation being played, or -1 for the selected frames
var _animation_index := -1


func _init() -> void:
	custom_minimum_size = Vector2(220, 230)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.fit_to_longest_item = false
	selector.clip_text = true
	selector.tooltip_text = "Animation to play"
	header.add_child(selector)
	details_button.icon = DETAILS_ICON
	details_button.flat = true
	details_button.tooltip_text = "Edit animations in a bigger preview"
	header.add_child(details_button)
	player.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(player)

	selector.item_selected.connect(
		func(item: int) -> void:
			# Ids are animation indices plus one, since -1 can't be an id
			_animation_index = selector.get_item_id(item) - 1
			refresh()
	)
	details_button.pressed.connect(func() -> void: details_requested.emit(_animation_index))


func _ready() -> void:
	player.sheet = preview.spritesheet
	preview.preview_updated.connect(refresh)
	visibility_changed.connect(refresh)
	refresh()


## Plays the animation at [param index], or the selected frames with -1
func select_animation(index: int) -> void:
	_animation_index = index
	refresh()


func get_animation_index() -> int:
	return _animation_index


## Picks up the current animations, frames and selection
func refresh() -> void:
	if not preview or not visible:
		return
	var sheet := preview.spritesheet
	if player.sheet != sheet:
		player.sheet = sheet
	var animations := sheet.animations
	if _animation_index >= animations.size():
		_animation_index = -1

	selector.clear()
	selector.add_item(tr("Selected frames"), 0)
	for i in animations.size():
		selector.add_item(animations[i].name, i + 1)
	selector.select(selector.get_item_index(_animation_index + 1))

	if _animation_index >= 0:
		var animation := animations[_animation_index]
		player.fps = animation.fps
		player.mode = animation.mode
		player.set_cells(animation.cells)
	else:
		var selected := preview.get_selected_coords()
		player.fps = SELECTION_FPS
		player.mode = SheetAnimation.Mode.LOOP
		player.set_cells(selected if selected.size() >= 2 else sheet.get_sorted_coords())
