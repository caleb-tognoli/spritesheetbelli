//! Platforms where drags can't be watched: nothing to attach to.

use godot::classes::Window;
use godot::prelude::*;

pub struct Hook;

impl Hook {
    /// Drags are told as they happen, without polling
    pub const POLLS: bool = false;

    pub fn poll(&mut self) {}

    pub fn new(_monitor: InstanceId, _window: Gd<Window>) -> Option<Hook> {
        None
    }
}
