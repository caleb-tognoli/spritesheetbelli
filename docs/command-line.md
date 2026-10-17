# Command line

The same packing and exporting can run in build scripts. Arguments go after `--`:

```sh
# Pack a folder of frames, 8 per row, with a Godot SpriteFrames file
spritesheetbelli --headless -- --pack ./frames --out hero.png --columns 8 --metadata godot

# Export a saved project, also writing every frame as its own PNG
spritesheetbelli --headless -- --export hero.sbelli --out hero.png --sprites ./hero_frames

# Write every export the project has, as set up in the Export dialog
spritesheetbelli --headless -- --export hero.sbelli

# Write a 1x and a 2x sheet, each with its JSON file
spritesheetbelli --headless -- --export hero.sbelli --out hero.png --metadata json --scales 1,2

# A GIF of each animation, and GameMaker strips at 1x and 2x
spritesheetbelli --headless -- --export hero.sbelli --gifs ./gifs --strips ./gamemaker --scales 1,2

# Cut a packed sheet into frames by the space around the sprites
spritesheetbelli --headless -- --cut packed.png --detect --sprites ./frames

# Cut a sheet drawn on magenta into frames, keeping the magenta
spritesheetbelli --headless -- --cut hero_magenta.png --grid 8x2 --keep-background --sprites ./frames

# Pack a project tightly with a JSON file, and make a GIF of its walk animation
spritesheetbelli --headless -- --export hero.sbelli --out hero_atlas.png --atlas
spritesheetbelli --headless -- --export hero.sbelli --out walk.gif --animation walk --scale 4

# Keep an atlas's layout in a project, then write it for libGDX on pages of up to 1024 px
spritesheetbelli --headless -- --cut ui.atlas --layout packed --out ui.sbelli
spritesheetbelli --headless -- --export ui.sbelli --out ui.png --atlas-data atlas --max-size 1024

# Write the data file from a template of your own
spritesheetbelli --headless -- --export hero.sbelli --out hero.png --template my_engine.template
```

`--cut` makes a solid background colour, like magenta, transparent unless
`--keep-background` is given; `--tolerance` sets how close a colour must be, and
`--all-matching` removes it inside the sprites too, not only where it reaches the edges. Run with
`--help` for every option. The exit code is 0 on success, 1 on errors and 2 on bad usage.
