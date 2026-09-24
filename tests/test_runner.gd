extends Node
## Runs every tests/unit/test_*.gd script and quits with the number of failures.
## Usage: godot --headless --path . res://tests/test_runner.tscn [-- --filter=<text>]

const TEST_DIR := "res://tests/unit"


func _ready() -> void:
	# The headless window is tiny, which makes popups complain about their position
	get_window().size = Vector2i(1280, 800)
	
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
			await test.call(method_name)
			await test.after_each()
			test_count += 1
			
			if test.failures.is_empty():
				print("  ok   ", test_name)
			else:
				print("  FAIL ", test_name)
				for f in test.failures:
					print("         ", f)
				failures.append_array(test.failures)
			remove_child(test)
			test.queue_free()
			await get_tree().process_frame
	
	print("\n%d tests, %d failures" % [test_count, failures.size()])
	get_tree().quit(mini(failures.size(), 125))
