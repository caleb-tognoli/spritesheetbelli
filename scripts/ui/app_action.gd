class_name AppAction
extends RefCounted
## A user command registered in [code]Actions[/code]. Its texts are untranslated, marked
## with [method L10n.mark], and translated where they're shown.

var id: StringName
var label: String
## Says more than the label in tooltips, in one line. Left out when the label is enough.
var description: String
var run: Callable
## Returns whether the action can run. Always enabled when not set.
var can_run: Callable
## Why the action can't run, in a few words like "No frames selected", for the command
## palette. See [method Actions.get_disabled_reason].
var disabled_reason: String
## For toggles: returns whether the action is on
var is_checked: Callable
## Returns whether the action makes sense at all right now, like grid actions in the grid
## layout. Unavailable actions are left out of menus and toolbars. Always when not set.
var is_available: Callable
var icon: Texture2D
