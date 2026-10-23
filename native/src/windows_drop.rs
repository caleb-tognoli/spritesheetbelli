//! Windows: Godot registers an OLE drop target on each window, which only reports drops.
//! [`Hook`] puts this one in its place. It accepts the same drags as Godot's (files, and
//! virtual files like images dragged from a browser, saved to a temporary folder) and also
//! says when they enter and leave. Ported from Godot's `drop_target_windows.cpp` (MIT).

use std::cell::{Cell, RefCell};
use std::ffi::c_void;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use godot::classes::{DisplayServer, Window, display_server::HandleType};
use godot::prelude::*;
use windows::Win32::Foundation::{E_FAIL, HGLOBAL, HWND, POINTL};
use windows::Win32::System::Com::{
    DVASPECT_CONTENT, FORMATETC, IDataObject, IStream, STGMEDIUM, TYMED_HGLOBAL, TYMED_ISTREAM,
};
use windows::Win32::System::DataExchange::RegisterClipboardFormatW;
use windows::Win32::System::Memory::{GlobalLock, GlobalSize, GlobalUnlock};
use windows::Win32::System::Ole::{
    CF_HDROP, DROPEFFECT, DROPEFFECT_COPY, DROPEFFECT_NONE, IDropTarget, IDropTarget_Impl,
    RegisterDragDrop, ReleaseStgMedium, RevokeDragDrop,
};
use windows::Win32::System::SystemServices::MODIFIERKEYS_FLAGS;
use windows::Win32::UI::Shell::{
    CFSTR_FILECONTENTS, CFSTR_FILEDESCRIPTORW, DragQueryFileW, FD_FILESIZE, FILEDESCRIPTORW,
    FILEGROUPDESCRIPTORW, HDROP,
};
use windows::core::{Error, Result, implement};

use crate::emit;

const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;

/// Our drop target, registered on a window while the hook exists
pub struct Hook {
    hwnd: HWND,
    _target: IDropTarget,
}

impl Hook {
    /// Drags are told as they happen, without polling
    pub const POLLS: bool = false;

    pub fn poll(&mut self) {}

    /// Replaces the drop target of `window`. None when it has no native window, like when
    /// running headless.
    pub fn new(monitor: InstanceId, window: Gd<Window>) -> Option<Hook> {
        let handle = DisplayServer::singleton()
            .window_get_native_handle_ex(HandleType::WINDOW_HANDLE)
            .window_id(window.get_window_id())
            .done();
        if handle == 0 {
            return None;
        }
        let hwnd = HWND(handle as *mut c_void);
        let target: IDropTarget = DropTarget::new(monitor, window.instance_id()).into();
        unsafe {
            // Godot's isn't there when its window has no drop callback yet
            let _ = RevokeDragDrop(hwnd);
            if let Err(error) = RegisterDragDrop(hwnd, &target) {
                godot_error!("Could not watch file drags: {error}");
                return None;
            }
        }
        Some(Hook {
            hwnd,
            _target: target,
        })
    }
}

impl Drop for Hook {
    fn drop(&mut self) {
        unsafe {
            let _ = RevokeDragDrop(self.hwnd);
        }
    }
}

#[implement(IDropTarget)]
struct DropTarget {
    monitor: InstanceId,
    window: InstanceId,
    cf_filedescriptor: u16,
    cf_filecontents: u16,
    /// Whether the drag that entered has files, so it can be dropped
    accepted: Cell<bool>,
    /// Where virtual files of the last drop were saved. They're removed on the next drop,
    /// not right after it like Godot does: opening dropped files can take a few frames.
    temp_dir: RefCell<Option<PathBuf>>,
}

impl DropTarget {
    fn new(monitor: InstanceId, window: InstanceId) -> DropTarget {
        unsafe {
            DropTarget {
                monitor,
                window,
                cf_filedescriptor: RegisterClipboardFormatW(CFSTR_FILEDESCRIPTORW) as u16,
                cf_filecontents: RegisterClipboardFormatW(CFSTR_FILECONTENTS) as u16,
                accepted: Cell::new(false),
                temp_dir: RefCell::new(None),
            }
        }
    }

    fn has_format(data: &IDataObject, format: u16) -> bool {
        format != 0 && unsafe { data.QueryGetData(&hglobal_format(format)) }.is_ok()
    }

    fn has_files(&self, data: &IDataObject) -> bool {
        Self::has_format(data, CF_HDROP.0)
            || (self.cf_filecontents != 0 && Self::has_format(data, self.cf_filedescriptor))
    }

    /// The paths of the dropped files, or of copies of virtual ones
    fn files(&self, data: &IDataObject) -> Result<Vec<String>> {
        if Self::has_format(data, CF_HDROP.0) {
            return hdrop_files(data);
        }
        self.remove_temp_dir();
        let dir = std::env::temp_dir().join(format!("sbelli_drop_{}", std::process::id()));
        *self.temp_dir.borrow_mut() = Some(dir.clone());
        save_virtual_files(data, &dir, self.cf_filedescriptor, self.cf_filecontents)
    }

    fn remove_temp_dir(&self) {
        if let Some(dir) = self.temp_dir.borrow_mut().take() {
            let _ = fs::remove_dir_all(dir);
        }
    }
}

impl Drop for DropTarget {
    fn drop(&mut self) {
        self.remove_temp_dir();
    }
}

#[allow(non_snake_case)]
impl IDropTarget_Impl for DropTarget_Impl {
    fn DragEnter(
        &self,
        data: Option<&IDataObject>,
        _keys: MODIFIERKEYS_FLAGS,
        _point: &POINTL,
        effect: *mut DROPEFFECT,
    ) -> Result<()> {
        let accepted = data.is_some_and(|data| self.has_files(data));
        self.accepted.set(accepted);
        set_effect(effect, accepted);
        if accepted {
            emit(self.monitor, "drag_entered");
        }
        Ok(())
    }

    fn DragOver(
        &self,
        _keys: MODIFIERKEYS_FLAGS,
        _point: &POINTL,
        effect: *mut DROPEFFECT,
    ) -> Result<()> {
        set_effect(effect, self.accepted.get());
        Ok(())
    }

    fn DragLeave(&self) -> Result<()> {
        if self.accepted.replace(false) {
            emit(self.monitor, "drag_exited");
        }
        Ok(())
    }

    fn Drop(
        &self,
        data: Option<&IDataObject>,
        _keys: MODIFIERKEYS_FLAGS,
        _point: &POINTL,
        effect: *mut DROPEFFECT,
    ) -> Result<()> {
        set_effect(effect, false);
        if !self.accepted.replace(false) {
            return Ok(());
        }
        emit(self.monitor, "drag_exited");
        let Some(data) = data else {
            return Ok(());
        };
        let files = match self.files(data) {
            Ok(files) => files,
            Err(error) => {
                godot_error!("Could not read the dropped files: {error}");
                return Err(error);
            }
        };
        if files.is_empty() {
            return Ok(());
        }
        let Ok(mut window) = Gd::<Window>::try_from_instance_id(self.window) else {
            return Ok(());
        };
        let files: PackedStringArray = files.iter().map(GString::from).collect();
        window.emit_signal("files_dropped", &[files.to_variant()]);
        set_effect(effect, true);
        Ok(())
    }
}

fn set_effect(effect: *mut DROPEFFECT, copy: bool) {
    if !effect.is_null() {
        unsafe {
            *effect = if copy {
                DROPEFFECT_COPY
            } else {
                DROPEFFECT_NONE
            }
        };
    }
}

fn hglobal_format(format: u16) -> FORMATETC {
    FORMATETC {
        cfFormat: format,
        ptd: std::ptr::null_mut(),
        dwAspect: DVASPECT_CONTENT.0,
        lindex: -1,
        tymed: TYMED_HGLOBAL.0 as u32,
    }
}

/// Locks the memory of `medium` while `read` reads it, then releases it
fn with_hglobal<T>(
    mut medium: STGMEDIUM,
    read: impl FnOnce(*mut c_void) -> Result<T>,
) -> Result<T> {
    unsafe {
        let global: HGLOBAL = medium.u.hGlobal;
        let pointer = GlobalLock(global);
        let result = if pointer.is_null() {
            Err(Error::from_win32())
        } else {
            let result = read(pointer);
            let _ = GlobalUnlock(global);
            result
        };
        ReleaseStgMedium(&mut medium);
        result
    }
}

fn hdrop_files(data: &IDataObject) -> Result<Vec<String>> {
    let medium = unsafe { data.GetData(&hglobal_format(CF_HDROP.0))? };
    with_hglobal(medium, |pointer| unsafe {
        let drop = HDROP(pointer);
        let count = DragQueryFileW(drop, u32::MAX, None);
        let mut files = Vec::with_capacity(count as usize);
        for i in 0..count {
            let len = DragQueryFileW(drop, i, None) as usize;
            let mut buffer = vec![0u16; len + 1];
            if DragQueryFileW(drop, i, Some(&mut buffer)) == 0 {
                return Err(Error::from_win32());
            }
            files.push(String::from_utf16_lossy(&buffer[..len]).replace('\\', "/"));
        }
        Ok(files)
    })
}

/// Saves each virtual file of `data` in `dir`, returning the files and folders at its top,
/// like Godot
fn save_virtual_files(
    data: &IDataObject,
    dir: &Path,
    cf_filedescriptor: u16,
    cf_filecontents: u16,
) -> Result<Vec<String>> {
    let medium = unsafe { data.GetData(&hglobal_format(cf_filedescriptor))? };
    let saved = with_hglobal(medium, |pointer| unsafe {
        fs::create_dir_all(dir).map_err(io_error)?;
        let group = &*(pointer as *const FILEGROUPDESCRIPTORW);
        let descriptors = std::slice::from_raw_parts(group.fgd.as_ptr(), group.cItems as usize);
        for (index, descriptor) in descriptors.iter().enumerate() {
            save_virtual_file(data, dir, descriptor, index as i32, cf_filecontents)?;
        }
        Ok(())
    });
    if let Err(error) = saved {
        let _ = fs::remove_dir_all(dir);
        return Err(error);
    }
    let mut files = Vec::new();
    for entry in fs::read_dir(dir).map_err(io_error)?.flatten() {
        files.push(entry.path().to_string_lossy().replace('\\', "/"));
    }
    files.sort();
    Ok(files)
}

fn save_virtual_file(
    data: &IDataObject,
    dir: &Path,
    descriptor: &FILEDESCRIPTORW,
    index: i32,
    cf_filecontents: u16,
) -> Result<()> {
    // Copied out: the descriptor is packed, so its fields can't be borrowed
    let name = { descriptor.cFileName };
    let attributes = { descriptor.dwFileAttributes };
    let name_len = name.iter().position(|&c| c == 0).unwrap_or(name.len());
    let path = dir.join(String::from_utf16_lossy(&name[..name_len]));
    if attributes & FILE_ATTRIBUTE_DIRECTORY != 0 {
        return fs::create_dir_all(path).map_err(io_error);
    }
    // Godot only takes a stream, some apps only give memory
    let format = FORMATETC {
        cfFormat: cf_filecontents,
        ptd: std::ptr::null_mut(),
        dwAspect: DVASPECT_CONTENT.0,
        lindex: index,
        tymed: (TYMED_ISTREAM.0 | TYMED_HGLOBAL.0) as u32,
    };
    let medium = unsafe { data.GetData(&format)? };
    if medium.tymed == TYMED_HGLOBAL.0 as u32 {
        let size =
            { descriptor.nFileSizeLow } as usize | ({ descriptor.nFileSizeHigh } as usize) << 32;
        let has_size = { descriptor.dwFlags } & FD_FILESIZE.0 as u32 != 0;
        let global = unsafe { medium.u.hGlobal };
        return with_hglobal(medium, |pointer| unsafe {
            let len = if has_size { size } else { GlobalSize(global) };
            let bytes = std::slice::from_raw_parts(pointer as *const u8, len);
            write_new_file(&path)?.write_all(bytes).map_err(io_error)
        });
    }
    let mut medium = medium;
    unsafe {
        let result = match medium.u.pstm.as_ref() {
            Some(stream) => stream_to_file(stream, &path),
            None => Err(Error::from_win32()),
        };
        ReleaseStgMedium(&mut medium);
        result
    }
}

fn write_new_file(path: &Path) -> Result<fs::File> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(io_error)?;
    }
    fs::File::create_new(path).map_err(io_error)
}

fn stream_to_file(stream: &IStream, path: &Path) -> Result<()> {
    let mut file = write_new_file(path)?;
    let mut buffer = [0u8; 4096];
    loop {
        let mut read = 0u32;
        let result = unsafe {
            stream.Read(
                buffer.as_mut_ptr() as *mut c_void,
                buffer.len() as u32,
                Some(&mut read),
            )
        };
        // S_FALSE, a success, is the end of the stream
        result.ok()?;
        if read == 0 {
            return Ok(());
        }
        file.write_all(&buffer[..read as usize]).map_err(io_error)?;
    }
}

fn io_error(error: std::io::Error) -> Error {
    Error::new(E_FAIL, error.to_string())
}
