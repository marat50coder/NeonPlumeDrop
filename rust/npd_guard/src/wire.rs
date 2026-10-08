// ─────────────────────────────────────────────────────────────
// wire — ephemeral per-call Rust→Dart buffer envelope
// ─────────────────────────────────────────────────────────────
// Dart and Rust share the process so a real cipher between them
// is pointless. The goal here is weaker but still useful: do
// NOT let the unsealed plaintext sit in a predictable buffer
// that `cat /proc/<pid>/maps` + `dd` + `strings` would catch.
//
// Buffer shape:
//
//   [ nonce(4) | key_header(4) | body (unseal_len bytes) ]
//
//   nonce       — 4 random bytes seeded from the system clock
//                 + a process-local Weyl counter.
//   key_header  — nonce XOR'd with the mask below. Lets Dart
//                 detect a tampered buffer without a real MAC.
//   body        — plaintext XOR'd with a 48-byte keystream
//                 derived from the nonce via a SplitMix32
//                 chain (same family as `cloak.rs`, different
//                 seed material).
//
// Dart undoes this inside `_decodeWire` in orbit_guard.dart.
// All constants rotate per project — see .cursor rules.
// ─────────────────────────────────────────────────────────────

use core::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const WIRE_HEADER: usize = 8;
pub const WIRE_STREAM_LEN: usize = 48;

const SPLITMIX_INC: u32 = 0x9E37_79B9;
const SPLITMIX_X1: u32 = 0x7F4A_7C15;
const SPLITMIX_X2: u32 = 0xC2B2_AE35;

/// Fixed cross-check constant woven into the key header. MUST
/// match `_wireKeyMask` in `lib/orbit_guard/orbit_guard.dart`.
pub const WIRE_KEY_MASK: u32 = 0x9E37_79B9;

static COUNTER: AtomicU64 = AtomicU64::new(0xA54F_F53A_5F1D_36F1);

fn next_nonce() -> [u8; 4] {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0);
    let tick = COUNTER.fetch_add(0xA54F_F53A_5F1D_36F1, Ordering::Relaxed);
    let mix = (now ^ tick ^ tick.rotate_left(23)) as u32;
    mix.to_le_bytes()
}

fn stream_from_nonce(nonce: [u8; 4]) -> [u8; WIRE_STREAM_LEN] {
    let mut state: u32 = 0;
    for b in nonce.iter() {
        state = state.wrapping_add(u32::from(*b));
        state = state.wrapping_mul(SPLITMIX_INC);
    }
    if state == 0 {
        state = SPLITMIX_INC;
    }
    let mut out = [0u8; WIRE_STREAM_LEN];
    for s in out.iter_mut() {
        state = state.wrapping_add(SPLITMIX_INC);
        let mut z = state;
        z = (z ^ (z >> 16)).wrapping_mul(SPLITMIX_X1);
        z = (z ^ (z >> 13)).wrapping_mul(SPLITMIX_X2);
        z ^= z >> 16;
        *s = ((z >> 8) & 0xFF) as u8;
    }
    out
}

/// Wraps the already-unsealed plaintext into the wire envelope.
pub fn wrap(plain: &[u8]) -> Vec<u8> {
    let nonce = next_nonce();
    let stream = stream_from_nonce(nonce);

    let mut buf = Vec::with_capacity(WIRE_HEADER + plain.len());
    buf.extend_from_slice(&nonce);
    let header = u32::from_le_bytes(nonce) ^ WIRE_KEY_MASK;
    buf.extend_from_slice(&header.to_le_bytes());
    for (i, byte) in plain.iter().enumerate() {
        buf.push(byte ^ stream[i % WIRE_STREAM_LEN]);
    }
    buf
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wrap_adds_header() {
        let plain = b"hello";
        let w = wrap(plain);
        assert_eq!(w.len(), WIRE_HEADER + plain.len());
        let nonce = u32::from_le_bytes(w[0..4].try_into().unwrap());
        let header = u32::from_le_bytes(w[4..8].try_into().unwrap());
        assert_eq!(nonce ^ WIRE_KEY_MASK, header);
    }

    #[test]
    fn two_wraps_use_different_nonces() {
        let a = wrap(b"same");
        let b = wrap(b"same");
        assert_ne!(&a[0..4], &b[0..4]);
    }
}
