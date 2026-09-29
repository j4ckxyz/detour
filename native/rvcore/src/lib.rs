//! Detour's GDExtension. Exposes the deterministic world generator (and, later, other native
//! hot paths such as the Opus codec) to GDScript.

use godot::prelude::*;

mod builder;
mod cache;
mod convert;
mod worldgen;

struct RvCore;

#[gdextension]
unsafe impl ExtensionLibrary for RvCore {}
