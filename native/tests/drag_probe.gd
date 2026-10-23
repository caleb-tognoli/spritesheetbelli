extends SceneTree
## Opens a 600×400 window at (100, 100) with a FileDragMonitor attached, for a drag source
## to drag a file into, out of, back into, and drop. Quits with 0 when the monitor and the
## window said so, in order, and 1 otherwise or after 20 seconds. See x11_drag_test.sh
## and drag_source_windows.ps1.

const EXPECTED := ["entered", "exited", "entered", "exited", "dropped"]

var events: Array[String] = []
var monitor: Object
var attached := false
var started := 0


func _initialize() -> void:
	root.position = Vector2i(100, 100)
	root.size = Vector2i(600, 400)
	started = Time.get_ticks_msec()
	if not ClassDB.class_exists(&"FileDragMonitor"):
		_finish("the extension isn't loaded")
		return
	monitor = ClassDB.instantiate(&"FileDragMonitor")
	monitor.connect(&"drag_entered", _note.bind("entered"))
	monitor.connect(&"drag_exited", _note.bind("exited"))
	root.files_dropped.connect(
		func(files: PackedStringArray) -> void:
			print("dropped ", files)
			_note("dropped")
	)



func _process(_delta: float) -> bool:
	# The window only has its id once the tree is set up
	if monitor and not attached:
		attached = true
		if not monitor.call(&"attach", root):
			_finish("attach() failed on " + DisplayServer.get_name())
	if Time.get_ticks_msec() - started > 20000:
		_finish("timed out")
	return false


func _note(event: String) -> void:
	print(event)
	events.append(event)
	if events.size() == EXPECTED.size():
		_finish("")


func _finish(error: String) -> void:
	if error.is_empty() and events == EXPECTED:
		print("PASS")
		quit(0)
	else:
		print("FAIL: ", error if error else "got %s, expected %s" % [events, EXPECTED])
		quit(1)
