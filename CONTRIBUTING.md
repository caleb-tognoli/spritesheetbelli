# Contributing

How to build spritesheetbelli, run its tests, translate it and publish a release.

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
| `scripts/resources/packed_layout.gd` | Where frames are in the packed layout |
| `scripts/frame_edits.gd`, `scripts/frame_source.gd` | Pixel edits that can be made again, and the files frames are linked to |
| `scripts/document.gd` | The open document: file, unsaved state, undo history |
| `scripts/export/` | Exporting images, sprites, atlases and metadata; the packer |
| `scripts/import/` | Reading where frames are in packed sheets |
| `scripts/autoloaded/` | Global state, actions and shortcuts, settings, dialogs |
| `ui/main/` | The main window, menus and file handling |
| `ui/spritesheet_preview/` | The preview that draws and edits the grid |
| `tests/` | The test runner and tests |

## Translations

spritesheetbelli is in English and Italian; pick one in Settings > Interface > Language
(System follows the operating system). To add a language:

1. Copy `translations/spritesheetbelli.pot` to a file named after the language's code,
   like `de.po`, and translate it with a gettext editor such as Poedit, with the
   language's plural forms.
2. To try it, put it in the translations folder (the folder button next to the Language
   setting) and reopen Settings: the language is in the list. This works in the released
   app too, on desktops.
3. To ship it, put it in `translations/` and add it in Project Settings > Localization >
   Translations.

The text to translate is collected with
`godot --headless --path . -s res://_dev/generate_pot.gd`, which writes
`translations/spritesheetbelli.pot` from the scripts and scenes listed in Project Settings
> Localization > POT Generation. Run it after changing text (the tests say when it's out
of date), then update each `.po` from it, e.g.
`msgmerge --update translations/it.po translations/spritesheetbelli.pot` or Poedit's
Update from POT. In code, text goes through `tr()` (`tr_n()` for counts, with whole
sentences as formats like `tr("Saved %s") % name`); text kept to translate where it's
shown, like action names, is marked with `L10n.mark()`, or with a `# L10n.mark` comment on
a constant.

## Publishing a release

1. Set the version in `project.godot` (`application/config/version`) and in
   `export_presets.cfg` (the Windows `file_version` and `product_version`, with a `.0`
   at the end, and the macOS `short_version` and `version`).
2. Rename `## Unreleased` in `CHANGELOG.md` to `## <version>`: that section becomes the
   release notes.
3. Push a tag such as `v1.0.0`.

The Release workflow stops if the tag doesn't match those versions or the changelog has
no section for it. Otherwise it builds every platform, attaches the builds to a GitHub
release and publishes the web version to GitHub Pages (set
*Settings > Pages > Source* to *GitHub Actions* once). To also publish on itch.io, add
the repository variable `ITCH_GAME` (like `your-name/spritesheetbelli`) and the secret
`BUTLER_API_KEY`.

## Updating the README images

The images in `docs/` are taken from the real app by `_dev/readme/`:

```sh
python _dev/readme/make_slime.py <input>          # the slime, drawn into <input>
godot --path . res://_dev/readme/screenshots.tscn -- <input>
python _dev/readme/compose.py <input>              # the in-betweens GIF and composites
```

`<input>` is any empty folder. The screenshots script keeps its settings in a temporary
folder, so yours aren't touched.
