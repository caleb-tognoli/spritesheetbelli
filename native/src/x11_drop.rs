//! Linux on X11: drags arrive as XDND client messages on Godot's own X connection, which
//! an extension can't read. XDND lets a window name a proxy that gets them instead
//! (XdndProxy), so [`Hook`] makes one on a connection of its own, notes when files
//! enter and leave, and passes every message on to Godot's window unchanged, which
//! answers the source and opens the files as before. On Wayland nothing can be watched.

use godot::classes::{DisplayServer, Window, display_server::HandleType};
use godot::prelude::*;
use x11rb::connection::Connection;
use x11rb::protocol::Event;
use x11rb::protocol::xproto::{
    self, AtomEnum, ClientMessageEvent, ConnectionExt as _, CreateWindowAux, EventMask, PropMode,
    WindowClass,
};
use x11rb::rust_connection::RustConnection;
use x11rb::wrapper::ConnectionExt as _;

use crate::emit;

/// The XDND version the proxy says it speaks, like Godot
const XDND_VERSION: u32 = 5;

struct Atoms {
    aware: u32,
    proxy: u32,
    enter: u32,
    position: u32,
    leave: u32,
    drop: u32,
    type_list: u32,
    uri_list: u32,
}

/// The proxy of a window, while it exists
pub struct Hook {
    connection: RustConnection,
    atoms: Atoms,
    monitor: InstanceId,
    /// Godot's window
    target: xproto::Window,
    proxy: xproto::Window,
    /// Whether the drag that entered has files, so Godot accepts it
    accepted: bool,
}

impl Hook {
    /// X11 is only read when polled, every frame
    pub const POLLS: bool = true;

    /// Makes a proxy for `window`. None on Wayland, or when it has no X window, like
    /// when running headless.
    pub fn new(monitor: InstanceId, window: Gd<Window>) -> Option<Hook> {
        let server = DisplayServer::singleton();
        if server.get_name() != "X11" {
            return None;
        }
        let target = server
            .window_get_native_handle_ex(HandleType::WINDOW_HANDLE)
            .window_id(window.get_window_id())
            .done() as xproto::Window;
        if target == 0 {
            return None;
        }
        match Hook::connect(monitor, target) {
            Ok(hook) => Some(hook),
            Err(error) => {
                godot_error!("Could not watch file drags: {error}");
                None
            }
        }
    }

    fn connect(
        monitor: InstanceId,
        target: xproto::Window,
    ) -> Result<Hook, Box<dyn std::error::Error>> {
        let (connection, screen) = x11rb::connect(None)?;
        let intern = |name: &[u8]| -> Result<u32, Box<dyn std::error::Error>> {
            Ok(connection.intern_atom(false, name)?.reply()?.atom)
        };
        let atoms = Atoms {
            aware: intern(b"XdndAware")?,
            proxy: intern(b"XdndProxy")?,
            enter: intern(b"XdndEnter")?,
            position: intern(b"XdndPosition")?,
            leave: intern(b"XdndLeave")?,
            drop: intern(b"XdndDrop")?,
            type_list: intern(b"XdndTypeList")?,
            uri_list: intern(b"text/uri-list")?,
        };
        let root = connection.setup().roots[screen].root;
        let proxy = connection.generate_id()?;
        connection.create_window(
            0,
            proxy,
            root,
            -1,
            -1,
            1,
            1,
            0,
            WindowClass::INPUT_ONLY,
            0,
            &CreateWindowAux::new(),
        )?;
        // The proxy names itself, as XDND asks, so sources know it's not stale
        connection.change_property32(
            PropMode::REPLACE,
            proxy,
            atoms.proxy,
            AtomEnum::WINDOW,
            &[proxy],
        )?;
        connection.change_property32(
            PropMode::REPLACE,
            proxy,
            atoms.aware,
            AtomEnum::ATOM,
            &[XDND_VERSION],
        )?;
        connection.change_property32(
            PropMode::REPLACE,
            target,
            atoms.proxy,
            AtomEnum::WINDOW,
            &[proxy],
        )?;
        connection.flush()?;
        Ok(Hook {
            connection,
            atoms,
            monitor,
            target,
            proxy,
            accepted: false,
        })
    }

    /// Passes on the messages the proxy got, telling the monitor when files enter and leave
    pub fn poll(&mut self) {
        while let Ok(Some(event)) = self.connection.poll_for_event() {
            // Only the proxy is ours, so messages are for it, whichever window they name: XDND
            // says the target's, GTK puts the proxy's
            let Event::ClientMessage(message) = event else {
                continue;
            };
            let kind = message.type_;
            if ![
                self.atoms.enter,
                self.atoms.position,
                self.atoms.leave,
                self.atoms.drop,
            ]
            .contains(&kind)
            {
                continue;
            }
            self.forward(message);
            if kind == self.atoms.enter {
                self.accepted = self.offers_files(&message);
                if self.accepted {
                    emit(self.monitor, "drag_entered");
                }
            } else if (kind == self.atoms.leave || kind == self.atoms.drop) && self.accepted {
                self.accepted = false;
                emit(self.monitor, "drag_exited");
            }
        }
    }

    fn forward(&self, message: ClientMessageEvent) {
        let forwarded = ClientMessageEvent {
            window: self.target,
            ..message
        };
        let sent = self
            .connection
            .send_event(false, self.target, EventMask::NO_EVENT, forwarded);
        if sent.is_err() || self.connection.flush().is_err() {
            godot_error!("Could not pass a file drag on to the window");
        }
    }

    /// Whether the drag that entered offers a list of files, the only thing Godot takes
    fn offers_files(&self, enter: &ClientMessageEvent) -> bool {
        let data = enter.data.as_data32();
        // More than three types are listed on the source window instead
        if data[1] & 1 == 0 {
            return data[2..5].contains(&self.atoms.uri_list);
        }
        let types = self
            .connection
            .get_property(
                false,
                data[0],
                self.atoms.type_list,
                AtomEnum::ATOM,
                0,
                1024,
            )
            .ok()
            .and_then(|cookie| cookie.reply().ok());
        types.is_some_and(|reply| {
            reply
                .value32()
                .is_some_and(|mut atoms| atoms.any(|atom| atom == self.atoms.uri_list))
        })
    }
}

impl Drop for Hook {
    fn drop(&mut self) {
        let _ = self
            .connection
            .delete_property(self.target, self.atoms.proxy);
        let _ = self.connection.destroy_window(self.proxy);
        let _ = self.connection.flush();
    }
}
