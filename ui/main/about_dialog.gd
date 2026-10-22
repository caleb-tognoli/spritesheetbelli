class_name AboutDialog
extends AcceptDialog
## Shows the logo, version and links, and the licenses of the app and of Godot.

const REPOSITORY := "https://github.com/caleb-tognoli/spritesheetbelli"
# L10n.mark
## The project's description in project.godot, here to be translated
const DESCRIPTION := "Combine sprites into spritesheets and cut spritesheets into sprites."
## The licenses of the crates in the native library, written with it by native/build.py
const NATIVE_LICENSES := "res://extension/bin/native_licenses.txt"

var _engine := Label.new()
var _licenses := AcceptDialog.new()
var _license_text := TextEdit.new()


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

	var licenses_button := Button.new()
	licenses_button.text = "Licenses"
	licenses_button.flat = true
	licenses_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	licenses_button.pressed.connect(_show_licenses)
	box.add_child(licenses_button)

	_licenses.title = "Licenses"
	_licenses.ok_button_text = "Close"
	DialogButtons.apply(_licenses)
	_license_text.editable = false
	_license_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_license_text.custom_minimum_size = Vector2(560, 420)
	_licenses.add_child(_license_text)
	add_child(_licenses)


static func get_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "")


## The app's license, Godot's, those of the libraries in Godot, and those of the native
## extension's when it's there (see [constant NATIVE_LICENSES]), which every copy of the
## app has to show. Left in English, as licenses are.
static func get_license_text() -> String:
	var sections := PackedStringArray()
	var own := FileAccess.get_file_as_string("res://LICENSE").strip_edges()
	if own:
		sections.append("spritesheetbelli\n\n" + own)
	sections.append("Godot Engine\n\n" + Engine.get_license_text().strip_edges())
	var components := PackedStringArray()
	for component: Dictionary in Engine.get_copyright_info():
		var lines := PackedStringArray([component.name])
		for part: Dictionary in component.parts:
			for holder: String in part.copyright:
				lines.append("    © " + holder)
			lines.append("    License: " + part.license)
		components.append("\n".join(lines))
	sections.append("Third-party components of Godot Engine\n\n" + "\n\n".join(components))
	var licenses := Engine.get_license_info()
	for license: String in licenses:
		sections.append("%s\n\n%s" % [license, (licenses[license] as String).strip_edges()])
	var native := FileAccess.get_file_as_string(NATIVE_LICENSES).strip_edges()
	if native:
		sections.append(native)
	return "\n\n\n".join(sections)


func _show_licenses() -> void:
	if _license_text.text.is_empty():
		_license_text.text = get_license_text()
	_licenses.popup_centered()
