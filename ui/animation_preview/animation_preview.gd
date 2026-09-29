class_name AnimationPreview
extends MarginContainer
## The preview of the animation panel, see [AnimationPanel]. Plays one of the sheet's
## animations, or the selected frames (every frame when fewer than two are selected).

## Speed of the selection, which isn't an animation of its own
const SELECTION_FPS := 12.0

## Where selected frames come from, see [method set_preview]
var preview: SpritesheetPreview:
	set = set_preview
var player := FramePlayer.new()

## Index of the animation being played, or -1 for the selected frames
var _animation_index := -1


func _init() -> void:
	add_theme_constant_override("margin_left", 6)
	add_theme_constant_override("margin_right", 2)
	add_theme_constant_override("margin_bottom", 4)
	add_child(player)


## Plays from [param value]'s sheet and selection, following them
func set_preview(value: SpritesheetPreview) -> void:
	preview = value
	player.sheet = preview.spritesheet
	preview.preview_updated.connect(refresh)
	refresh()


## Plays the animation at [param index], or the selected frames with -1
func select_animation(index: int) -> void:
	_animation_index = index
	refresh()


func get_animation_index() -> int:
	return _animation_index


## What the selected frames are called, which depends on how many there are: fewer than
## two play every frame
func get_selection_title() -> String:
	var all_frames := not preview or preview.get_selected_coords().size() < 2
	return tr("All frames") if all_frames else tr("Selected frames")


## Picks up the current animations, frames and selection
func refresh() -> void:
	if not preview:
		return
	var sheet := preview.spritesheet
	if player.sheet != sheet:
		player.sheet = sheet
	var animations := sheet.animations
	if _animation_index >= animations.size():
		_animation_index = -1

	if _animation_index >= 0:
		var animation := animations[_animation_index]
		player.fps = animation.fps
		player.mode = animation.mode
		player.set_cells(animation.cells, animation.durations)
	else:
		var selected := preview.get_selected_coords()
		player.fps = SELECTION_FPS
		player.mode = SheetAnimation.Mode.LOOP
		player.set_cells(sheet.get_sorted_coords() if selected.size() < 2 else selected)
