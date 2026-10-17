# Data file templates

Every data file is written from a template: plain text with Mustache-like tags. The
bundled ones are in `templates/`; put your own in the templates folder (Export dialog >
Open templates folder) to list them with the others, or pick one file with Custom
template. A template there with the file name of a bundled one (like `json.template`)
replaces it, marked "(yours)"; take it out to get the bundled one back. On the command
line a template's id is its file name without `.template` (`--metadata <id>`,
`--atlas-data <id>`), and `--template <file>` uses any file.

    {{name}}                 a value; nothing when it isn't set
    {{page.w}}  {{list.0}}   a value inside another
    {{.}}                    the current item, in a section over plain values
    {{name | json-escape}}   a value through filters, left to right
    {{#frames}}…{{/frames}}  once for every item of a list, or once when a value is set
    {{^frames}}…{{/frames}}  once when a value isn't set or a list is empty
    {{! comment }}           left out

Not set: nothing, false, empty text, an empty list. Numbers are always set, 0 too. Names
are looked up in the current item, then in the sections around it, then in the export.
Inside a list, `@index` is the item's position from 0, and `@first` and `@last` say
whether it's the first or the last: `{{#frames}}"{{name}}"{{^@last}}, {{/@last}}{{/frames}}`.
A line holding only sections and comments is left out, and so is the line break at the
very end. Filters: `json`, `json-escape`, `xml-escape`, `css-ident`, `tpsheet-escape`,
`lower`, `upper`, `pad N`, `plus N`, `minus N`, `times N`, `divide N`, `negate`,
`round N`; N is a number or a value's name (`{{x | plus w}}`).

A template starts with a header comment of `key: value` lines, up to an empty line:

    {{! my engine
    name: My engine
    extension: txt
    per_page: false
    rotation: none
    layouts: grid, packed
    }}
    {{#frames}}{{name}} {{x}} {{y}} {{w}} {{h}}
    {{/frames}}

`per_page`: a file for each page of an atlas. `rotation`: which way turned frames are
stored (clockwise, counter-clockwise, or none when the format can't say, and then frames
aren't turned). `layouts`: grid sheets, packed atlases or both. Without a header, the
extension comes from the file name (`list.csv.template`), else txt.

Values:
- the export: app, version, fps, frames, frame_count, animations, animation_count, pages,
  page_count, page, image, image_w, image_h, all_frames, related, and for a grid sheet
  columns, rows, cell_w, cell_h, padding, spacing, extrude;
- each frame: index, name, file_name, column, row, cell, page, x, y, w, h, packed_w,
  packed_h, rotated, trimmed, source_w, source_h, trim_left/top/right/bottom, has_pivot,
  pivot_x, pivot_y, pivot_px_x, pivot_px_y, duration;
- each animation: name, color (like Aseprite's `#rrggbbff`), fps, mode, loop, ping_pong,
  once, frames, frame_count, played_frames, from, to, direction, reversed, from_cell,
  to_cell; its frames also have relative_duration;
- each page: index, image, w, h, frames, frame_count, retina_image (its image at twice the
  size, in the 1x file of an export at scales 1 and 2).

At scales other than 1, every size and position (and a grid's cell_w, cell_h, padding,
spacing and extrude) is scaled.

The comments in `scripts/export/template_data.gd` describe each one.
