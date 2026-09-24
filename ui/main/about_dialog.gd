class_name AboutDialog
extends AcceptDialog
## Shows the logo, version and links.

const REPOSITORY := "https://github.com/caleb-tognoli/spritesheetbelli"


func _init() -> void:
	title = "About spritesheetbelli"
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var logo := TextureRect.new()
	logo.texture = preload("res://icon.svg")
	logo.custom_minimum_size = Vector2(96, 96)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(logo)

	var name_label := Label.new()
	name_label.text = "spritesheetbelli %s" % get_version()
	name_label.theme_type_variation = &"HeaderMedium"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var description := Label.new()
	description.text = ProjectSettings.get_setting("application/config/description", "")
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(description)

	var engine := Label.new()
	engine.text = "Made with Godot %s · MIT License" % Engine.get_version_info().string
	engine.theme_type_variation = &"StatusLabel"
	engine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(engine)

	var link := LinkButton.new()
	link.text = REPOSITORY.trim_prefix("https://")
	link.uri = REPOSITORY
	link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(link)


static func get_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "")
