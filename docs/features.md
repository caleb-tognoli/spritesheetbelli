# Everything spritesheetbelli does

The full tour. For the short version, see the [README](../README.md).

- **Build sheets from sprites.** Add image files (PNG, JPG, WebP, animated GIF), whole
  folders or dropped files. They're
  sorted by name and placed in the first free cell, after the last frame or on a new row.
- **Cut sheets into frames.** The grid is set by columns × rows or by cell size in pixels,
  each following the other, and guessed from the file name (`hero_32x32.png`,
  `walk_8x2.png`) or from the gaps between sprites, or where they touch; offset and
  spacing handle sheets that aren't packed edge to edge, and pixels left over are pointed
  out. The window starts in
  Grid or Find sprites to match the sheet's layout, unless a data file comes with the
  image. The empty cells of an added sheet are locked so added sprites skip them, unless
  "Lock empty cells" is unticked. Sheets drawn on a solid colour, like magenta, have it
  made transparent before they're cut, so the grid is guessed from the gaps and frames
  come in clean; the eyedropper button in the toolbar picks another colour (from the
  colour picker, or by clicking the preview), sets how close a colour must be, or turns it
  off.
- **Unpack packed sheets.** A TexturePacker, Aseprite or Phaser JSON or a libGDX / Spine
  `.atlas` next to the image says where every frame is, on every page; trimmed and rotated
  frames are restored and tags become animations. Without one, the sprites are found by
  the transparent space around them, in boxes on the image you can move, resize, merge,
  delete or draw before adding them.
- **Packed layout.** Instead of a grid, frames can be laid out packed tightly on pages,
  like a texture atlas, and edited right there: drag frames anywhere (or onto a new page),
  pin them, pack again. An opened atlas keeps every frame where it is, so exporting it
  again after adding or editing frames keeps the places engines know. Page size, packing,
  spacing, padding, extrusion, turning frames to fit and trimming are in the sidebar;
  sharing identical frames and power-of-two or square pages are in Settings.
- **Pivots** (turn them on in Settings): the point engines anchor each frame at, shown on
  the selected frames and the one under the mouse and dragged there (all the selected
  frames' at once), or set with presets, and exported where the format has them.
- **Edit frames.** Click or box-select frames and drag them where they go: there are no
  tools to switch between. Flip, rotate, trim, remove a background colour (from the
  eyedropper button in the toolbar, picked by clicking a frame and previewed on the
  selected frames, or every frame, until you Apply; only where it reaches the frame's
  edges unless Contiguous only is off), add an outline, replace,
  cut/copy/paste (also images copied in other apps), duplicate, insert or remove cells,
  insert, remove or reorder rows. Everything can be undone.
- **Stay linked to your art files.** Sprites and sheets remember the file they came from.
  When you save it again in your drawing program, spritesheetbelli asks whether to reload
  it, keeping the flips, trims, outlines and moves made here or going back to the file as
  it is; with several changed files, answer once for all of them. Sheets are cut again in
  the same places (data-file frames by name), GIF frames by number. Link a folder with Add
  Folder or by dropping it on the window: new images you save there are added
  automatically, deleted ones can be removed, and renamed ones stay linked.
- **Line frames up.** Move frames inside their cells a pixel at a time with the arrow
  keys, or align them to an edge of their cells; trimming keeps every pixel where it was, so
  animations don't jump. Turn on the rulers (Y) and click them to add guides repeated in
  every cell, like a baseline, then Alt+arrow keys put each frame on the next one.
- **Resize without losing quality.** Sprites are always resized from the originals, with
  Nearest for sharp pixel art, and pixel-perfect zoom keeps every pixel the same size on
  screen. Or resize the canvas instead: add transparent space around the frames, or crop
  it away without touching what's drawn.
- **Animations:** make named animations from a row, a column or the selected frames in a
  keystroke (F2, Shift+F2, Ctrl+F2), named after what their frames' names share, or from
  a range of cells, each with its own speed and loop, ping-pong or play-once. Put their
  frames together on a timeline by dragging them from the sheet or the Sprites panel
  (dropped anywhere else in the panel, they make a new animation), reordering or copying
  them and setting how long each is shown, or type them by number or name (`0-3, 4*2`);
  mirror walk_right into walk_left; generate the frames between two key frames, each
  piece of the sprite turned about its joint, squashed or stretched part of the way, cloth
  and bending limbs bent, without new colours, and add them to the animations that play
  the keys in a row; play them in the animation panel under the sheet, with onion skin,
  zoom, a scrub bar and a choice of background, and export them; only animations are
  exported as animations.
  Animations are named on the grid, next to or around their frames; the tag button in
  the toolbar chooses which. Click a name to play it, double-click to rename it,
  right-click for more.
- **Export** the sheet as PNG, JPG or WebP; every frame as its own PNG with file names
  like `{animation}_{animation_frame:2}` (walk_00, walk_01…); a tightly packed atlas, or
  its pages as images; an animation as an animated GIF, or a GIF of each animation; or
  GameMaker strips (`walk_strip8.png`, each animation's frames side by side). Images, data
  files, atlases and strips can be written at several scales at once (`hero.png`,
  `hero@2x.png`, pages `hero_0@2x.png`, strips `walk@2x_strip8.png`), each resized from
  the original frames with its own data file. A project keeps a list of exports, each with
  its settings and where it writes (relative to the project), so Export Again or the
  command line writes them all at once. The Export button sits at the top of the sidebar
  with the size of what it writes and how many exports there are, and the Export dialog
  shows only the settings that matter for each, with a Tokens… list for file names and the
  files it will write. Padding, spacing and edge extrusion are set in the sidebar, where
  the preview shows them, for the grid and the atlas.
- **Metadata for game engines:** TexturePacker-style JSON (hash or array, with
  Aseprite-style tags), a Phaser 3 multi-atlas, a libGDX / Spine `.atlas`, Sparrow /
  Starling XML, a Godot `SpriteFrames` resource with the sheet's animations (or every
  frame in one "default" animation when there are none), a Unity `.tpsheet`, a Cocos2d-x
  `.plist`, CSS or SCSS sprites (with the @2x image for high-density screens when exported
  at scales 1 and 2), and for grid sheets a Defold tile source, for a grid sheet or every
  page of a packed atlas, with pivots and turned frames where the format has them. Every
  data file comes from a template, and your own templates can add formats (see [Data file
  templates](templates.md)). For Unity, install the free [TexturePacker Importer](
  https://assetstore.unity.com/packages/tools/sprite-management/texturepacker-importer-166
  41) package and export with the Unity data file into your project's Assets folder, next
  to the PNG: Unity cuts it into one sprite per frame, named after the frames, with their
  pivots, and cuts it again whenever you export over it.
- **Tabs.** Every project opens in a tab of its own over the canvas, with its own undo
  history, selection and view: switch with a click or Ctrl+Tab, drag tabs to reorder
  them, and copy frames from one project to paste them in another. With Reopen last
  projects on in Settings, they all open again at the next start.
- **Start screen.** A new tab shows your recent projects and sheets with thumbnails, to
  open with a click, and buttons to open a file or add sprites.
- **Crash recovery.** Unsaved work in every tab is copied every few minutes and offered
  on the start screen after a crash.
- **Projects** (`.sbelli`) reopen exactly as they were, with frames at their original
  size and the view you left them at.
- English and Italian. Light and dark themes, or the system's as it changes, an accent
  colour of your choice or the system's, interface scaling and keyboard shortcuts.

## Keyboard shortcuts

Press **F1** in the app for every shortcut and what the mouse does in the preview; type in
its search box to find one by name or by key (like "ctrl+e"). Menus show each action's
shortcut, and toolbar buttons show it when hovered. **Ctrl+Shift+P** (or Ctrl+K, which
also works in browsers) opens the command palette: type part of an action's name, an
animation or an export, then press Enter.
