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
