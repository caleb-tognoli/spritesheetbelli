class_name AboutDialog
extends AcceptDialog
## Shows the logo, version and links.

const REPOSITORY := "https://github.com/caleb-tognoli/spritesheetbelli"
# L10n.mark
## The project's description in project.godot, here to be translated
const DESCRIPTION := "Combine sprites into spritesheets and cut spritesheets into sprites."

var _engine := Label.new()


func _init() -> void:
	title = "About spritesheetbelli"
	ok_button_text = "Close"
	DialogButtons.apply(self, true)
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
	description.text = DESCRIPTION
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(description)

	_engine.theme_type_variation = &"StatusLabel"
	_engine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_engine)
	about_to_popup.connect(
		func() -> void:
			_engine.text = (
				tr("Made with Godot %s · MIT License") % Engine.get_version_info().string
			)
	)

	var link := Button.new()
	link.text = REPOSITORY.trim_prefix("https://")
	link.icon = preload("res://assets/icons/ExternalLink.svg")
	link.flat = true
	link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	link.pressed.connect(OS.shell_open.bind(REPOSITORY))
	box.add_child(link)


static func get_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "")
