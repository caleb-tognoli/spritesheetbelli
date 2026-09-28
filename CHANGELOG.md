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
  extrusion (in a panel that drops down), and toggles for turning frames to fit and
  trimming transparent borders next to Repack, which packs everything but pinned frames
  again. Sharing identical frames and
  power-of-two or square pages are in Settings > Atlas, for every sheet, and the size
  the data file gives each frame (its cell or its own) is in the Export dialog. Frames
  that grow or
  are added go in the free space; frames too big for a page get one of their own.
  Unpinning a frame also unpins the frames that share its place, and when always packing
  tightly it goes back among the others.
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
- Pivots, turned on in Settings > General: a pivot mode (E) drags the pivot of the
  selected frames, and Frame > Pivot has presets, top left and bottom left included. Pivots follow flips and turns, stay on their pixel when trimming, and are
  exported where the format has them. Frames without one use the atlas's default.
- View > Sprites lists every frame with a thumbnail, its name and size, under the first
  animation showing it, in play order, with a dot of the animation's colour, and the
  others under "No animation"; in the grid layout, the button next to the search field
  groups them by row instead, numbered like the frames. Clicking
  a group's name selects its frames, and its arrow folds it. Selection follows the preview both ways,
  double-click a name or F2 renames a frame, and frames can be searched and pinned.
- Command line: `--layout grid|packed`, `--max-size`, `--rotate` and `--repack`, and
  `--atlas-data` takes every format above. Packed sheets are written as atlases.
- Packed spritesheets with a data file: opening or adding an image that has a
  TexturePacker or Aseprite `.json` next to it (or opening the `.json` itself) cuts the
  frames where the data says. Trimmed and rotated frames come back as they were drawn,
  and frame tags become animations, each in a row of its own. Add Spritesheet can still cut a grid
  instead.
- Add Spritesheet can find the sprites in a packed sheet without a data file: every group
  of pixels surrounded by transparency (or by the background colour in the corners) is a
  frame, in rows as they're laid out. Close parts can be joined, and frames can be
  aligned at the bottom so characters stand on one line.
- Animations: make named animations from a range of cells or the selected frames, each
  with its own speed and type (once, loop or ping-pong), in the animation panel under
  the preview, which can play any of them. Exports use
  them: SpriteFrames get their speed and looping, JSON gets frame tags.
- Frames can be shown longer than others: in an animation's frames, `4*2` shows sprite 4
  for two frames and `5*0.5` for half of one. The preview plays them that way, Godot
  SpriteFrames get each frame's duration, JSON gets milliseconds per frame, and
  durations from Aseprite JSON are kept. The animation panel shows how long a cycle
  takes.
- File > Export Again (Ctrl+Shift+E) repeats the last export to the same place without
  asking. Projects remember where that was.
- Animated GIFs can be opened, added as a spritesheet or dropped: the frames go in a
  new row, with an animation named after the file at the GIF's speed and frame times.
  Adding a GIF as sprites adds every frame and the animation too.
- Export an animation as an animated GIF, scaled up with sharp pixels. It plays like the
  animation: its speed, frame durations, ping-pong and play-once.
- Frame > Add Outline… draws an outline of any colour and thickness around the selected
  frames, with round or square corners.
- Rows: Frame > Rows has Insert Row (Ctrl+Insert), Remove Row (Ctrl+Shift+Delete) and
  Move Row Up/Down (Ctrl+Shift+Up/Down). Locked cells and animations move along.
- Mirror an animation in the animation panel: its frames are flipped into a new row
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
- Add Spritesheet has "Lock empty cells" next to its buttons, shown when the sheet has
  empty cells, on by default and remembered. Turned off, the added sheet's empty cells
  aren't locked, so added sprites can fill them.
- Projects save the zoom and where the preview was looking, and open there again, also in
  a window of another size. Looking around alone doesn't make a project unsaved; the view
  is saved with the next save.
- Settings > Preview > Pixel-perfect zoom: Auto, On or Off. When it applies, Fit to View
  rounds down to a whole zoom (200%, 300%… or 50%, 33%, 25%… below 100%) and the zoom
  buttons, shortcuts and wheel step through whole zooms, so every pixel is the same size
  on screen, in the preview and the Add Spritesheet window. Auto applies when the sheet's
  resize filter is Nearest.
- Settings > Preview > Selection tint sets how strongly the accent colour covers selected
  frames, from 0% (only their outline) to 100%; the default 25% looks as before. It
  applies to the preview and to Add Spritesheet.
- An animation's Frames field reports numbers past the end of the sheet as "outside the
  sheet", apart from the empty cells that are skipped.
- Both sidebars (the settings on the left, the sprites and history on the right) have a
  visible handle on their inner edge: drag it to make them wider, double-click it to make
  them as narrow as they can be again. Their width is remembered.
- The window opens where it was left: same size, place, screen and maximised state. The
  first time, it takes 80% of the screen, centred, or is maximised on small screens.
- Shortcuts for Frame > Pinned (K, in the packed layout) and showing or hiding the
  Sprites panel (Ctrl+L).
- File name tokens `{animation}` (the first animation a frame is in, or "frame") and
  `{animation_frame}` (its place in that animation, numbered like the others), e.g.
  `{animation}_{animation_frame:2}` gives walk_00, walk_01….
- Animation panel: animations get a panel under the preview, between the sidebars, in
  place of the small player over the preview and the Animations window: the preview, the
  list of animations (with the selected frames, or every frame, at the top) and the
  chosen animation's details, side by side. Drag its top edge to make it taller (up to
  half the window, remembered) and the separators between its parts. P or the arrow
  collapses it to a bar with the name of what plays and play/pause; it stays collapsed
  until a sheet has animations, then opens once. Frames can still be selected while it's
  open.
- The animation preview zooms with the wheel (by whole steps with pixel-perfect zoom) and
  fits again with a button or a double-click, pans when zoomed in, has a scrub bar to drag
  through the frames or click to one, and shows the frames over a checkerboard, a colour
  or the export background.
- Animation from Row (F2), Animation from Column (Shift+F2) and Animation from Selection
  (Ctrl+F2), also in the preview's right-click menu and, for the selection, the Sprites
  panel's: they ask for a name, starting as what the frames' names begin with (slime_walk
  from slime_walk_00 to slime_walk_05, or "animation"), skip empty cells and choose the
  new animation in the animation panel. When an animation already has exactly those
  frames, it's renamed instead. Rows and columns are the right-clicked cell's, or the
  first selected frame's, in the grid layout.
- An Animation menu with these, Edit, Mirror Animation and Delete Animation (of the
  animation chosen in the animation panel), Animation Panel (P) and Onion Skin.
- The grid names animations: an animation that is exactly one row is named in the left
  margin (the right one when it runs right to left), one that is exactly one column above
  it (below when it runs upwards); empty cells don't count. Any other connected run or
  area, such as part of a row, a rectangle, 8 frames in 6 columns or an L-shape, is
  outlined with the name on the edge at its first frame. Frames shown twice count once;
  scattered or out-of-order animations aren't named. Names and outlines are drawn in
  their animation's colour; where they overlap, names stack in their margin and outlines
  around the same frames are drawn further inside, with the playing one on top.
  Names are never drawn over each other or over frame numbers, and Fit to View leaves
  room for them.
- A toolbar button next to the view toggles, and Animation > Animation Labels…, choose
  which animations are named: an eye for each, Show all, Hide all and Only the playing
  animation, and how many more can't be named. The choices are saved in the project and
  can be undone. Not in the packed layout.
- Clicking an animation's name on the grid selects its frames and plays it,
  double-clicking renames it, right-clicking offers Rename, Edit, Speed, Type, Mirror,
  Hide Label and Delete, and hovering highlights its frames and tells its length, speed
  and type.
- The animation panel's details show the chosen animation's frames on a timeline: each
  frame with its picture, its place, the part of its name that differs from the others
  and how long it's shown (×1.0). Frames are dragged into another order, taken out with ×
  or Delete, picked with Ctrl, Shift or a box, and added by dragging them from the sheet
  or the Sprites panel, several at once, or with Add selected. Every change is a step to
  undo. The name, speed and type share one line above it; the typed frames (`0-3, 4*2`)
  are one button away.
- Every animation has a colour of its own, picked far from the others' when it's made and
  saved with the project. Change it with the colour button in the animation details, or
  with Colour… on its name on the grid. The animation list shows each one's colour.
  Animations made from Aseprite tags take the tag's colour, unless it's Aseprite's default
  black.
- Add Folder and dropping a folder link it, even one with no images yet: images added to
  it later are added as
  sprites where *New sprites go to* says, as one undo step, with a notice. Deleting images
  from a linked folder asks whether to remove their frames, and renamed images are
  followed: their frames link to the new name without asking. Linked folders are listed
  at the top of the Sprites panel, with *Unlink folder*, saved in the project and followed
  again when it's opened. *Reload changed files* turns this off too. Not in the web
  version.
- View > Pixel Grid (Shift+G) draws faint lines between pixels once you zoom in to 600%
  or more. The lines follow each frame's own pixels, so a frame scaled 2× gets a line
  every two pixels of the sheet. It's on by default and can also be turned off in
  Settings > Preview.
- While you hover a frame, the status bar shows the pixel under the mouse in the frame
  and on the exported sheet (or on its page, when packed on several), with its colour,
  like "3, 5 in the frame (35, 5 on the sheet) · #41d88f, alpha 255". Scaled, flipped,
  trimmed and turned frames give their own pixels.
- Add Spritesheet sets the Grid cut by cell size as well as by columns and rows. Editing
  one sets the other, and whichever was edited last is kept when the offset or spacing
  change. Pixels that don't divide evenly, including spacing after the last cell, show
  as "N px on the right not used" instead of making the cells bigger, so a 24×24 grid
  with an offset and spacing no longer cuts 24×25 frames with a strip of background. Set
  by columns and rows, spacing after the last column or row is left over too when
  there's only background in it. A
  sprite size in the file name, like `hero_24x24.png`, fills in the cell size. The
  toolbar wraps onto a second line in a narrow window, and shows the number of frames
  for the Grid cut.
- Add Spritesheet notices when a sheet is drawn on a solid colour instead of
  transparency, like magenta, and makes it transparent: the grid is guessed and sprites
  are found as if it were, and frames come in without it. "Make [colour] transparent" is
  on for such sheets, with a tolerance. The colour can be chosen by hand for any sheet,
  with the colour picker or by clicking the preview with the eyedropper, and the preview
  updates as you go. Reloading a linked sheet makes its background transparent again.
- Add Spritesheet's Find sprites shows the image with a numbered box over each sprite,
  numbered in the order the frames are added, and the boxes can be edited: click to
  select (Shift or Ctrl for several), drag inside to move, drag an edge or corner to
  resize, drag on empty space to draw a new box, Delete to remove, and Merge (or
  Ctrl+drag across boxes) to join them. Boxes snap to whole pixels and stay in the image.
  Ctrl+Z undoes box edits in the window. The boxes are what's added, aligned and kept in
  the packed layout as before, and reloading the file cuts the same boxes again. Changing
  Join parts within or the colour made transparent finds the sprites again; Undo brings
  back boxes edited by hand, and Find Again starts over.

### Changed
- Copy, paste, duplicate, mirrored animations and Add Spritesheet copy a frame's origin,
  pivot and link, not just its pixels.
- The grid section of the sidebar has spacing, padding and extruded edges for exports too,
  in the same drop-down panel as the atlas and Add Spritesheet's offset and spacing, with
  a button to reset each. The preview shows them as the export will: cells apart, the
  padding around, and frames' edges extruded.
- Packed sheets can be exported as images too, one per page.
- Export is at the top of the sidebar, with the size of what it writes under it.
- The export background is a single colour picker, transparent unless a colour is picked.
  JPG quality and fill colour are set in the Export dialog only, not in Settings.
- Add Spritesheet warns about a grid that doesn't divide the image in the bottom-right
  corner of the preview, with a warning icon, so the bar above keeps its layout.
- The history has a toolbar button, after the sprites list.
- Settings have short names; hovering one says what it does.
- Grid actions (cells and rows) are left out of the menus and the toolbar in the packed
  layout.
- The toolbar wraps onto more rows when the preview is narrow, and has a button for the
  list of sprites. Align in Cell, Pivot, Trim and Pinned come first and work on every
  frame when none are selected; Select All and Select None are in the Edit menu only.
- A toolbar above the preview: select and move tools (Q, W), select all/none, flip and
  rotate, Align in Cell and Trim, toggles for grid lines (G), frame numbers (N) and the
  animation panel (P). Zoom floats over the top-right corner of the preview, like in
  Godot: a button fits the view, and clicking the zoom level goes back to 100%.
- The right-click menu groups flipping and rotating under Transform, and has Align in
  Cell and Rows submenus.
- The animation player has back to start, previous frame, play/pause and next frame.
- Animation frames can also be typed as sprite numbers and ranges, such as 0-3, 5, 9-7,
  or by name: idle, walk_0-walk_3, "jump up"*2. Frames with a name of their own are
  shown by it.
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
  settings that matter. Exports
  always ask where to save, so only projects are overwritten without asking.
- Changing the export settings is no longer a step in the History, so Ctrl+Z after
  exporting undoes the last edit. They still count as unsaved changes. Spacing, padding
  and extruded edges set in the sidebar are still undone like the rest of the layout.
- Toolbar and sidebar buttons show the name and current shortcut of their action, like
  "Export (Ctrl+E)", with what it does on the next line where that helps. Align in Cell,
  Pivot, Trim and Pinned say they work on every frame when none are selected.
- Keyboard Shortcuts (F1) also lists panning with Space+drag, Ctrl+click, Shift+click,
  copying with Alt+drag, locking cells and the right-click menu. The README no longer
  lists shortcuts and points to F1 instead.
- Adding a GIF with Add Sprites also makes its animation, like Add Spritesheet and
  dropping it do.
- In the web version, Open and Add Spritesheet accept spritesheet data files
  (TexturePacker, Aseprite, Phaser, libGDX), picked together with their image.
- Icons follow the theme like in the Godot editor: the light theme swaps their greys for
  darker ones instead of tinting them, so icons in several greys such as Align in Cell and
  the zoom buttons keep their parts. Pressed toggles show the accent colour in both
  themes, and menu and dropdown arrows follow the theme.
- Repack and Frame > Pack Again have their own icon instead of a circular arrow like
  Turn frames to fit.
- New and empty sheets show at 100%, and a sheet opened without a saved view (an image,
  atlas or GIF) shows whole.
- The Add Spritesheet preview shows the whole sheet again when Cut or Keep the packed
  layout changes; grid sizes, offset, spacing and the Find sprites settings keep the zoom.
- The Move tool shows the move cursor wherever dragging would move frames: anywhere while
  frames are selected, since the selection moves from wherever it's dragged, else over a
  frame.
- Pressing with the Move tool picks the frames up right away: they leave their places and
  are shown see-through where they'd land, in the grid and the packed layout. Releasing
  without dragging moves nothing; Alt+dragging in the grid keeps the copied frames in
  their cells.
- Dialog buttons sit together at the right, at least 88 px wide (the standard on
  Windows), in the platform's order: OK before Cancel on Windows, after it on macOS and
  Linux. Other buttons (Reset All…, Don't Save, Add selected frames) go to their left.
  Add Spritesheet has a Cancel button, Escape cancels it, and "Lock empty cells" moves to
  the left of its buttons.
- The status bar shows the file a frame comes from as its folder and name; the preview's
  tooltip still has the whole path. When the status bar is full, the path is cut first.
- The window can be made as small as 960×600, scaled with the interface.
- Selected rows in the Sprites, History, Settings, Export and Animations lists are in the
  accent colour, a little stronger while the list has focus, in both themes; hovering stays
  neutral. Their text stays readable with any accent colour picked in Settings.
- Only animations are exported as animations: JSON frame tags, Godot SpriteFrames and
  atlases have the sheet's animations, and without any, SpriteFrames get every frame in
  one "default" animation.
- The export's format decides the file's extension, and only that extension is taken off
  the typed name: hero as JPG gives hero.jpg, hero.png as JPG gives hero.png.jpg, and
  hero.png as PNG stays hero.png (so does HERO.PNG, and .jpeg or .jpe for JPG), so the
  file named in the save dialog is the one written. Data files and atlas pages are named
  after the image without its extension (hero.png gives hero.json), and the same goes for
  GIFs, sprite name patterns ({index}.png names 0.png), Export Again and the command
  line's --out, whose extension picks the image format.
- Animations… becomes Animation > Edit: it opens the animation panel at the chosen
  animation's details. The panel's toggle (P) moved from View to the Animation menu too.
- Animations given a free name (New, Mirror, GIFs and Add Spritesheet) are numbered like
  the names Animation from Row suggests: walk_2, walk_3, not walk2. A name that already
  ends in a number counts on from it, so walk_2 gives walk_3.
- Add Spritesheet opens in Grid when the sheet is in the Grid layout and in Find sprites
  when it's in the Packed layout. A data file next to the image still opens it cut where
  the data file says.
- Remove Background Colour opens a small panel over the preview instead of a dialog, with
  the same colour, eyedropper and tolerance as Add Spritesheet. While it's open, the
  selected frames are shown with the colour removed, and frames can still be selected and
  the view moved. Nothing changes until Remove, which is one step to undo; Cancel or
  Escape leaves the frames as they were. The eyedropper picks the colour by clicking a
  frame, as the frame is, not as previewed.

### Removed
- Named rows: Frame > Rows > Name Row… (F2), double-clicking left of a row, the names
  left of the grid and the row headers in the Sprites list. Animations are the only way
  to group frames; exports no longer make an animation of every row, or name rows
  "row0", "row1"….
- The `{row_name}` file name token.

### Fixed
- Godot's warning about rounded popup corners: windows may use per-pixel transparency.
- The status bar's note about locked cells shows its tooltip again.
- The sidebar's resize bar ending up under the preview when the preview was narrower than
  its toolbar.
- Picking a resize filter at the original size switching back to the one from the
  settings. The filter chosen in the settings is now the one new sheets start with.
- Save As and Export no longer suggest an empty name or `spritesheet.png` in the app's
  folder for a sheet made from sprites or opened from a GIF: they suggest the first
  sprite's name, in its folder (e.g. `walk_0.sbelli` next to `walk_0.png`). A cancelled
  save or export dialog no longer leaves the next one without a name.
- The window title of an unsaved new sheet no longer reads "(*) - spritesheetbelli": it
  shows the first sprite's file, or "Untitled".
- The folder picker for exporting sprites is titled Export Sprites and starts next to the
  sheet's files.
- Add Sprites lists GIFs, and the web version accepts them too.
- In the light theme, the Sprites, History, Settings, Export and Animations lists no
  longer look disabled, pins in the Sprites list are visible, and the Shortcuts headings,
  the Animations frames error and the empty preview's hint are readable.
- The interface scale applies to dialogs and other separate windows (Settings, Export,
  Add Spritesheet, File Changed, confirmations, colour pickers), not just the main
  window, also when it changes while they're open. Dropdown panels such as Spacing &
  Padding open right below their button at any scale.
- The Sprites list highlights a selected frame's whole row, size and pin included, as one
  box; the keyboard cursor's box shows only while the list has focus, on the first frame
  selected in the preview.
- Opening a project kept the previous sheet's zoom, which could cut the new one off; New
  kept it too.
- Switching Add Spritesheet from Grid to Find sprites could leave frames off-screen.
- Opening a project, an image or a GIF, and New, start with nothing selected; the
  selection of the previous document no longer carries over to frames in the same places.
- The status bar kept describing a cell after the mouse left the preview, or after New or
  opening a file.
- The left sidebar changed width when switching between the grid and the packed layout,
  moving the toolbar and the preview.
- Opening the Sprites panel made the panels on the right as narrow as they can be,
  forgetting their width.
- In the web version, dialogs and other windows had a see-through title bar that showed
  the window behind through it; it's now opaque in the dialogs' colour, with the title and
  close button readable in both themes.

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
