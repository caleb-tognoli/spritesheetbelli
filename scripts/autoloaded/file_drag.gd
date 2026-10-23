extends Node
## Tells while files from the operating system are dragged over the window, so where they
## can be dropped can show it. Godot's windows only say when they're dropped (see
## [signal Window.files_dropped]), so the native extension in [code]native/[/code] tells
## on desktops, and the page in a browser. Without either, like on Wayland or when the
## extension wasn't built, [member supported] is false and nothing is sent.

## Files were dragged into the window
signal entered
## They were dragged out again, the drag was canceled, or they were dropped
signal exited

## Lets a browser page add the listeners, see [method _watch_page]
const PAGE_SCRIPT := """
(function() {
	var canvas = document.querySelector('canvas');
	var inside = false;
	function hasFiles(event) {
		return event.dataTransfer && Array.prototype.indexOf.call(event.dataTransfer.types, 'Files') >= 0;
	}
	function set(value) {
		if (inside != value) {
			inside = value;
			window.sbelliFileDrag(value);
		}
	}
	canvas.addEventListener('dragenter', function(event) { if (hasFiles(event)) set(true); });
	canvas.addEventListener('dragleave', function() { set(false); });
	canvas.addEventListener('drop', function() { set(false); });
})();
"""

## Whether files are over the window
var dragging := false
## Whether this platform tells, see the class description
var supported := false
## The extension's FileDragMonitor, untyped so this works without the extension
var _monitor: Object
## Keeps the browser's callback alive
var _page_callback: JavaScriptObject


func _ready() -> void:
	get_window().files_dropped.connect(_on_files_dropped)
	if WebFiles.is_web():
		_watch_page()
	elif ClassDB.class_exists(&"FileDragMonitor"):
		# The window only has its id once the tree is set up
		_attach_monitor.call_deferred()


## Sets [member dragging], saying when it changes
func set_dragging(value: bool) -> void:
	if dragging == value:
		return
	dragging = value
	if value:
		entered.emit()
	else:
		exited.emit()


## Whatever was said before, files that were dropped are no longer dragged
func _on_files_dropped(_files: PackedStringArray) -> void:
	set_dragging(false)


func _attach_monitor() -> void:
	_monitor = ClassDB.instantiate(&"FileDragMonitor")
	supported = _monitor.call(&"attach", get_window())
	if supported:
		_monitor.connect(&"drag_entered", set_dragging.bind(true))
		_monitor.connect(&"drag_exited", set_dragging.bind(false))


func _watch_page() -> void:
	_page_callback = JavaScriptBridge.create_callback(
		func(args: Array) -> void: set_dragging(bool(args[0]))
	)
	JavaScriptBridge.get_interface("window").sbelliFileDrag = _page_callback
	JavaScriptBridge.eval(PAGE_SCRIPT, true)
	supported = true
