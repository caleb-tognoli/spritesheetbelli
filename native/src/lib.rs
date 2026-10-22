//! Native parts of spritesheetbelli: the in-betweens' hottest loops, see [`inbetween`].

use godot::prelude::*;

mod inbetween;

struct SbelliNative;

#[gdextension]
unsafe impl ExtensionLibrary for SbelliNative {}
