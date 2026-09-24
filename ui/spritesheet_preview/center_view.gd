extends TextureButton

@export var preview: SpritesheetPreview


func _ready() -> void:
	tooltip_text = "Fit to view"


func _pressed() -> void:
	preview.fit_to_view()
