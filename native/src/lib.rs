//! Native parts of spritesheetbelli: what Godot doesn't offer, see [`FileDragMonitor`],
//! and the in-betweens' hottest loops, see [`inbetween`].

// godot-rust's #[class(init)] writes `base: base`
#![allow(clippy::redundant_field_names)]

use godot::classes::{Engine, SceneTree, Window};
use godot::prelude::*;

mod inbetween;

// Each platform's Hook watches a window's drags while it exists
#[cfg(windows)]
#[path = "windows_drop.rs"]
mod platform;
#[cfg(target_os = "macos")]
#[path = "macos_drop.rs"]
mod platform;
#[cfg(target_os = "linux")]
#[path = "x11_drop.rs"]
mod platform;
#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
#[path = "no_drop.rs"]
mod platform;

struct SbelliNative;

#[gdextension]
unsafe impl ExtensionLibrary for SbelliNative {}

/// Tells when files from the operating system are dragged over a window, which Godot
/// doesn't: its windows only say when they're dropped, with `files_dropped`. Drops keep
/// arriving there once the monitor is attached.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct FileDragMonitor {
    base: Base<RefCounted>,
    hook: Option<platform::Hook>,
}

#[godot_api]
impl FileDragMonitor {
    /// Files were dragged into the window
    #[signal]
    fn drag_entered();

    /// The files were dragged out of the window again, the drag was canceled, or they
    /// were dropped (just before the window's `files_dropped`)
    #[signal]
    fn drag_exited();

    /// Starts watching drags over [param window], until the monitor is freed. False when
    /// this platform or display server can't tell, and drops work as before.
    #[func]
    fn attach(&mut self, window: Gd<Window>) -> bool {
        self.hook = platform::Hook::new(self.to_gd().instance_id(), window);
        if self.hook.is_some() && platform::Hook::POLLS {
            let tree = Engine::singleton()
                .get_main_loop()
                .map(|main| main.cast::<SceneTree>());
            if let Some(mut tree) = tree {
                tree.connect("process_frame", &self.to_gd().callable("poll"));
            }
        }
        self.hook.is_some()
    }

    /// Reads what the platform said, each frame where it has to be asked (X11)
    #[func]
    fn poll(&mut self) {
        if let Some(hook) = &mut self.hook {
            hook.poll();
        }
    }
}

/// Sends `signal` from the monitor, if it still exists
#[cfg_attr(
    not(any(windows, target_os = "macos", target_os = "linux")),
    allow(dead_code)
)]
fn emit(monitor: InstanceId, signal: &str) {
    if let Ok(mut monitor) = Gd::<Object>::try_from_instance_id(monitor) {
        monitor.emit_signal(signal, &[]);
    }
}
