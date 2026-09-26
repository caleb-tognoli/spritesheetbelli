# Changelog

All notable changes to spritesheetbelli. The version is set in `project.godot`
(`application/config/version`) and shown in Help > About.

## Unreleased

### Added
- The packed layout: instead of a grid, frames can be packed tightly on pages like a
  texture atlas, and edited there with every tool. Switch with Grid / Packed in the
  sidebar or View. The move tool drags frames anywhere on a page or onto a new one;
  frames that would land on others stay put. Moved frames are pinned, and Frame > Pinned
  pins or unpins them. The sidebar has the atlas settings: page size, keeping places or
  always packing tightly, how frames are placed (five MaxRects rules), spacing, padding,
  extrusion, turning frames to fit and trimming. Sharing identical frames and
  power-of-two or square pages are in Settings > Atlas, for every sheet, and the size
  the data file gives each frame (its cell or its own) is in the Export dialog. The
  button next to Packed packs everything but pinned frames again. Frames that grow or
  are added go in the free space; frames too big for a page get one of their own.
- Opening a packed sheet keeps its layout: every frame stays where it is in the image,
  with its name and pivot, so exporting it again keeps the places engines know. The Add
  Spritesheet window has "Keep the packed layout" for this, also for sprites found
  without a data file.
- libGDX / Spine `.atlas` files open like JSON ones, every page of a Phaser multi-atlas
  is read, and TexturePacker multipacks open whole.
- Packed atlases can be exported with TexturePacker JSON as a hash or an array, a Phaser 3
  multi-atlas, a libGDX / Spine `.atlas` with every page, Sparrow / Starling XML or a
  Godot SpriteFrames using every page (with margins for trimmed frames). Pages are
  numbered when there are more than one, turned frames are stored the way each engine
  expects, and frame names are made unique.
- Pivots: a pivot mode (E) drags the pivot of the selected frames, and Frame > Pivot has
  presets. Pivots follow flips and turns, stay on their pixel when trimming, and are
  exported where the format has them. Frames without one use the atlas's default.
- View > Sprites lists every frame with a thumbnail, its name and size. Selection follows
  the preview both ways, double-click or F2 renames a frame, and frames can be searched
  and pinned.
- Command line: `--layout grid|packed`, `--max-size`, `--rotate` and `--repack`, and
  `--atlas-data` takes every format above. Packed sheets are written as atlases.
- Packed spritesheets with a data file: opening or adding an image that has a
  TexturePacker or Aseprite `.json` next to it (or opening the `.json` itself) cuts the
  frames where the data says. Trimmed and rotated frames come back as they were drawn,
  and frame tags become named rows and animations. Add Spritesheet can still cut a grid
  instead.
- Add Spritesheet can find the sprites in a packed sheet without a data file: every group
  of pixels surrounded by transparency (or by the background colour in the corners) is a
  frame, in rows as they're laid out. Close parts can be joined, and frames can be
  aligned at the bottom so characters stand on one line.
- Animations: make named animations from a range of cells or the selected frames, each
  with its own speed and type (once, loop or ping-pong), in View > Animations… or with
  the button on the animation preview. The preview can play any of them. Exports use
  them: SpriteFrames get their speed and looping, JSON gets frame tags.
- Frames can be shown longer than others: in an animation's frames, `4*2` shows sprite 4
  for two frames and `5*0.5` for half of one. The preview plays them that way, Godot
  SpriteFrames get each frame's duration, JSON gets milliseconds per frame, and
  durations from Aseprite JSON are kept. The Animations window shows how long a cycle
  takes.
- File > Export Again (Ctrl+Shift+E) repeats the last export to the same place without
  asking. Projects remember where that was.
- Animated GIFs can be opened, added as a spritesheet or dropped: the frames go in a
  new row named after the file, with an animation at the GIF's speed and frame times.
  Adding a GIF as sprites adds every frame.
- Export an animation as an animated GIF, scaled up with sharp pixels. It plays like the
  animation: its speed, frame durations, ping-pong and play-once.
- Frame > Add Outline… draws an outline of any colour and thickness around the selected
  frames, with round or square corners.
- Rows: Frame > Rows has Insert Row (Ctrl+Insert), Remove Row (Ctrl+Shift+Delete) and
  Move Row Up/Down (Ctrl+Shift+Up/Down). Row names, locked cells and animations move
  along.
- Mirror an animation in the Animations window: its frames are flipped into a new row
  and a copy of the animation plays them, named walk_left for walk_right.
- Onion skin in the animation players: a button shows the previous frame faintly behind
  the current one.
- History panel (View > History, Ctrl+H): every undo step; click one to go back to it.
- Progress overlay for slow work, such as resizing many big sprites, which now happens
  on worker threads.
- Error dialogs when an image would be bigger than Godot or the format allows.
- Frames can be moved inside their cells: in the move mode, arrow keys move the selected
  frames by a pixel (8 with Shift), and Frame > Align in Cell puts them against the top,
  bottom, left or right of their cells or in the middle (Alt+T, B, L, R, C). Cells grow to hold moved
  frames, and projects keep where every frame is.
- Linked files: sprites, spritesheets and GIFs remember the file (and the place in it) they
  came from. When a linked file changes on disk, a dialog asks whether to reload it,
  keeping the edits made here (flip, rotate, trim, background colour, outline, moves in the
  cell) or resetting to the file, or to ignore it; with several changed files, the answer
  can go for all of them as one undo step. Frame > Reload from File reloads the selected
  frames by hand. Projects keep the links, so files changed while a project was closed are
  noticed when it's opened. Exporting over a linked file unlinks its frames. Can be turned
  off in Settings.
- Command line: `--cut <image>` cuts a spritesheet (grid, data file or `--detect`) or
  an animated GIF; `--atlas` writes a packed atlas; an `--out` ending in `.gif` writes an
  animated GIF (`--animation`, `--scale`); `--pack` takes GIFs too.

### Changed
- Copy, paste, duplicate, mirrored animations and Add Spritesheet copy a frame's origin,
  pivot and link, not just its pixels.
- Grid actions (cells and rows) are left out of the menus and the toolbar in the packed
  layout.
- The toolbar wraps onto more rows when the preview is narrow, and has a button for the
  list of sprites.
- A toolbar above the preview: select and move tools (Q, W), select all/none, flip and
  rotate, Align in Cell and Trim, toggles for grid lines (G), frame numbers (N) and the
  animation preview (P), and zoom buttons around the zoom level, which fits the view.
- The right-click menu groups flipping and rotating under Transform, and has Align in
  Cell and Rows submenus.
- The animation player has back to start, previous frame, play/pause and next frame.
- Animation frames are typed as sprite numbers and ranges, such as 0-3, 5, 9-7, or by
  name: idle, walk_0-walk_3, "jump up"*2. The Names button shows them by name.
- Tooltips of linked frames show the file's path.
- Clicking a setting's label opens, toggles or focuses its control.
- Locked cells show a lock instead of diagonal lines.
- JSON exports list the frames of every animation in playing order (`meta.animations`),
  which frame tags can't do for scattered frames, and packed atlas JSON now has frame
  tags and durations too. Opening such a JSON brings the exact animations back.
- Packed atlases store frames that look the same only once; their JSON entries share
  the place. Pages can be powers of two (Settings > Atlas) for engines that need it, and
  the data file can be a libGDX / Spine `.atlas` instead of JSON (`--atlas-data atlas` on
  the command line).
- Trimming keeps the pixels where they were in the cell, so trimming all frames of an
  animation shrinks the cells without making it jump. Flipping and rotating move a
  nudged frame with it.
- Offset and spacing in Add Spritesheet are hidden until needed.
- Removing a background colour and adding outlines work on worker threads, with the
  progress overlay when they take a while.
- One Export dialog (Ctrl+E) replaces Export Image, Export As, Export Sprites, Export
  Packed Atlas and Export Settings. It asks what to export (spritesheet image, sprites,
  Godot SpriteFrames, Aseprite/TexturePacker JSON or a packed atlas) and shows only the
  settings that matter, with padding, spacing and extrusion under Advanced. Exports
  always ask where to save, so only projects are overwritten without asking.

### Fixed
- The sidebar's resize bar ending up under the preview when the preview was narrower than
  its toolbar.
- Picking a resize filter at the original size switching back to the one from the
  settings. The filter chosen in the settings is now the one new sheets start with.

## 0.2.0

### Added
- Projects: save and reopen `.sbelli` files with every frame at its original size, the
  grid, locked cells, scale, row names and export settings.
- Undo and redo for every edit.
- Export Image, Export Image As, Export Sprites and Export Packed Atlas, with export
  settings: background colour, sprite file-name patterns, only selected frames, what to
  do with existing files, and advanced padding, spacing and edge extrusion.
- Metadata for game engines: TexturePacker-style JSON with Aseprite-style tags, or a
  Godot SpriteFrames `.tres` with one animation per named row.
- Animation preview (P) with loop, ping-pong and play-once.
- Cut, copy, paste (also images copied in other apps), duplicate, replace image, insert
  and remove cells, trim transparent borders and remove a background colour.
- Drag frames to move them (Alt+drag copies); box selection, Shift and Ctrl clicks, and
  arrow keys.
- Named rows, shown next to the grid and used in exports.
- Offset and spacing when slicing a spritesheet, with a warning when it doesn't divide
  evenly, and a smarter grid-size guess.
- Drag and drop files and folders; File > Add Folder; File > Open Recent.
- Settings: where sprites are added, resize filter, numbering from 0 or 1, preview
  colours, JPG options, theme, accent colour, interface scale and more.
- Light theme, accent colour, logo, app icons and a boot splash.
- Resizable sidebar, status bar, zoom presets, toasts and an empty-state hint.
- Command-line mode for build pipelines (`--pack`, `--export`).
- Keyboard shortcuts for every action (F1 lists them) and an About dialog.
- Tests, CI and a formatter/linter setup.

### Changed
- Upgraded to Godot 4.7.2 with the Compatibility renderer.
- Resizing is non-destructive and can keep pixel art sharp.
- Images load in the background with a progress bar; large sheets draw and open faster.
- New shortcuts: Ctrl+A selects all (was Add Sprites), Ctrl+I adds sprites, Ctrl+Q quits.

### Fixed
- Sprites being added twice, and in reverse order.
- Frame numbers not scaling with zoom.
- Exported sprites numbered in the wrong order.
- JPG export turning transparency black.
- Clearing a grid field deleting every sprite.
- Rotating frames growing the sheet permanently.
- Add Spritesheet locking free cells of the whole sheet.
- Opening a file marking it as changed; closing without asking about unsaved changes.
- Keep-aspect resizing drifting; the save message naming the folder; the right-click menu
  position with display scaling.

## 0.1.0

First version: combine sprites into a spritesheet, cut spritesheets into frames, flip,
rotate and export.
