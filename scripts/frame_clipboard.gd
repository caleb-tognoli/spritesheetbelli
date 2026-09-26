class_name FrameClipboard
extends RefCounted
## Frames copied inside the app, or an image copied from another app.
##
## Godot can read images from the system clipboard but not write them, so copied frames
## are kept here, with their origins, pivots and links (see
## [method Spritesheet.get_cell_data]). When the app regains focus with an image on the
## system clipboard, that image is assumed to be newer and is pasted instead.

var _cells: Array[Dictionary] = []
var _prefer_system := false


## Copies frames with what they hold. Where they were in the packed layout isn't kept:
## pasted frames are packed where they fit.
func copy(cells: Array[Dictionary]) -> void:
	_cells.clear()
	for data in cells:
		var copied := data.duplicate()
		copied.erase("placement")
		_cells.append(copied)
	_prefer_system = false


## Call when the app regains focus: something may have been copied elsewhere
func on_focus_in() -> void:
	if _system_has_image():
		_prefer_system = true


func has_content() -> bool:
	return not _cells.is_empty() or _system_has_image()


## The frames to paste, see [method Spritesheet.add_cells]
func get_cells() -> Array[Dictionary]:
	if (_prefer_system or _cells.is_empty()) and _system_has_image():
		var img := DisplayServer.clipboard_get_image()
		if img and not img.is_empty():
			img.resource_name = "Pasted image"
			return [{"image": img}] as Array[Dictionary]
	return _cells.duplicate()


func _system_has_image() -> bool:
	# Browsers don't let the app read images from the clipboard
	if OS.has_feature("web"):
		return false
	return (
		DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
		and DisplayServer.clipboard_has_image()
	)
