class_name L10n
extends RefCounted
## Translation of the interface. Text is written in English and translated where it's
## shown, with [method Object.tr] and [method Object.tr_n], or by the control showing it.
## [code]_dev/generate_pot.gd[/code] collects it for translators.
## [br]The [code]language[/code] setting picks the language: "system" for the operating
## system's, or a locale like "it". Translations come with the app (Project Settings >
## Localization), and on desktops also from .po files in [member user_dir].

## Where more translations can be put, as .po files named after their locale, like de.po
static var user_dir := "user://translations"
## The translations loaded from [member user_dir], to take out when loading them again
static var _user_translations: Array[Translation] = []


## Returns [param text] as it is, marking it to be translated where it's shown rather than
## here, e.g. action names and history steps, which then follow language changes
static func mark(text: String) -> String:
	return text


## Whether translations can be added in [member user_dir]. Browsers have no folder of the
## user's to put them in.
static func has_user_dir() -> bool:
	return not OS.has_feature("web")


## Loads the .po files in [member user_dir] again, in place of the ones loaded before.
## One that can't be read is left out.
static func load_user_translations() -> void:
	for translation in _user_translations:
		TranslationServer.remove_translation(translation)
	_user_translations.clear()
	if not has_user_dir() or not DirAccess.dir_exists_absolute(user_dir):
		return
	for file in DirAccess.get_files_at(user_dir):
		if file.get_extension().to_lower() != "po":
			continue
		var translation := (
			ResourceLoader.load(
				user_dir.path_join(file), "Translation", ResourceLoader.CACHE_MODE_IGNORE
			)
			as Translation
		)
		if translation == null:
			continue
		# A file without a Language header is named after its locale
		if translation.locale.is_empty() or translation.locale == "en":
			translation.locale = file.get_basename()
		TranslationServer.add_translation(translation)
		_user_translations.append(translation)


## The languages to choose from: [code][locale, name][/code] for English, then every
## language with a translation by locale, named in that language when it's known
static func get_languages() -> Array[Array]:
	var locales := PackedStringArray()
	for locale in TranslationServer.get_loaded_locales():
		var language := TranslationServer.standardize_locale(locale)
		if language not in locales and language != "en":
			locales.append(language)
	locales.sort()
	locales.insert(0, "en")
	var languages: Array[Array] = []
	for locale in locales:
		languages.append([locale, get_language_name(locale)])
	return languages


## [param locale]'s name, in its own language for English and Italian, else in English
static func get_language_name(locale: String) -> String:
	match locale:
		"en":
			return "English"
		"it":
			return "Italiano"
	return TranslationServer.get_locale_name(locale)


## The locale the [code]language[/code] setting stands for: the operating system's
## language for "system"
static func get_locale(language: String) -> String:
	return OS.get_locale_language() if language == "system" else language


## Shows the interface in [param language] (see [method get_locale]). Text without a
## translation in it stays in English.
static func apply(language: String) -> void:
	var locale := get_locale(language)
	if TranslationServer.get_locale() != locale:
		TranslationServer.set_locale(locale)
