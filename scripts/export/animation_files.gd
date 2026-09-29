class_name AnimationFiles
## How exports that write a file for each animation into a folder, like a GIF of each
## animation, name their files: with a pattern of [constant TOKENS], filled in like the
## names of sprites (see [method SpritesheetExporter.fill_tokens]).

## The tokens of their name patterns, with what they give
const TOKENS := {
	"animation": "The animation's name",
	"count": "How many frames its file has",
}


## The paths of files in [param folder] named with [param pattern], with
## [param extension], one for each of [param entries]: [code]{"name": String, "count": int}
## [/code], an animation's name and how many frames its file has. A name taken by a file
## before is numbered, as sprites' names are.
static func get_paths(
	folder: String, pattern: String, extension: String, entries: Array[Dictionary]
) -> PackedStringArray:
	var paths := PackedStringArray()
	# Lowercase, as Windows and macOS see "Walk.gif" and "walk.gif" as one file
	var used := {}
	var taken := func(path: String) -> bool: return used.has(path.to_lower())
	for entry in entries:
		var name := format_name(pattern, entry.name, entry.count, extension)
		var path := SpritesheetExporter.unique_path(folder.path_join(name), "." + extension, taken)
		used[path.to_lower()] = true
		paths.append(path)
	return paths


## The file name, without [param extension], that [param pattern] gives the file of the
## animation called [param animation] with [param count] frames. The extension is added
## when writing: "{animation}.gif" names "walk.gif", not "walk.gif.gif".
static func format_name(
	pattern: String, animation: String, count: int, extension: String
) -> String:
	var values := {"animation": animation, "count": count}
	var base := SpritesheetExporter.without_extension(pattern, extension)
	return SpritesheetExporter.fill_tokens(base, values, animation.validate_filename())


## What each token gives for the first animation of [param sheet], for examples
static func get_example_values(sheet: Spritesheet) -> Dictionary:
	for animation in sheet.animations:
		return {"animation": animation.name, "count": animation.get_frame_cells(sheet).size()}
	return {}
