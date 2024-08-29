class_name PreviewArea
extends Control


@onready var spritesheet_preview: SpritesheetPreview = %SpritesheetPreview
@onready var select_all_btn: Button = %SelectAll
@onready var select_none_btn: Button = %SelectNone
@onready var num_selected: Label = %NumSelected

@onready var zoom: Label = %Zoom


func _ready() -> void:
	updated_ui()
	spritesheet_preview.preview_updated.connect(updated_ui)
	select_all_btn.pressed.connect(select_all.bind(true))
	select_none_btn.pressed.connect(select_all.bind(false))


func _process(_delta: float) -> void:
	zoom.text = str(spritesheet_preview.camera.zoom.x * 100).pad_decimals(0) + "%"


func updated_ui() -> void:
	var is_empty := spritesheet_preview.spritesheet.is_empty()
	select_all_btn.visible = not is_empty
	select_none_btn.visible = not is_empty
	
	var selection_size := spritesheet_preview.get_selected_frames().size()
	num_selected.visible = not is_empty and not selection_size == 0
	num_selected.text = "%d selected" % [selection_size]


func select_all(select: bool) -> void:
	for frame: SpritesheetPreviewFrame in spritesheet_preview.frames.get_children():
		frame.selected = select
