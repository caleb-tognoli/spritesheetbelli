class_name L10n
extends RefCounted
## Translation of the interface. Text is written in English and translated where it's
## shown, with [method Object.tr] and [method Object.tr_n], or by the control showing it.
## [code]_dev/generate_pot.gd[/code] collects it for translators.


## Returns [param text] as it is, marking it to be translated where it's shown rather than
## here, e.g. action names and history steps, which then follow language changes
static func mark(text: String) -> String:
	return text
