# Changelog

All notable changes to spritesheetbelli. The version is set in `project.godot`
(`application/config/version`) and shown in Help > About.

## Unreleased

### Added
- Opening files from the file manager: `.sbelli` projects open with spritesheetbelli by
  default, and images and spritesheet data files offer it in "Open with". Releases have a
  Windows installer, the macOS app declares the file types, and the Linux archive has an
  `install.sh` adding the launcher, the file types and the `spritesheetbelli` command.
  Files given on the command line are opened at start, instead of the last session.
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
- Pivots, turned on in Settings > General: the selected frames and the frame under the
  mouse show their pivot, dragged to move it, with every selected frame's when it's one
  of them, always inside the frame. Frame > Pivot has presets, top left and bottom left included.
  Pivots follow flips and turns, stay on their pixel when trimming, and are exported where
  the format has them, for atlases and grid sheets with a data file, only while they're
  turned on. Frames without one use the atlas's default. Unity's `.tpsheet`, which always
  needs one, turns frames around the middle of the whole frame while pivots are off, so
  trimmed frames of an animation stay in place.
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
- Export targets: a project keeps a list of exports, each with its own settings and the
  file it writes, saved relative to the project. The Export dialog lists them on the
  left, with Add, Duplicate and Remove, and the selected one's settings and Export to path
  (with Browse…) on the right; Export writes the selected one and Export All every one.
  File > Export Again (Ctrl+Shift+E) writes them all without asking, and opens the dialog
  when there are none. The sidebar's Export button shows how many there are. In the web
  version they download instead.
- Command line: `--export project.sbelli` without `--out` or `--sprites` writes every
  export of the project, set up in the Export dialog.
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
- Frames can be moved inside their cells: arrow keys move the selected frames by a pixel
  (8 with Shift), and Frame > Align in Cell puts them against the top,
  bottom, left or right of their cells or in the middle (Alt+T, B, L, R, C). Both trim
  the frames' transparent borders first, so it's what's drawn that lines up, and only
  what's drawn grows the cells when moved past them. Projects keep where every frame is.
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
  resize filter is Nearest. With the interface scaled, whole zooms are whole screen
  pixels: at 150%, 67%, 133%, 200%, 267%…, and Actual Size goes to the nearest one
  (133%); at 100% and 200% they're as before.
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
  list of animations (with the selected frames, or every frame, at the top) and the chosen
  animation's details, side by side. It's a dock, like Godot's bottom panel: the Animation
  button (with its icon) in the row under the preview, or P, shows or hides it; it stays
  hidden until a sheet has animations, then opens once. Drag its top edge to make it
  taller (up to half the window, remembered) and the separators between its parts. Frames
  can still be selected while it's open.
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
- An Animation menu with these, Edit, Duplicate, Mirror and Delete Animation (of the
  animation chosen in the animation panel), Animation Panel (P) and Onion Skin.
- The grid names animations: an animation that is exactly one row is named in the left
  margin (the right one when it starts nearer the right), one that is exactly one column
  above it (below when it starts nearer the bottom); empty cells don't count. Any other
  connected area, such as part of a row, a rectangle, 8 frames in 6 columns or an
  L-shape, is outlined with the name on the edge at its first frame; outlines take in
  empty cells between its frames, so a rectangle with a frame missing is still one, and
  a row with a gap is one outline. The order of the
  frames doesn't matter, and frames shown twice count once; scattered animations aren't
  named. Names and outlines are drawn in
  their animation's colour; where they overlap, names stack in their margin and outlines
  around the same frames are drawn further inside, with the playing one on top.
  Names are never drawn over each other or over frame numbers, and Fit to View leaves
  room for them.
- A toolbar button next to the view toggles, and Animation > Animation Labels…, choose
  which animations are named: an eye for each, Show all, Hide all and Only the playing
  animation, and how many more can't be named. The choices are saved in the project and
  can be undone. Not in the packed layout.
- Clicking an animation's name on the grid selects its frames and plays it,
  double-clicking renames it, right-clicking offers Rename, Edit, Speed, Type, Duplicate,
  Mirror, Hide Label and Delete, and hovering highlights its frames and tells its length,
  speed and type.
- The animation panel's details show the chosen animation's frames on a timeline: each
  frame with its picture, its place, the part of its name that differs from the others
  and how long it's shown (×1.0). Frames are dragged into another order, taken out with ×
  or Delete, copied with Alt+drag, picked with Ctrl, Shift or a box, and added by
  dragging them from the sheet or the Sprites panel, several at once. Frames dropped on
  the details while no animation is chosen, or on the list off the animations, make a new
  one. Every change is a step to undo. The name, speed and type share one line above it; the typed frames (`0-3, 4*2`)
  are one button away.
- Every animation has a colour of its own, picked far from the others' when it's made and
  saved with the project. Change it with the colour button in the animation details, or
  with Colour… on its name on the grid. The animation list shows each one's colour. JSON
  exports write each animation's colour on its frame tag, as Aseprite does. Animations
  made from tags take the tag's colour, even one another animation has, unless it's
  Aseprite's default black.
- Add Folder and dropping a folder link it, even one with no images yet: images added to
  it later are added as sprites where *New sprites go to* says, as one undo step, with a
  notice. Deleting images from a linked folder asks whether to remove their frames, and
  renamed images are followed: their frames link to the new name without asking. Linked
  folders are listed under Add Sprite(s) in the sidebar, each with its name, the folder
  it's in and *Unlink folder*, saved in the project and followed again when it's opened.
  Right-clicking one has Show in File Manager, Copy Path and Unlink Folder. A folder that
  was moved or deleted says "Not found", with Locate… to pick where it is now: its frames
  link to the images of the same name there, and images that are new there are added.
  *Reload changed files* turns this off too; linking a folder while it's off says it's
  paused, and so does the list, with a link to turn it on. Not in the web version.
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
  are found as if it were, and frames come in without it. The eyedropper button in the
  toolbar, in every cut, shows the colour under its icon while it's on, and opens a panel
  to turn it off, choose the colour (with the colour picker, or by clicking the preview
  with the eyedropper) and set a tolerance. The preview updates as you go; Confirm keeps
  it, Cancel puts back what it was. Reloading a linked sheet makes its background
  transparent again.
- Add Spritesheet's Find sprites shows the image with a numbered box over each sprite,
  numbered in the order the frames are added, and the boxes can be edited: click to
  select (Shift or Ctrl for several), drag inside to move, drag an edge or corner to
  resize, drag on empty space to draw a new box, Delete to remove, and Merge (or
  Ctrl+drag across boxes) to join them. Boxes snap to whole pixels and stay in the image.
  Ctrl+Z undoes box edits in the window. The boxes are what's added, aligned and kept in
  the packed layout as before, and reloading the file cuts the same boxes again. Changing
  Join parts within or the colour made transparent finds the sprites again; Undo brings
  back boxes edited by hand, and Reset starts over.
- Duplicate an animation: a copy with the same frames, timing, speed and type, named
  walk_2 after walk, with a colour of its own and its name shown on the grid. New sits
  above the animation list, with Duplicate, Mirror and Delete next to it while an
  animation is chosen; Duplicate is also in the Animation menu and in an animation name's
  right-click menu on the grid.
- The command line's `--cut` makes a solid background colour, like magenta, transparent,
  as Add Spritesheet does, for a grid, a data file and `--detect`. `--keep-background`
  keeps it (the grid and sprites are still found as if it were transparent), and
  `--tolerance <percent>` sets how close a colour must be (10 by default). The tolerance
  chosen in Add Spritesheet or Remove Background Colour is remembered, and both start with
  it next time.
- Custom templates: the Export dialog's Custom template export writes the data file from
  a template file of your own, next to the sheet or with atlas pages. The template's
  header says the file's extension; a template's mistake is shown with its line instead
  of exporting.
- A templates folder (Export dialog > Open templates folder; not in the web version):
  templates put there are listed with the bundled formats, and one named like a bundled
  template (`json.template`) replaces it, marked "(yours)"; taking it out brings the
  bundled one back. It comes with a README and a copy of every bundled template to start
  from.
- Command line: `--template <file>` writes the data file from a template, and `--metadata`
  and `--atlas-data` take any format, templates in the templates folder included.
- More data file formats for game engines: a Unity `.tpsheet` for the free TexturePacker
  Importer package, a Defold tile source (grid sheets, with the animations as tile
  ranges), a Cocos2d-x `.plist` (format 3, with trimmed and turned frames and pivots) and
  CSS or SCSS sprites (a class for every frame, and a Sass map and mixin). Templates get
  the `minus`, `times`, `divide`, `css-ident` and `tpsheet-escape` filters, a grid sheet's
  columns, rows, cell size, padding, spacing and extrusion, each frame's cell, and each
  animation's from_cell, to_cell and reversed.
- A GIF of each animation: "Every animation" in the Animated GIF export's Animation list
  writes a GIF of each animation, at its own speed, into a folder, named with a pattern
  (`{animation}` by default, or with `{count}`). On the command line, `--gifs <folder>`.
- GameMaker strips: a new export writes each animation as a PNG of its frames side by
  side, named like `walk_strip8.png`, which GameMaker's importer cuts into frames. The
  name pattern (like `spr_{animation}_strip{count}`) and a background can be set; frames
  in no animation are left out, and a sheet without animations gives one strip of every
  frame. Strips can be written at several scales too, into the same folder, with the
  suffix before `_strip` (`walk@2x_strip8.png`, which GameMaker names `walk@2x`). On the
  command line, `--strips <folder>`.
- Scale variants: image, data file, atlas, custom template and GameMaker strips exports
  can be written at several scales, like "1, 2". Each is the same sheet that many times
  bigger, with frames resized from their originals with the sheet's filter and padding,
  spacing and extrusion scaled too, and its own data file, named with a suffix
  (`hero@2x.png`, `hero@2x.json`); an atlas's pages are numbered before it
  (`hero_0@2x.png`, `hero_0@2x.json`). CSS and SCSS sprites show the @2x image on
  high-density screens when 2 is among the scales. On the command line, `--scales 1,2`,
  which applies to `--strips` too.
- Theme: a System option, now the default, follows the operating system's dark or light
  mode as it changes, and a System accent colour setting uses the operating system's
  accent colour where it has one, hiding the Accent colour picker meanwhile.
- A start screen while nothing is open, covering the whole window below the menu: the
  name and version, a zone to drop files on with Open, Add Spritesheet, Add Sprite(s) and
  Add Folder, and the recent projects and sheets, up to five in a row, with a thumbnail,
  name, folder and when they were changed ("3 hours ago", with the date and time in the
  tooltip). Click one to open it, or × to take it off the list; moved or deleted files say
  "Not found", with Locate… to pick where the file is now, which takes its place in the
  list and opens it. Right-clicking one has Open, Show in File Manager, Copy Path and
  Remove from Recent Files. The arrow keys move between them, starting on the first,
  Enter opens, Delete takes one off the list and the menu key opens its menu. Thumbnails
  are made when a project is saved or opened, and from the image for sheets. Meanwhile
  the View actions and the tools are greyed out, saying "Nothing open". In a browser it
  has just the drop zone.
- Keyboard Shortcuts (F1): a search box finds shortcuts by name or by key, like "ctrl+e"
  or "F2", and every key of an action is listed.
- Command palette (Ctrl+Shift+P, or Ctrl+K): type part of any action's name to run it,
  play an animation or write one export. What you ran last comes first; actions that can't
  run now are greyed out with the reason, like "No frames selected", "Select a single
  frame" or "No animation chosen". Actions that don't apply right now, like the packed
  layout's in the grid layout or the pivot actions while pivots are off, are listed greyed
  out at the bottom, saying why.
- Crash recovery: while there are unsaved changes, a copy of the work is kept every few
  minutes (Settings > General > Recovery copy every, 0 turns it off) and right after big
  changes, like adding a spritesheet or repacking. If spritesheetbelli closes
  unexpectedly, the start screen offers to recover it next time, as unsaved changes to
  its file, or to discard it. Saving or quitting deletes the copy. Not in the web version.
- Italian. Settings > Interface > Language picks the interface's language: System (the
  operating system's), English or Italiano. It changes right away, menus, tooltips and
  panels included. On desktops, a `.po` file put in the translations folder (the button
  next to the setting opens it) adds its language to the list. File dialogs, native ones
  included, name their file types in the chosen language too.

### Changed
- Dialogs that only ask something (unsaved changes, deleted or changed files, errors and
  confirmations) and About have their text and buttons in the middle. Their main button,
  and those of New / Rename Animation, Add Outline, Export and Settings' Reset All, have
  the icon of the action. Save, Don't Save, Cancel are in that order on Windows. Errors
  show a warning sign, About links to the repository with an external-link button, About
  and Keyboard Shortcuts close with Close, the background panel applies with Apply, and
  the grid-shrink confirmation resizes with Resize.
- Add Spritesheet, Add Sprite(s) and Add Folder are in this order everywhere: the sidebar,
  the start screen and the File menu. Add Folder is a button with a folder and a plus,
  right of Add Sprite(s), and has a shortcut, Ctrl+Alt+I. The empty preview only says
  what can be dropped on it.
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
- A toolbar above the preview: select all/none, flip and
  rotate, Align in Cell and Trim, toggles for grid lines (G) and frame numbers (N). Zoom
  floats over the top-right corner of the preview, like in
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
  the sheet with a data file, a packed atlas, an animated GIF or a custom template) and
  shows only the settings that matter. A Tokens… button next to the file names lists every
  token with what it gives for a frame of the sheet, and inserts one at the caret; unknown
  tokens get a warning. The example shows real names from the sheet, and exports that
  write more than one file list them (the first few and how many more). The background
  says "Transparent" when it is, frames are named `{animation}_{animation_frame}` by
  default when the sheet has animations, and the dialog opens on the export last
  selected. An export without a file asks where to save the first time; after that it
  writes there without asking.
- Changing the export settings is no longer a step in the History, so Ctrl+Z after
  exporting undoes the last edit. They still count as unsaved changes. Spacing, padding
  and extruded edges set in the sidebar are still undone like the rest of the layout.
- Toolbar and sidebar buttons show the name and current shortcut of their action, like
  "Export (Ctrl+E)", with what it does on the next line where that helps. Align in Cell,
  Pivot, Trim and Pinned say they work on every frame when none are selected.
- Keyboard Shortcuts (F1) also lists panning with Space+drag, Ctrl+click, Shift+click,
  boxes with Shift and Ctrl, moving frames and pivots, locking cells, the right-click menu
  and copying frames in the timeline with Alt+drag. The README no longer
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
- Selecting and moving frames need no tool: dragging a frame moves it, with the rest of
  the selection when it's selected, and dragging from anywhere else draws a selection
  box, which adds to the selection with Shift and toggles it with Ctrl, also from a
  frame. Frames are shown see-through where they'd land, in the grid and the packed
  layout, and Esc puts them back. Arrow keys move the selected frames inside their cells
  or on their page (8 px with Shift), and Ctrl+arrows add the next frame to the
  selection. Clicking an empty cell locks or unlocks it and keeps the selection; clicking
  outside the frames selects nothing. Alt+drag no longer copies frames: Duplicate
  (Ctrl+D) does.
- The cursor shows what pressing or dragging does: the move cursor over frames, a cross
  while drawing a box or over a pivot, a hand while panning, a pointing hand over the
  names of animations, and a forbidden sign where packed frames wouldn't fit. It only
  changes over the preview, never over other panels.
- Frames dragged out of the sheet can always be dropped somewhere: held over the
  Animation button, the panel opens; brought back over the sheet, they move there
  instead. In the Sprites panel, dragging a frame that isn't selected drags it alone.
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
- Remove Background Colour is a panel that drops down from an eyedropper button in the
  canvas toolbar (also Frame > Remove Background Colour…) instead of a dialog, with the
  same colour, eyedropper and tolerance as Add Spritesheet. While it's open, the frames
  are shown with the colour removed. Nothing changes until Confirm, which is one step to
  undo; While it's open, clicking the canvas selects frames as usual and the preview
  follows the selection; Cancel, Escape or clicking anywhere else leaves the frames as
  they were. The eyedropper picks the colour by clicking a frame, as the frame is, not as
  previewed. Dragging in the colour picker no longer makes the app lag on big sheets.
- Remove Background Colour works on every frame when none are selected, like Align and
  Trim, and is available whenever the sheet has frames.
- Every data file (TexturePacker JSON hash and array, Phaser 3 multi-atlas, libGDX /
  Spine `.atlas`, Sparrow / Starling XML, Godot SpriteFrames) is written from a template
  in `templates/`, filled by a small Mustache-like engine. The files are the same as
  before.
- Grid sheets can be exported with any data file that can describe them (TexturePacker
  JSON as a hash or an array, Phaser 3, libGDX / Spine, Sparrow / Starling, Godot
  SpriteFrames): the Godot SpriteFrames and Aseprite / TexturePacker JSON exports are one
  "Spritesheet and data file" export with a list of formats.
- Cancelling the Add Spritesheet window after File > Open leaves nothing open, instead of
  an empty sheet named after the image.
- Counts say "1 frame" and "2 frames", "1 empty cell is skipped", and so on, rather than
  "1 frames".

### Removed
- Named rows: Frame > Rows > Name Row… (F2), double-clicking left of a row, the names
  left of the grid and the row headers in the Sprites list. Animations are the only way
  to group frames; exports no longer make an animation of every row, or name rows
  "row0", "row1"….
- The `{row_name}` file name token.

### Fixed
- Opening a big image, GIF or project froze the window behind a "please wait" bar that
  never moved: the file is now loaded and looked into on worker threads, so the bar keeps
  going and the window keeps drawing. Keys are blocked too while it works.
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
- The lock on locked cells and the pin on pinned frames are crisp at any zoom instead of
  pixelated.
- With the interface scaled (150%, 200%…), the preview is sharp: frames, lines, numbers
  and icons were drawn at 100% and stretched, which blurred them. It's stretched by
  exactly the interface's scale, so pixels are all the same width.
- Frames with the same name in a grid sheet's data file are numbered (walk, walk_2) like
  in atlases, instead of being written twice.
- The grid guess of Add Spritesheet: faint specks between sprites, like those soft brushes
  leave, no longer stop it reading the gaps, which made it guess tiny cells (250×125 for
  a 6×3 sheet). Missing frames keep the spacing, sprites that touch are cut where they
  meet, an axis that can't be read gets square cells from the other, and a single sprite
  is one cell instead of 16 px tiles.

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
