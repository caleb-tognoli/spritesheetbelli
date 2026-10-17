extends Node
## Takes the README screenshots in docs/ from the real app. Settings and other user data
## go to a temporary folder.
## Usage: godot --path . res://_dev/readme/screenshots.tscn -- <input folder>
## The input folder has frames/ (the slime from make_slime.py), keys/ and run_keys/ (the
## bounce keys, for the in-betweens window and the GIF) and slime_sheet.png (the slime on
## magenta).

const SIZE := Vector2i(1280, 800)
const OUT := "res://docs/"

var input: String
var main: Control
var temp := OS.get_temp_dir().path_join("sbelli_screenshots")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	input = args[0]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(temp)
	Settings.load_settings(temp.path_join("settings.cfg"))
	AtlasFormats.user_dir = temp.path_join("templates")
	Thumbnails.folder = temp.path_join("thumbnails")
	Recovery.folder = temp.path_join("recovery")
	L10n.user_dir = temp.path_join("translations")
	Settings.set_value(&"theme", "dark")
	Settings.set_value(&"animation_panel", "open")
	get_window().size = SIZE
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	_run_inbetweens()
	await _inbetweens()
	await _slime()
	await _shoot(get_viewport(), "screenshot.png")
	await _reload()
	await _export()
	await _cut()
	Settings.set_value(&"theme", "light")
	await _shoot(get_viewport(), "screenshot-light.png")
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shoot(viewport: Viewport, file: String) -> void:
	for toast in Notify._toasts.get_children():
		toast.queue_free()
	await _frames(10)
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	img.save_png(file if file.is_absolute_path() else ProjectSettings.globalize_path(OUT + file))
	print("saved ", file)


func _pngs(folder: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".png"):
			paths.append(folder.path_join(file))
	return paths


func _inbetweens() -> void:
	await FileController.add_image_files(_pngs(input.path_join("keys")))
	await _frames(3)
	main.files.save_project(temp.path_join("slime_bounce.sbelli"))
	Settings.set_value(&"inbetween_count", 3)
	main.open_inbetweens(Vector2i(0, 0), Vector2i(1, 0), 10)
	var dialog: Window = main.inbetween_dialog
	while not dialog.is_ready():
		await _frames(5)
	dialog.player.playing = false
	dialog.player.go_to(2)
	await _shoot(dialog, "inbetweens.png")
	dialog.hide()


func _slime() -> void:
	main.files.open_in_tab()
	await _frames(3)
	var sheet := Global.spritesheet
	Global.document.perform("Grid", sheet.set_grid_size.bind(Vector2i(6, 2)))
	await FileController.add_image_files(_pngs(input.path_join("frames")))
	await _frames(3)
	var hop: Array[Vector2i] = []
	var idle: Array[Vector2i] = []
	for x in 6:
		hop.append(Vector2i(x, 0))
		idle.append(Vector2i(x, 1))
	Global.document.perform("Anim", sheet.add_animation.bind(SheetAnimation.create("hop", hop)))
	Global.document.perform(
		"Anim", sheet.add_animation.bind(SheetAnimation.create("idle", idle, 8))
	)
	main.files.save_project(temp.path_join("slime.sbelli"))
	await _frames(3)
	main.preview.set_selected_coords(hop)
	main.animation_panel.select_animation(0)
	main.preview.fit_to_view()


func _reload() -> void:
	var dialog: Window = main.source_watcher.dialog
	dialog.ask(input.path_join("slime_sheet.png"), 12, 3, 0, false)
	await _shoot(dialog, input.path_join("reload-dialog.png"))
	dialog.hide()


func _export() -> void:
	var sheet := Global.spritesheet
	var folder := "C:/Projects/slime-game/"
	var targets: Array[ExportTarget] = []
	var data := ExportOptions.Target.DATA
	for settings: Dictionary in [
		{"target": data, "grid_data": "godot", "path": folder + "godot/slime.png"},
		{"target": data, "grid_data": "unity", "path": folder + "unity/Assets/slime.png"},
		{
			"target": ExportOptions.Target.ATLAS,
			"atlas_data": "phaser",
			"path": folder + "web/slime.png",
			"scales": "1, 2",
		},
		{
			"target": ExportOptions.Target.GIF,
			"gif_every_animation": true,
			"gif_scale": 4,
			"path": folder + "gifs",
		},
		{"target": ExportOptions.Target.STRIPS, "path": folder + "gamemaker"},
	]:
		targets.append(ExportTarget.create(sheet, settings))
	Global.document.perform(
		"Exports", sheet.set_export_settings.bind(ExportTarget.settings_with(sheet, targets))
	)
	Settings.set_value(&"export_list_width", 320)
	main.export_dialog.open()
	main.export_dialog.size = Vector2i(1060, 500)
	await _shoot(main.export_dialog, "export.png")
	main.export_dialog.hide()


func _cut() -> void:
	main.files.show_add_spritesheet_window(input.path_join("slime_sheet.png"))
	var window: Window = main.files.add_spritesheet_window
	while not window.visible:
		await _frames(5)
	await _shoot(window, input.path_join("cut-window.png"))
	window.hide()


## Saves the keys of a bounce with frames generated between them, eased out going up and
## in coming down, for the README's GIF
func _run_inbetweens() -> void:
	var keys: Array[Dictionary] = []
	for path in _pngs(input.path_join("run_keys")):
		keys.append({"image": Image.load_from_file(path), "origin": Vector2i.ZERO})
	var out := input.path_join("run_out")
	DirAccess.make_dir_recursive_absolute(out)
	var spacings := [InBetween.Spacing.EASE_OUT, InBetween.Spacing.EASE_IN]
	for i in keys.size():
		var a := keys[i]
		var b := keys[(i + 1) % keys.size()]
		(a.image as Image).save_png(out.path_join("%d_0_key.png" % i))
		var frames := InBetween.generate(a, b, 3, null, spacings[i % spacings.size()])
		for j in frames.size():
			var canvas := Image.create_empty(
				a.image.get_width(), a.image.get_height(), false, Image.FORMAT_RGBA8
			)
			var img: Image = frames[j].image
			img.convert(Image.FORMAT_RGBA8)
			canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), frames[j].origin)
			canvas.save_png(out.path_join("%d_%d_new.png" % [i, j + 1]))
	print("saved run in-betweens")
