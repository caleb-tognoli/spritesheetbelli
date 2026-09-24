class_name AppAction
extends RefCounted
## A user command registered in [code]Actions[/code].

var id: StringName
var label: String
var run: Callable
## Returns whether the action can run. Always enabled when not set.
var can_run: Callable
## For toggles: returns whether the action is on
var is_checked: Callable
var icon: Texture2D
