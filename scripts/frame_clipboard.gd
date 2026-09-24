class_name FrameClipboard
extends RefCounted
## Frames copied inside the app, or an image copied from another app.
##
## Godot can read images from the system clipboard but not write them, so copied frames
## are kept here. When the app regains focus with an image on the system clipboard,
## that image is assumed to be newer and is pasted instead.

var _frames: Array[Image] = []
var _prefer_system := false


func copy(frames: Array[Image]) -> void:
	_frames = frames.duplicate()
	_prefer_system = false


## Call when the app regains focus: something may have been copied elsewhere
func on_focus_in() -> void:
	if _system_has_image():
		_prefer_system = true


func has_content() -> bool:
	return not _frames.is_empty() or _system_has_image()


## The images to paste
func get_images() -> Array[Image]:
	if (_prefer_system or _frames.is_empty()) and _system_has_image():
		var img := DisplayServer.clipboard_get_image()
		if img and not img.is_empty():
			img.resource_name = "Pasted image"
			return [img] as Array[Image]
	return _frames.duplicate()


func _system_has_image() -> bool:
	return (
		DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
		and DisplayServer.clipboard_has_image()
	)
