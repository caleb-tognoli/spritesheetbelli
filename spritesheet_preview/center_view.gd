extends TextureButton


@export var camera: Camera2D


func _pressed() -> void:
	camera.position = Vector2(-50, -50)
