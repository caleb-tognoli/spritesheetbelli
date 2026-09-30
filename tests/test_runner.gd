extends Node
## Runs every tests/unit/test_*.gd script and quits with the number of failures.
## Usage: godot --headless --path . res://tests/test_runner.tscn [-- --filter=<text>]

const TestCase := preload("res://tests/test_case.gd")
const TEST_DIR := "res://tests/unit"


func _ready() -> void:
	# Fail instead of hanging when something breaks badly, e.g. an autoload
	get_tree().create_timer(600).timeout.connect(
		func() -> void:
			print("Tests timed out")
			TestCase.remove_dir(TestCase.temp_path())
			get_tree().quit(124)
	)

	# The headless window is tiny, which makes popups complain about their position
	get_window().size = Vector2i(1280, 800)

	# Never touch the real settings, nor the files of other runs: user:// is shared by every
	# checkout of the project, so each run has a folder of its own, see TestCase.temp_path
	_remove_stale_runs()
	TestCase.remove_dir(TestCase.temp_path())
	DirAccess.make_dir_recursive_absolute(TestCase.temp_path())
	Settings.load_settings(TestCase.temp_path("settings.cfg"))
	AtlasFormats.user_dir = TestCase.temp_path("templates")
	Thumbnails.folder = TestCase.temp_path("thumbnails")
	Recovery.folder = TestCase.temp_path("recovery")
	# Undo what the real settings did at startup
	Global.apply_ui_scale()
	Global.apply_theme()
	# Tests check English text, whatever the machine's language, without the user's own
	# translations
	L10n.user_dir = TestCase.temp_path("translations")
	L10n.load_user_translations()
	TranslationServer.set_locale("en")

	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")

	var failures: PackedStringArray = []
	var test_count := 0
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(TEST_DIR.path_join(file))
		# A script that doesn't compile has no methods, so its tests would silently vanish
		if script == null or not script.can_instantiate():
			print("  FAIL ", file, " doesn't compile")
			failures.append("%s doesn't compile" % file)
			continue
		for method in script.get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			var test_name := "%s:%s" % [file.get_basename(), method_name]
			if filter and not filter in test_name:
				continue

			var test: Node = script.new()
			test.current_test = test_name
			add_child(test)
			await test.before_each()
			# The headless mouse never leaves (0, 0), where controls are until their container
			# places them. A control found there then stays hovered wherever it ends up, and
			# shows its tooltip, which takes the next Escape. Hover what's really there.
			get_viewport().update_mouse_cursor_state()
			await test.call(method_name)
			await test.after_each()
			test_count += 1

			if test.failures.is_empty():
				print("  ok   ", test_name)
			else:
				print("  FAIL ", test_name)
				for f: String in test.failures:
					print("         ", f)
				failures.append_array(test.failures)
			remove_child(test)
			test.queue_free()
			await get_tree().process_frame

	print("\n%d tests, %d failures" % [test_count, failures.size()])
	TestCase.remove_dir(TestCase.temp_path())
	get_tree().quit(mini(failures.size(), 125))


## Deletes the folders of runs that were killed before they could
func _remove_stale_runs() -> void:
	var tests_dir := TestCase.temp_path().get_base_dir()
	for dir in DirAccess.get_directories_at(tests_dir):
		if dir.is_valid_int() and not OS.is_process_running(dir.to_int()):
			TestCase.remove_dir(tests_dir.path_join(dir))
