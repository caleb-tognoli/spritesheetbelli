extends "res://tests/test_case.gd"

var main: Control
var recovery: Recovery
var dir := temp_path("recovery_test")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Global.document.reset()
	await start()


func after_each() -> void:
	main.queue_free()
	await get_tree().process_frame
	Global.document.reset()
	Settings.reset_to_defaults()
	Settings.set_value(&"last_session", "")
	remove_dir(dir)
	if DirAccess.dir_exists_absolute(Recovery.folder):
		remove_dir(Recovery.folder)


## Instantiates the main window, as when the app starts
func start() -> void:
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	recovery = main.recovery
	await get_tree().process_frame


## Quits the main window cleanly and starts it again
func restart() -> void:
	main.queue_free()
	await get_tree().process_frame
	Global.document.reset()
	await start()


func add_frames(count: int, action_name := "Add sprites") -> void:
	var imgs: Array[Image] = []
	for i in count:
		imgs.append(make_image(Color(i / float(count), 0, 0)))
	Global.document.perform(action_name, Global.spritesheet.add_frames.bind(imgs))


## A copy left by a run that's no longer running: process 0, with one blue frame
func leave_copy(path: String, doc_name: String, time := 1000, session := "0_1_0") -> String:
	var left := Recovery.folder.path_join(session)
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.BLUE)] as Array[Image])
	Recovery._write(sheet, {}, {"path": path, "name": doc_name, "time": time}, left)
	return left


func read_copy() -> Dictionary:
	return Recovery.read_info(recovery.session_dir)


func test_copied_every_few_minutes_when_unsaved() -> void:
	assert_eq(recovery.timer.wait_time, 120.0, "every 2 minutes")
	assert_false(recovery.timer.is_stopped())
	recovery.timer.timeout.emit()
	recovery.wait()
	assert_false(recovery.has_copy(), "nothing unsaved")

	add_frames(1)
	assert_false(recovery.has_copy(), "a small change waits for the timer")
	recovery.timer.timeout.emit()
	recovery.wait()
	assert_true(recovery.has_copy(), "written")
	var info := read_copy()
	assert_eq(info.path, "", "never saved")
	assert_eq(info.name, "")
	assert_true(absi(info.time - int(Time.get_unix_time_from_system())) < 60, "its time")
	var loaded := ProjectFile.load(recovery.session_dir.path_join(Recovery.COPY_FILE))
	assert_eq(loaded.state.frames.size(), 1, "the sheet as it is")
	assert_false(
		FileAccess.file_exists(recovery.session_dir.path_join(Recovery.COPY_FILE + ".tmp")),
		"no temporary file left"
	)

	# Unchanged since: not written again
	DirAccess.remove_absolute(recovery.session_dir.path_join(Recovery.COPY_FILE))
	recovery.timer.timeout.emit()
	recovery.wait()
	assert_false(recovery.has_copy(), "nothing new to copy")


func test_interval_setting() -> void:
	Settings.set_value(&"recovery_minutes", 5)
	assert_eq(recovery.timer.wait_time, 300.0)
	Settings.set_value(&"recovery_minutes", 0)
	assert_true(recovery.timer.is_stopped(), "off")
	add_frames(Recovery.BIG_CHANGE_FRAMES)
	await get_tree().process_frame
	recovery.save_copy()
	recovery.wait()
	assert_false(recovery.has_copy(), "no copies while off")


func test_copied_right_after_big_changes() -> void:
	add_frames(Recovery.BIG_CHANGE_FRAMES)
	await get_tree().process_frame
	recovery.wait()
	assert_true(recovery.has_copy(), "written without waiting for the timer")

	# Small changes add up
	DirAccess.remove_absolute(recovery.session_dir.path_join(Recovery.COPY_FILE))
	for i in Recovery.BIG_CHANGE_FRAMES - 1:
		add_frames(1)
	await get_tree().process_frame
	recovery.wait()
	assert_false(recovery.has_copy(), "not yet")
	add_frames(1)
	await get_tree().process_frame
	recovery.wait()
	assert_true(recovery.has_copy(), "once enough changed")


func test_saved_project_keeps_its_path() -> void:
	add_frames(1)
	var path := dir.path_join("walk.sbelli")
	assert_true(await main.files.save_project(path))
	add_frames(1)
	recovery.timer.timeout.emit()
	recovery.wait()
	var info := read_copy()
	assert_eq(info.path, path)
	assert_eq(info.name, "walk.sbelli")


func test_saving_deletes_the_copy() -> void:
	add_frames(1)
	recovery.save_copy()
	assert_true(await main.files.save_project(dir.path_join("saved.sbelli")))
	assert_false(recovery.has_copy(), "saved")
	assert_false(DirAccess.dir_exists_absolute(recovery.session_dir))

	# Undoing back to what was saved needs no copy either
	add_frames(1)
	recovery.save_copy()
	recovery.wait()
	assert_true(recovery.has_copy())
	Global.document.undo()
	assert_false(recovery.has_copy(), "as saved")


func test_replacing_the_document_deletes_the_copy() -> void:
	add_frames(1)
	recovery.save_copy()
	recovery.wait()
	Global.document.reset()
	assert_false(recovery.has_copy(), "New, after Don't Save")


func test_clean_exit_deletes_the_copy() -> void:
	add_frames(1)
	recovery.save_copy()
	recovery.wait()
	var session := recovery.session_dir
	assert_true(recovery.has_copy())
	await restart()
	assert_false(DirAccess.dir_exists_absolute(session), "deleted when quitting")
	assert_true(recovery.leftovers.is_empty(), "nothing to recover")
	assert_false(main.start_screen.notices.visible)


func test_crash_offers_the_copy() -> void:
	var project := dir.path_join("walk.sbelli")
	Settings.set_value(&"restore_session", true)
	Settings.set_value(&"last_session", project)
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	ProjectFile.save(sheet, project)
	var older := leave_copy("", "", 1000, "0_1_0")
	var newer := leave_copy(project, "walk.sbelli", 2000, "0_2_0")
	# A run that left nothing to recover
	DirAccess.make_dir_recursive_absolute(Recovery.folder.path_join("0_3_0"))
	await restart()

	assert_eq(recovery.leftovers.size(), 2, "offered")
	assert_eq(recovery.leftovers[0].dir, newer, "newest first")
	assert_eq(recovery.leftovers[0].path, project)
	assert_eq(recovery.leftovers[1].dir, older)
	assert_false(DirAccess.dir_exists_absolute(Recovery.folder.path_join("0_3_0")), "cleaned up")
	assert_true(Global.document.is_blank(), "the last project isn't reopened")
	await get_tree().process_frame
	assert_true(Global.document.is_blank())
	var start_screen: StartScreen = main.start_screen
	assert_true(start_screen.visible)
	assert_true(start_screen.notices.visible, "on the start screen")
	assert_eq(recovery.notice.rows.size(), 2)
	var texts: PackedStringArray = []
	for label in recovery.notice.rows[0].find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_eq(texts[0], "walk.sbelli")
	assert_true(texts[1].ends_with(project), "with its file, got %s" % texts[1])
	assert_eq(Recovery.describe_time(0).length(), 16, "like 2026-09-30 14:05")


func test_recover() -> void:
	var project := dir.path_join("walk.sbelli")
	var left := leave_copy(project, "walk.sbelli")
	await restart()
	var buttons := recovery.notice.rows[0].find_children("*", "Button", true, false)
	(buttons[0] as Button).pressed.emit()
	var document := Global.document
	assert_eq(document.path, project, "Save writes to its file")
	assert_true(document.is_dirty, "unsaved")
	assert_eq(document.get_history_start(), "Recovered walk.sbelli")
	assert_color(Global.spritesheet.frames[Vector2i.ZERO], Vector2i.ZERO, Color.BLUE)
	assert_false(DirAccess.dir_exists_absolute(left), "the old copy is gone")
	assert_true(recovery.has_copy(), "it's this run's copy now")
	assert_true(recovery.leftovers.is_empty())
	assert_false(main.start_screen.visible, "opened")
	assert_false(recovery.notice.visible)
	Global.document.undo()
	assert_true(document.is_dirty, "still unsaved")

	# Never saved: a new document
	left = leave_copy("", "")
	recovery.find_leftovers()
	Global.document.reset()
	assert_true(recovery.recover(recovery.leftovers[0]))
	assert_eq(document.path, "")
	assert_true(document.is_dirty)
	assert_eq(document.get_history_start(), "Recovered Untitled")


func test_discard() -> void:
	var left := leave_copy("", "")
	await restart()
	var buttons := recovery.notice.rows[0].find_children("*", "Button", true, false)
	(buttons[1] as Button).pressed.emit()
	assert_true(Notify.confirm_dialog.visible, "asks first")
	Notify.confirm_dialog.confirmed.emit()
	Notify.confirm_dialog.hide()
	assert_false(DirAccess.dir_exists_absolute(left), "deleted")
	assert_true(recovery.leftovers.is_empty())
	assert_false(main.start_screen.notices.visible)


func test_running_runs_are_not_offered() -> void:
	# This process's own run, and another one that's open
	add_frames(1)
	recovery.save_copy()
	recovery.wait()
	var other := Recovery.new()
	add_child(other)
	assert_true(other.leftovers.is_empty(), "the other run's copy isn't offered")
	other.queue_free()
	await get_tree().process_frame
	assert_true(recovery.has_copy(), "and it stays")


func test_web() -> void:
	Recovery.enabled = false
	var window := SettingsWindow.new()
	assert_true(window.get_control(&"recovery_minutes") == null, "no setting in a browser")
	window.free()
	var other := Recovery.new()
	add_child(other)
	add_frames(1)
	other.save_copy()
	other.wait()
	assert_eq(other.session_dir, "", "nothing written")
	other.queue_free()
	Recovery.enabled = true
	window = SettingsWindow.new()
	assert_true(window.get_control(&"recovery_minutes") != null)
	window.free()
