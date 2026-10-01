#!/bin/sh
# Installs spritesheetbelli for the current user: the app, its launcher, the
# `spritesheetbelli` command, .sbelli projects opening with it and the files it imports
# offering it in "Open with". `./install.sh --uninstall` removes it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
app=$data/spritesheetbelli/spritesheetbelli.x86_64
bin=$HOME/.local/bin/spritesheetbelli
desktop=$data/applications/spritesheetbelli.desktop
mime=$data/mime/packages/spritesheetbelli.xml
icon=$data/icons/hicolor/scalable/apps/spritesheetbelli.svg

if [ "$1" = "--uninstall" ]; then
	rm -rf "$data/spritesheetbelli"
	rm -f "$bin" "$desktop" "$mime" "$icon"
else
	install -Dm755 "$here/spritesheetbelli.x86_64" "$app"
	mkdir -p "$(dirname "$bin")"
	ln -sf "$app" "$bin"
	install -Dm644 "$here/spritesheetbelli.svg" "$icon"
	install -Dm644 "$here/spritesheetbelli.xml" "$mime"
	mkdir -p "$(dirname "$desktop")"
	sed "s|^Exec=spritesheetbelli|Exec=\"$app\"|" "$here/spritesheetbelli.desktop" > "$desktop"
fi

update-mime-database "$data/mime" >/dev/null 2>&1 || true
update-desktop-database "$data/applications" >/dev/null 2>&1 || true
gtk-update-icon-cache -q "$data/icons/hicolor" >/dev/null 2>&1 || true
if [ "$1" = "--uninstall" ]; then
	echo "spritesheetbelli was removed."
else
	xdg-mime default spritesheetbelli.desktop application/x-spritesheetbelli >/dev/null 2>&1 || true
	echo "spritesheetbelli was installed. Run ./install.sh --uninstall to remove it."
fi
