class_name TemplateData
## The values a [Template] is filled with to write the data file of an export: the frames,
## the animations and the pages (images) of the export, built once per export. Every
## value is described where it's set. Sizes and positions are in pixels.
##
## A data file written for each page of an atlas gets the values of the whole export,
## with the frames and image of its page instead, see [method for_page].


## The values of an export of [param frames] on [param pages], from
## [method Metadata.grid_frames] or [method AtlasFormats.get_frames] and
## [code]{"file": String, "size": Vector2i}[/code]. [param animation_list] is from
## [method Metadata.animations], and [param fps] is the export's speed. A grid sheet's
## export gives [param grid], see [method grid_values].
static func build(
	frames: Array[Dictionary],
	animation_list: Array[Dictionary],
	pages: Array[Dictionary],
	fps: float,
	grid := {},
) -> Dictionary:
	var durations := frame_durations(animation_list, fps)
	var frame_values: Array[Dictionary] = []
	for index in frames.size():
		var duration: Variant = null
		if frames[index].has("duration"):
			duration = frames[index].duration
		elif durations.has(index):
			duration = durations[index]
		elif fps > 0:
			duration = roundi(1000.0 / fps)
		frame_values.append(_frame(frames[index], index, duration))
	var page_values: Array[Dictionary] = []
	for index in pages.size():
		var size: Vector2i = pages[index].size
		var on_page := frame_values.filter(
			func(frame: Dictionary) -> bool: return frame.page == index
		)
		(
			page_values
			. append(
				{
					## Position among the pages, from 0
					"index": index,
					## File name of the page's image
					"image": pages[index].file,
					## Size of the page's image
					"w": size.x,
					"h": size.y,
					## File name of the page's image at twice the size, when the export
					## is written at scales 1 and 2 (for CSS on screens with two pixels to
					## a CSS pixel), in the file of scale 1. Nothing otherwise.
					"retina_image": pages[index].get("retina_image"),
					## The frames on the page, see [method _frame]
					"frames": on_page,
					## How many frames are on it
					"frame_count": on_page.size(),
				}
			)
		)
	var animation_values: Array[Dictionary] = []
	for animation in animation_list:
		animation_values.append(_animation(animation, frame_values, fps))
	var first_page: Dictionary = page_values[0] if page_values else {}
	var values := {
		## The app that wrote the file, "spritesheetbelli", and its version
		"app": "spritesheetbelli",
		"version": ProjectSettings.get_setting("application/config/version", ""),
		## Frames per second the export is played at, for animations without a speed
		"fps": float(fps),
		## Every frame of the file in reading order, see [method _frame]
		"frames": frame_values,
		## How many frames the file has
		"frame_count": frame_values.size(),
		## Whether the file has every frame of the export. Only then do frame positions
		## ([code]index[/code], [code]from[/code] and [code]to[/code]) count the file's
		## frames too.
		"all_frames": true,
		## The sheet's animations, see [method _animation]. Empty when it has none.
		"animations": animation_values,
		## How many animations the sheet has
		"animation_count": animation_values.size(),
		## Every page (image) of the export, see above: one for a grid sheet
		"pages": page_values,
		## How many pages the export has
		"page_count": page_values.size(),
		## The file's page: its position, image file name and size. For a file of the whole
		## export, the first page.
		"page": 0,
		"image": first_page.get("image", ""),
		"image_w": first_page.get("w", 0),
		"image_h": first_page.get("h", 0),
		## File names of the data files of the other pages, for a file written for each page
		"related": PackedStringArray(),
	}
	values.merge(grid)
	return values


## The values of a grid sheet's export, not set for an atlas: how the image is laid out,
## for formats that cut it into tiles themselves
static func grid_values(sheet: Spritesheet, options: ExportOptions) -> Dictionary:
	return {
		## How many columns and rows of cells the grid has, empty ones too
		"columns": sheet.grid_size.x,
		"rows": sheet.grid_size.y,
		## The size of a cell, and so of every frame
		"cell_w": sheet.sprite_size.x * options.scale,
		"cell_h": sheet.sprite_size.y * options.scale,
		## Transparent pixels around the image, between cells, and edge pixels repeated
		## around each cell (inside the spacing): the first cell is at padding + extrude,
		## and each next one cell_w + 2 × extrude + spacing further. Like every size, as
		## many times bigger as the image at a scale other than 1.
		"padding": options.padding * options.scale,
		"spacing": options.spacing * options.scale,
		"extrude": options.extrude * options.scale,
	}


## The values of [param data] (from [method build]) for the file of [param page] only,
## which names the files of the others in [param related]
static func for_page(data: Dictionary, page: int, related: PackedStringArray) -> Dictionary:
	var result := data.duplicate()
	var values: Dictionary = data.pages[page]
	result.frames = values.frames
	result.frame_count = values.frame_count
	result.all_frames = values.frame_count == data.frame_count
	result.page = page
	result.image = values.image
	result.image_w = values.w
	result.image_h = values.h
	result.related = related
	return result


## How long each of [param frames] is shown in milliseconds, by index: from the first
## animation of [param animation_list] it's in, at that animation's speed or else
## [param fps]. Frames in no animation are left out.
static func frame_durations(animation_list: Array[Dictionary], fps: float) -> Dictionary:
	var result := {}
	for animation in animation_list:
		var animation_fps: float = animation.fps if animation.fps > 0 else fps
		if animation_fps <= 0:
			continue
		var indices: Array = animation.indices
		var durations: Array = animation.get("durations", [])
		for i in indices.size():
			if not result.has(indices[i]):
				var duration: float = durations[i] if i < durations.size() else 1.0
				result[indices[i]] = roundi(1000.0 * duration / animation_fps)
	return result


## The values of a frame, the [param index]th of the export
static func _frame(frame: Dictionary, index: int, duration: Variant) -> Dictionary:
	var rect: Rect2i = frame.rect
	var rotated: bool = frame.get("rotated", false)
	var size := Vector2i(rect.size.y, rect.size.x) if rotated else rect.size
	var source: Rect2i = frame.get("source_rect", Rect2i(Vector2i.ZERO, size))
	var source_size: Vector2i = frame.get("source_size", size)
	var coord: Vector2i = frame.get("coord", Vector2i.ZERO)
	var has_pivot: bool = frame.has("pivot")
	var pivot: Vector2 = frame.get("pivot", Vector2.ZERO)
	var pivot_pixels := pivot * Vector2(source_size)
	return {
		## Position among the export's frames in reading order, from 0
		"index": index,
		## The name from the sprite name pattern, unique in the export, and as a PNG file
		## name: "walk_0" and "walk_0.png"
		"name": str(frame.name).get_basename(),
		"file_name": frame.name,
		## The cell the frame is in on the sheet's grid, from 0
		"column": coord.x,
		"row": coord.y,
		## The position of that cell in reading order from 0, counting empty cells too, as
		## tile sets number their tiles. For an atlas, the same as index.
		"cell": frame.get("cell", index),
		## The page it's on, from 0
		"page": frame.get("page", 0),
		## Where it is on its page, and its size before it was turned. For a grid sheet,
		## its cell.
		"x": rect.position.x,
		"y": rect.position.y,
		"w": size.x,
		"h": size.y,
		## Its size on the page as it's stored: w and h the other way round when turned
		"packed_w": rect.size.x,
		"packed_h": rect.size.y,
		## Stored turned 90°, which way the format's header says
		"rotated": rotated,
		## Packed without transparent borders, see the trim values
		"trimmed": source.size != source_size,
		## Its size with the borders: its own, or its cell's when the export gives frames
		## their cell's size
		"source_w": source_size.x,
		"source_h": source_size.y,
		## The transparent pixels left out on each side
		"trim_left": source.position.x,
		"trim_top": source.position.y,
		"trim_right": source_size.x - source.end.x,
		"trim_bottom": source_size.y - source.end.y,
		## Whether it has a pivot: frames of a packed atlas do, their own or the atlas's
		## default, and so do frames of a grid sheet when pivots are turned on in Settings
		"has_pivot": has_pivot,
		## The pivot from 0 to 1 across the frame with its borders, and in pixels from its
		## top-left corner. Nothing without a pivot.
		"pivot_x": _only_if(has_pivot, pivot.x),
		"pivot_y": _only_if(has_pivot, pivot.y),
		"pivot_px_x": _only_if(has_pivot, pivot_pixels.x),
		"pivot_px_y": _only_if(has_pivot, pivot_pixels.y),
		## How long it's shown in milliseconds: in the first animation it's in, at that
		## animation's speed, or else at the export's speed. Nothing when neither has one.
		"duration": duration,
	}


## The values of an animation from [method Metadata.animations], of [param frame_values]
static func _animation(
	animation: Dictionary, frame_values: Array[Dictionary], fps: float
) -> Dictionary:
	var indices: Array = animation.indices
	var mode: SheetAnimation.Mode = animation.get("mode", SheetAnimation.Mode.LOOP)
	var animation_fps: float = animation.fps if animation.get("fps", 0.0) > 0 else fps
	var durations: Array = animation.get("durations", []).duplicate()
	durations.resize(indices.size())
	durations = durations.map(
		func(value: Variant) -> float: return 1.0 if value == null else float(value)
	)
	var listed: Array[Dictionary] = []
	for i in indices.size():
		listed.append(_animation_frame(frame_values[indices[i]], durations[i], animation_fps))
	var played: Array[Dictionary] = []
	played.assign(
		SheetAnimation.ping_pong(listed) if mode == SheetAnimation.Mode.PING_PONG else listed
	)
	var mode_name := "loop"
	var direction := "reverse" if indices[-1] < indices[0] else "forward"
	if mode == SheetAnimation.Mode.PING_PONG:
		mode_name = "ping_pong"
		direction = "pingpong"
	elif mode == SheetAnimation.Mode.ONCE:
		mode_name = "once"
	var color: Color = animation.get("color", SheetAnimation.NO_COLOR)
	return {
		## Its name
		"name": animation.name,
		## Its colour, like Aseprite writes a tag's: "#rrggbbff", in lower case. Nothing
		## for the "default" animation of a sheet without any.
		"color": _only_if(color.a > 0, "#" + color.to_html(true)),
		## Frames per second: its own speed, or else the export's
		"fps": animation_fps,
		## How it plays: "loop", "ping_pong" (forward then back, again and again) or "once",
		## and each as a boolean. "loop" is true for ping-pong too, as it plays on.
		"mode": mode_name,
		"loop": mode != SheetAnimation.Mode.ONCE,
		"ping_pong": mode == SheetAnimation.Mode.PING_PONG,
		"once": mode == SheetAnimation.Mode.ONCE,
		## Its frames in playing order, see [method _animation_frame]
		"frames": listed,
		## How many frames it has
		"frame_count": listed.size(),
		## Its frames in the order one cycle shows them: ping-pong goes back too, without
		## repeating the ends
		"played_frames": played,
		## Its frames as an Aseprite frame tag: the positions of its first and last frames,
		## the lower one first, and "forward", "reverse" (when the last comes first) or
		## "pingpong". Scattered frames span from the first to the last.
		"from": mini(indices[0], indices[-1]),
		"to": maxi(indices[0], indices[-1]),
		"direction": direction,
		## Whether its last frame comes before its first, even when it ping-pongs
		"reversed": indices[-1] < indices[0],
		## The cells (see [method _frame]) of the frames at from and to, for formats that
		## play a range of tiles
		"from_cell": frame_values[mini(indices[0], indices[-1])].cell,
		"to_cell": frame_values[maxi(indices[0], indices[-1])].cell,
	}


## A frame of an animation: the frame's values (see [method _frame], so "index" is its
## position among the export's frames) with how long it's shown in this animation
static func _animation_frame(frame: Dictionary, held: float, fps: float) -> Dictionary:
	var result := frame.duplicate()
	## How many frames at the animation's speed it's shown for: 2 shows it twice as long
	result.relative_duration = held
	## How long it's shown in milliseconds, at the animation's speed
	result.duration = null
	if fps > 0:
		result.duration = roundi(1000.0 * held / fps)
	return result


## [param value] when [param condition] holds, else nothing
static func _only_if(condition: bool, value: Variant) -> Variant:
	return value if condition else null
