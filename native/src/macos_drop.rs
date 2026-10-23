//! macOS: Godot's content view accepts file drags (`draggingEntered:`) and opens them
//! (`performDragOperation:`), but has no `draggingExited:`. [`Hook`] wraps the first two
//! and adds the third through the Objective-C runtime, for every Godot view, and tells
//! the monitors of the views it's attached to. Godot's own methods still run.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, c_void};
use std::sync::OnceLock;

use godot::classes::{DisplayServer, Window, display_server::HandleType};
use godot::prelude::*;
use objc2::ffi::class_addMethod;
use objc2::runtime::{AnyClass, AnyObject, Bool, Imp, Sel};
use objc2::sel;

use crate::emit;

type EnteredImp = unsafe extern "C-unwind" fn(*mut AnyObject, Sel, *mut AnyObject) -> usize;
type PerformImp = unsafe extern "C-unwind" fn(*mut AnyObject, Sel, *mut AnyObject) -> Bool;
type ExitedImp = unsafe extern "C-unwind" fn(*mut AnyObject, Sel, *mut AnyObject);

/// Godot's methods, called by ours
struct Originals {
    entered: Option<EnteredImp>,
    perform: Option<PerformImp>,
    exited: Option<ExitedImp>,
}

static ORIGINALS: OnceLock<Originals> = OnceLock::new();

thread_local! {
    /// The monitor of each view a hook is attached to, by its address. AppKit calls the
    /// dragging methods on the main thread, Godot's.
    static MONITORS: RefCell<HashMap<usize, InstanceId>> = RefCell::new(HashMap::new());
}

/// Keeps a view's drags told to a monitor while it exists
pub struct Hook {
    view: usize,
}

impl Hook {
    /// Drags are told as they happen, without polling
    pub const POLLS: bool = false;

    pub fn poll(&mut self) {}

    /// Watches the content view of `window`. None when it has none, like when running
    /// headless.
    pub fn new(monitor: InstanceId, window: Gd<Window>) -> Option<Hook> {
        let view = DisplayServer::singleton()
            .window_get_native_handle_ex(HandleType::WINDOW_VIEW)
            .window_id(window.get_window_id())
            .done() as usize;
        if view == 0 {
            return None;
        }
        let class = unsafe { (*(view as *const AnyObject)).class() };
        ORIGINALS.get_or_init(|| unsafe { install(class) });
        MONITORS.with_borrow_mut(|monitors| monitors.insert(view, monitor));
        Some(Hook { view })
    }
}

impl Drop for Hook {
    fn drop(&mut self) {
        MONITORS.with_borrow_mut(|monitors| monitors.remove(&self.view));
    }
}

/// Puts our methods in `class`, returning the ones they replace
unsafe fn install(class: &AnyClass) -> Originals {
    unsafe {
        let entered = replace(
            class,
            sel!(draggingEntered:),
            std::mem::transmute::<EnteredImp, Imp>(entered),
            c"Q@:@",
        );
        // BOOL is a bool on Apple Silicon and a signed char on Intel
        let bool_types = if cfg!(target_arch = "aarch64") {
            c"B@:@"
        } else {
            c"c@:@"
        };
        let perform = replace(
            class,
            sel!(performDragOperation:),
            std::mem::transmute::<PerformImp, Imp>(perform),
            bool_types,
        );
        let exited = replace(
            class,
            sel!(draggingExited:),
            std::mem::transmute::<ExitedImp, Imp>(exited),
            c"v@:@",
        );
        Originals {
            entered: entered.map(|imp| std::mem::transmute::<Imp, EnteredImp>(imp)),
            perform: perform.map(|imp| std::mem::transmute::<Imp, PerformImp>(imp)),
            exited: exited.map(|imp| std::mem::transmute::<Imp, ExitedImp>(imp)),
        }
    }
}

/// Makes `imp` the implementation of `sel` in `class`, returning the one it had, its own
/// or inherited. `types` are its type encoding, for when the class didn't have its own.
unsafe fn replace(class: &AnyClass, sel: Sel, imp: Imp, types: &CStr) -> Option<Imp> {
    let inherited = class
        .instance_method(sel)
        .map(|method| method.implementation());
    let class_ptr = class as *const AnyClass as *mut AnyClass;
    if unsafe { class_addMethod(class_ptr, sel, imp, types.as_ptr()) }.as_bool() {
        return inherited;
    }
    // It has its own
    let method = class.instance_method(sel)?;
    Some(unsafe { method.set_implementation(imp) })
}

fn monitor_of(view: *mut AnyObject) -> Option<InstanceId> {
    MONITORS.with_borrow(|monitors| monitors.get(&(view as *const c_void as usize)).copied())
}

unsafe extern "C-unwind" fn entered(view: *mut AnyObject, sel: Sel, info: *mut AnyObject) -> usize {
    let original = ORIGINALS.get().and_then(|originals| originals.entered);
    // NSDragOperationNone when Godot didn't have it
    let operation = original.map_or(0, |original| unsafe { original(view, sel, info) });
    // Godot only registers for file URLs, so these are files
    if operation != 0
        && let Some(monitor) = monitor_of(view)
    {
        emit(monitor, "drag_entered");
    }
    operation
}

unsafe extern "C-unwind" fn exited(view: *mut AnyObject, sel: Sel, info: *mut AnyObject) {
    if let Some(original) = ORIGINALS.get().and_then(|originals| originals.exited) {
        unsafe { original(view, sel, info) };
    }
    if let Some(monitor) = monitor_of(view) {
        emit(monitor, "drag_exited");
    }
}

/// Drops don't exit, so it's said before Godot opens the files
unsafe extern "C-unwind" fn perform(view: *mut AnyObject, sel: Sel, info: *mut AnyObject) -> Bool {
    if let Some(monitor) = monitor_of(view) {
        emit(monitor, "drag_exited");
    }
    match ORIGINALS.get().and_then(|originals| originals.perform) {
        Some(original) => unsafe { original(view, sel, info) },
        None => Bool::NO,
    }
}
