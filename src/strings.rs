//! UTF-16 conversion helpers for the `ImageGlass` ABI.
//!
//! All strings crossing the FFI boundary are UTF-16 [`IGStringRef`]s:
//! `length` counts code units (not bytes) and the slice is not
//! null-terminated.  These helpers convert between `&str` / [`String`]
//! and the ABI representation.

use crate::types::IGStringRef;

/// Encode a `&str` as UTF-16 code units.
pub(crate) fn encode_utf16(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

/// Converts a UTF-16 [`IGStringRef`] to a [`String`] using lossy conversion.
pub(crate) fn utf16_to_string(s: &IGStringRef) -> Option<String> {
    if s.data.is_null() || s.length <= 0 {
        return None;
    }
    // SAFETY: caller guarantees the pointer is valid for `length` code units.
    let slice = unsafe { std::slice::from_raw_parts(s.data, s.length as usize) };
    Some(String::from_utf16_lossy(slice))
}
