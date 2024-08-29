class_name PreviewArea
extends Control


@onready var spritesheet_preview: SpritesheetPreview = %SpritesheetPreview
@onready var zoom: Label = %Zoom


func _process(_delta: float) -> void:
	zoom.text = str(spritesheet_preview.camera.zoom.x * 100).pad_decimals(0) + "%"
