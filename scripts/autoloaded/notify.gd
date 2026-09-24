extends Node
## Message and confirmation dialogs usable from anywhere.

var message_dialog := AcceptDialog.new()
var confirm_dialog := ConfirmationDialog.new()
var _confirm_action: Callable


func _ready() -> void:
	for dialog: AcceptDialog in [message_dialog, confirm_dialog]:
		dialog.dialog_autowrap = true
		dialog.min_size = Vector2i(400, 0)
		dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(dialog)
	confirm_dialog.confirmed.connect(
		func():
			var action := _confirm_action
			_confirm_action = Callable()
			if action.is_valid():
				action.call()
	)
	confirm_dialog.canceled.connect(func(): _confirm_action = Callable())


func message(title: String, text: String) -> void:
	message_dialog.title = title
	message_dialog.dialog_text = text
	_popup(message_dialog)


func error(text: String) -> void:
	message("Error", text)


## Asks for confirmation and runs [param action] if confirmed
func confirm(title: String, text: String, action: Callable, ok_text := "OK") -> void:
	confirm_dialog.title = title
	confirm_dialog.dialog_text = text
	confirm_dialog.ok_button_text = ok_text
	_confirm_action = action
	_popup(confirm_dialog)


func _popup(dialog: AcceptDialog) -> void:
	dialog.reset_size()
	dialog.popup_centered()
