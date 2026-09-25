# Changelog

All notable changes to spritesheetbelli. The version is set in `project.godot`
(`application/config/version`) and shown in Help > About.

## Unreleased

### Added
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
- Rows: Frame > Insert Row (Ctrl+Insert), Remove Row (Ctrl+Shift+Delete) and Move Row
  Up/Down (Ctrl+Shift+Up/Down). Row names, locked cells and animations move along.
- Mirror an animation in the Animations window: its frames are flipped into a new row
  and a copy of the animation plays them, named walk_left for walk_right.
- Onion skin in the animation players: a button shows the previous frame faintly behind
  the current one.
- History panel (View > History, Ctrl+H): every undo step; click one to go back to it.
- Progress overlay for slow work, such as resizing many big sprites, which now happens
  on worker threads.
- Error dialogs when an image would be bigger than Godot or the format allows.
- Frames can be moved inside their cells: Alt+arrow keys nudge the selected frames by a
  pixel (8 with Shift), Frame > Align to Bottom (B) lines up their feet and Frame > Centre
  in Cell (C) puts them back in the middle. Cells grow to hold them, and projects keep
  where every frame is.

### Changed
- A toolbar above the preview: select and move tools (Q, W), select all/none with the
  selection count, and zoom buttons around the zoom level, which fits the view.
- The animation player has back to start, previous frame, play/pause and next frame.
- Animation frames are typed as sprite numbers and ranges, such as 0-3, 5, 9-7.
- Clicking a setting's label opens, toggles or focuses its control.
- Locked cells show a lock instead of diagonal lines.
- JSON exports list the frames of every animation in playing order (`meta.animations`),
  which frame tags can't do for scattered frames, and packed atlas JSON now has frame
  tags and durations too. Opening such a JSON brings the exact animations back.
- Packed atlases store frames that look the same only once; their JSON entries share
  the place. Advanced has a power-of-two size option for engines that need one.
- Trimming keeps the pixels where they were in the cell, so trimming all frames of an
  animation shrinks the cells without making it jump. Flipping and rotating move a
  nudged frame with it.
- Offset and spacing in Add Spritesheet are hidden until needed.
- One Export dialog (Ctrl+E) replaces Export Image, Export As, Export Sprites, Export
  Packed Atlas and Export Settings. It asks what to export (spritesheet image, sprites,
  Godot SpriteFrames, Aseprite/TexturePacker JSON or a packed atlas) and shows only the
  settings that matter, with padding, spacing and extrusion under Advanced. Exports
  always ask where to save, so only projects are overwritten without asking.

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
