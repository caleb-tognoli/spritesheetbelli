"""A window at (800, 100) whose button drags the file given as a URI list, for
x11_drag_test.sh."""

import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

uri = "file://" + sys.argv[1]
window = Gtk.Window()
window.move(800, 100)
window.resize(200, 200)
button = Gtk.Button(label="drag")
window.add(button)
button.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [], Gdk.DragAction.COPY)
button.drag_source_add_uri_targets()
button.connect("drag-data-get", lambda _w, _c, data, _i, _t: data.set_uris([uri]))
window.connect("destroy", Gtk.main_quit)
window.show_all()
Gtk.main()
