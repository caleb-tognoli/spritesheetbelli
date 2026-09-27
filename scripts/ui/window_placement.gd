class_name WindowPlacement
extends Node
## Where the main window goes and how small it can be. On first launch it takes 80% of
## the screen, centred, or the whole screen on small ones; after that it's put back where
## it was left, on the same screen, unless that screen is gone. It's remembered a moment
## after the window is moved or resized, so a crash doesn't lose it, and on quit.
## Only on desktops: the web has no window to place, see [method is_supported].

## The smallest the main window can be, in interface units
const MIN_SIZE := Vector2i(960, 600)
## On first launch, the part of the screen the window takes, and the size it gets at least
## when the screen is big enough
const FIRST_SHARE := 0.8
const FIRST_MIN_SIZE := Vector2i(1280, 800)
## Screens up to this wide (in pixels) start with the window maximised
const MAXIMIZE_WIDTH := 1440
## Seconds between looks at the window. It's remembered once it stops changing.
const CHECK_INTERVAL := 0.5

var _timer := Timer.new()
## The window's place at the last look, see [method _get_state]
var _seen := {}


## Whether there's a window to place: not on the web, the command line or in tests, nor
## when the editor shows the app in its own window
static func is_supported() -> bool:
	return not (
		WebFiles.is_web()
		or DisplayServer.get_name() == "headless"
		or Engine.is_embedded_in_editor()
	)


func _ready() -> void:
	_timer.wait_time = CHECK_INTERVAL
	_timer.timeout.connect(_check)
	add_child(_timer)
	_timer.start()


func _exit_tree() -> void:
	_remember(_get_state())


## Puts the window back where it was left, or where it goes on first launch
func restore() -> void:
	var window := get_window()
	var areas: Array[Rect2i] = []
	for screen in DisplayServer.get_screen_count():
		areas.append(get_client_area(screen))
	var saved: Rect2i = Settings.get_value(&"window_rect")
	var rect := get_restored_rect(saved, Settings.get_value(&"window_screen"), areas)
	var maximized: bool = Settings.get_value(&"window_maximized")
	if not rect.has_area():
		var screen := window.current_screen
		rect = get_first_rect(areas[screen])
		# Maximised or not as it was left, unless it's the first time
		if not saved.has_area():
			maximized = maximizes_first(DisplayServer.screen_get_size(screen))
	window.mode = Window.MODE_WINDOWED
	window.size = rect.size
	window.position = rect.position
	if maximized:
		window.mode = Window.MODE_MAXIMIZED
	_seen = _get_state()


## Keeps the window at least [constant MIN_SIZE] interface units at [param scale], as far
## as the screen it's on allows
func apply_min_size(scale: float) -> void:
	var window := get_window()
	window.min_size = get_min_size(scale, get_client_area(window.current_screen).size)


## Where a window's inside can go on [param screen]: the screen without the taskbar, dock
## or menu bar, and without room for the window's title bar and borders
func get_client_area(screen: int) -> Rect2i:
	var area := DisplayServer.screen_get_usable_rect(screen)
	var window := get_window()
	var frame_size := DisplayServer.window_get_size_with_decorations() - window.size
	var frame_offset := window.position - DisplayServer.window_get_position_with_decorations()
	return Rect2i(area.position + frame_offset, area.size - frame_size)


## [constant MIN_SIZE] at the interface's [param scale], in pixels, no bigger than
## [param area] when there's one
static func get_min_size(scale: float, area: Vector2i) -> Vector2i:
	var min_size := Vector2i((Vector2(MIN_SIZE) * scale).ceil())
	return min_size.min(area) if area.x > 0 and area.y > 0 else min_size


## The first launch's window on a screen whose windows can use [param area]: centred,
## [constant FIRST_SHARE] of it, at least [constant FIRST_MIN_SIZE] and at most all of it
static func get_first_rect(area: Rect2i) -> Rect2i:
	var size := Vector2i((Vector2(area.size) * FIRST_SHARE).round())
	size = size.max(FIRST_MIN_SIZE).min(area.size)
	return Rect2i(area.position + (area.size - size) / 2, size)


## Whether the window starts maximised on a screen [param screen_size] pixels big
static func maximizes_first(screen_size: Vector2i) -> bool:
	return screen_size.x <= MAXIMIZE_WIDTH


## The [param saved] window rect as it can be put back, given the [param areas] windows
## can use on each screen: empty when it was never saved, when its [param screen] is gone
## or when it's off every screen. Otherwise it's moved and shrunk to fit on the screen
## that has most of it, e.g. after the screen's resolution went down.
static func get_restored_rect(saved: Rect2i, screen: int, areas: Array[Rect2i]) -> Rect2i:
	if not saved.has_area() or screen < 0 or screen >= areas.size():
		return Rect2i()
	var best := Rect2i()
	var best_overlap := 0
	for area in areas:
		var overlap := area.intersection(saved).get_area()
		if overlap > best_overlap:
			best = area
			best_overlap = overlap
	if best_overlap == 0:
		return Rect2i()
	var size := saved.size.min(best.size)
	return Rect2i(saved.position.clamp(best.position, best.end - size), size)


## The window's mode, and its place and screen
func _get_state() -> Dictionary:
	var window := get_window()
	return {
		"mode": window.mode,
		"rect": Rect2i(window.position, window.size),
		"screen": window.current_screen,
	}


## Remembers the window's place once it's the same as at the last look, so moving or
## resizing it doesn't save the settings many times a second
func _check() -> void:
	var state := _get_state()
	if state != _seen:
		_seen = state
		return
	_remember(state)


## Remembers where the window is, but its size before it was maximised, and nothing while
## it's minimised
func _remember(state: Dictionary) -> void:
	match state.mode:
		Window.MODE_WINDOWED:
			Settings.set_value(&"window_rect", state.rect)
			Settings.set_value(&"window_screen", state.screen)
			Settings.set_value(&"window_maximized", false)
		Window.MODE_MAXIMIZED:
			Settings.set_value(&"window_screen", state.screen)
			Settings.set_value(&"window_maximized", true)
