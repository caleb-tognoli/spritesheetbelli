extends "res://tests/test_case.gd"
## Scenes are free of what Godot warns about next to nodes in the editor's scene dock


## Every scene of the app
func scenes(dir := "res://") -> PackedStringArray:
	var found := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and sub not in ["addons", "tests"]:
			found.append_array(scenes(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			found.append(dir.path_join(file))
	return found


func check(node: Node, scene: String) -> void:
	var control := node as Control
	if control:
		var where := "%s: %s" % [scene, node.name]
		assert_false(
			control.tooltip_text and control.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			where + " has a tooltip it can't show"
		)
		var label := control as Label
		if label and label.get_parent() is Container:
			assert_false(
				(
					label.autowrap_mode != TextServer.AUTOWRAP_OFF
					and label.custom_minimum_size == Vector2.ZERO
				),
				where + " wraps without a minimum size"
			)
	for child in node.get_children():
		if child.owner == node or child.owner == node.owner:
			check(child, scene)


func test_no_configuration_warnings() -> void:
	var found := scenes()
	assert_true(found.size() >= 3, "scenes found")
	for path in found:
		var scene: PackedScene = load(path)
		var root := scene.instantiate()
		add_child(root)
		await get_tree().process_frame
		check(root, path)
		root.queue_free()
		await get_tree().process_frame
