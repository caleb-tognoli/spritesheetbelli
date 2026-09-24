<p align="center"><img src="icon.svg" width="96" alt="spritesheetbelli logo"></p>

<h1 align="center">spritesheetbelli</h1>

<p align="center">Combine sprites into spritesheets and cut spritesheets into sprites.<br>
A small desktop tool made with Godot.</p>

![spritesheetbelli with a slime spritesheet, its idle and jump rows and the animation preview](docs/screenshot.png)

## Features

- **Build sheets from sprites.** Add image files, whole folders or dropped files. They're
  sorted by name and placed in the first free cell, after the last frame or on a new row.
- **Cut sheets into frames.** The grid size is guessed from the file name
  (`hero_32x32.png`, `walk_8x2.png`) or from the gaps between sprites; offset and spacing
  handle sheets that aren't packed edge to edge.
- **Edit frames.** Drag to move or copy (Alt), flip, rotate, trim, remove a background
  colour, replace, cut/copy/paste (also images copied in other apps), duplicate, insert or
  remove cells. Everything can be undone.
- **Resize without losing quality.** Sprites are always resized from the originals, with
  Nearest for sharp pixel art.
- **Animations:** make named animations from a range of cells or the selected frames,
  each with its own speed and loop, ping-pong or play-once; preview them and export them.
- **Name rows** as animations (idle, walk, jump); names are used in exports.
- **Export** the sheet as PNG, JPG or WebP; every frame as its own PNG with file names like
  `walk_{frame:2}`; or a tightly packed atlas. One Export dialog shows only the settings
  that matter for what you export; padding, spacing and edge extrusion are there when an
  engine needs them.
- **Metadata for game engines:** TexturePacker-style JSON (with Aseprite-style tags) or a
  Godot `SpriteFrames` resource with one animation per named row.
- **Projects** (`.sbelli`) reopen exactly as they were, with frames at their original size.
- Light and dark themes, an accent colour, interface scaling and a keyboard shortcut for
  every action.

<details>
<summary>Light theme</summary>

![The same spritesheet in the light theme](docs/screenshot-light.png)
</details>

## Download

Builds for Windows, macOS, Linux and the web are attached to each
[release](https://github.com/caleb-tognoli/spritesheetbelli/releases). The web version
runs in the browser: opening files uses the browser's file picker and saving downloads
the result.

### Publishing a release

Push a tag such as `v0.2.0`. The Release workflow builds every platform, attaches the
builds to a GitHub release and publishes the web version to GitHub Pages (set
*Settings > Pages > Source* to *GitHub Actions* once). To also publish on itch.io, add
the repository variable `ITCH_GAME` (like `your-name/spritesheetbelli`) and the secret
`BUTLER_API_KEY`.

## Keyboard shortcuts

Press **F1** in the app for the full list. The most useful:

| Action | Shortcut |
| --- | --- |
| Add sprites / spritesheet | Ctrl+I / Ctrl+Shift+I |
| Save project / Save As | Ctrl+S / Ctrl+Shift+S |
| Export | Ctrl+E |
| Undo / Redo | Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z |
| Cut / Copy / Paste / Duplicate | Ctrl+X / Ctrl+C / Ctrl+V / Ctrl+D |
| Select all / none | Ctrl+A / Esc |
| Delete frames / Remove cells | Delete / Shift+Delete |
| Flip / Rotate | H, V / R, Shift+R |
| Trim transparent borders | T |
| Name row | F2 |
| Zoom / Actual size / Fit | Ctrl+= and Ctrl+- / Ctrl+0 / F |
| Animation preview | P |

In the preview: click selects, Ctrl+click toggles, Shift+click selects a range, drag on
empty space draws a selection box, drag frames to move them, click an empty cell to lock it
so added sprites skip it. Pan with the middle mouse button or Space+drag, zoom with the
wheel. Arrow keys move the selection.

## Command line

The same packing and exporting can run in build scripts. Arguments go after `--`:

```sh
# Pack a folder of frames, 8 per row, with a Godot SpriteFrames file
spritesheetbelli --headless -- --pack ./frames --out hero.png --columns 8 --metadata godot

# Export a saved project, also writing every frame as its own PNG
spritesheetbelli --headless -- --export hero.sbelli --out hero.png --sprites ./hero_frames
```

Run with `--help` for every option. The exit code is 0 on success, 1 on errors and 2 on
bad usage.

## Building from source

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open `project.godot` in Godot, or run it directly: `godot --path .`
3. To make builds, install the export templates and use Project > Export; the presets
   in `export_presets.cfg` are ready for Windows, macOS, Linux and the web.

### Tests and style

```sh
godot --headless --path . res://tests/test_runner.tscn   # exit code = failures
pip install "gdtoolkit==4.*"
gdlint scripts ui tests
gdformat scripts ui tests
```

CI runs the same on every push. Godot's script editor keeps indentation on blank lines,
so run `gdformat` before committing (or enable *Trim trailing whitespace on save* in the
editor settings).

### How it's organised

| Path | What's there |
| --- | --- |
| `scripts/resources/spritesheet.gd` | The spritesheet data and every edit |
| `scripts/document.gd` | The open document: file, unsaved state, undo history |
| `scripts/export/` | Exporting images, sprites, atlases and metadata |
| `scripts/autoloaded/` | Global state, actions and shortcuts, settings, dialogs |
| `ui/main/` | The main window, menus and file handling |
| `ui/spritesheet_preview/` | The preview that draws and edits the grid |
| `tests/` | The test runner and tests |

