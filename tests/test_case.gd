extends Node
## Base class for tests. Every method whose name starts with "test_" is run by
## the test runner, on a fresh instance added to the scene tree.

var failures: PackedStringArray = []
var current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		fail(message if message else "expected true")


func assert_false(condition: bool, message := "") -> void:
	if condition:
		fail(message if message else "expected false")


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if not _is_equal(actual, expected):
		fail(
			(
				"%sexpected %s, got %s"
				% [message + ": " if message else "", var_to_str(expected), var_to_str(actual)]
			)
		)


func assert_ne(actual: Variant, not_expected: Variant, message := "") -> void:
	if _is_equal(actual, not_expected):
		fail(
			(
				"%sexpected anything but %s"
				% [message + ": " if message else "", var_to_str(not_expected)]
			)
		)


func assert_color(img: Image, pos: Vector2i, expected: Color, message := "") -> void:
	assert_eq(img.get_pixelv(pos), expected, message)


func fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])


## Where tests write their files: [param relative] in a folder of this run's own, since
## user:// is shared by every checkout of the project and runs can happen at the same time.
## The test runner empties it before and after the run.
static func temp_path(relative := "") -> String:
	var run_dir := OS.get_user_data_dir().path_join("tests/%d" % OS.get_process_id())
	return run_dir.path_join(relative) if relative else run_dir


## Deletes a folder and everything in it
static func remove_dir(path: String) -> void:
	for dir in DirAccess.get_directories_at(path):
		remove_dir(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## Waits for work behind the busy overlay to end, like opening a file, see
## [method Notify.run_busy]
func until_idle() -> void:
	for i in 600:
		if not Notify.is_progress_visible():
			return
		await get_tree().process_frame


## Returns a solid-colour image
static func make_image(color: Color, size := Vector2i(16, 16)) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img


func _is_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
			return is_equal_approx(float(a), float(b))
		return false
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(a, b)
		TYPE_VECTOR2, TYPE_COLOR:
			return a.is_equal_approx(b)
	return a == b
