// ─────────────────────────────────────────────────────────────
// cloak — sealed-value codec (SplitMix32 keystream → XOR)
// ─────────────────────────────────────────────────────────────
// Not shared with Lumina's `prism_core::cloak`:
//   • SplitMix32 (not FNV-1a → LCG) as the state transition,
//   • 37-byte keystream (Lumina uses 29),
//   • 20-byte salt (Lumina 18),
//   • wire codec in `wire.rs` uses a different constant family.
//
// All constants are routed through `obfstr::obfconst!`/`obfbytes!`
// so a `strings libnpd_guard.a` never shows the salt or the mix
// constants as a readable literal.
// ─────────────────────────────────────────────────────────────

use obfstr::obfbytes;

/// Keystream length — rotate per project (do NOT reuse Lumina's 29).
pub const STREAM_LEN: usize = 37;

/// SplitMix32 round constants. Plain `const` — integer literals get
/// folded directly into instructions by LLVM, so there is no `.rodata`
/// footprint to grep for.
const SPLITMIX_INC: u32 = 0x9E37_79B9;
const SPLITMIX_X1: u32 = 0x7F4A_7C15;
const SPLITMIX_X2: u32 = 0xC2B2_AE35;

#[inline(always)]
fn salt() -> [u8; 20] {
    // obfstr scrambles the array in `.rodata` and descrambles on
    // first use — the literal here never ships contiguously.
    *obfbytes!(&[
        0xA1, 0x3F, 0x7C, 0x95,
        0x28, 0xB4, 0x5D, 0x02,
        0xE6, 0x81, 0x49, 0x7A,
        0xD5, 0x1C, 0x9F, 0x38,
        0x6B, 0xC2, 0x04, 0xEE,
    ])
}

#[inline(never)]
pub fn build_stream() -> [u8; STREAM_LEN] {
    let salt = salt();
    let mut state: u32 = 0;
    for b in salt.iter() {
        state = state.wrapping_add(u32::from(*b));
        state = state.wrapping_mul(SPLITMIX_INC);
    }
    if state == 0 {
        state = SPLITMIX_INC;
    }
    let mut stream = [0u8; STREAM_LEN];
    for s in stream.iter_mut() {
        state = state.wrapping_add(SPLITMIX_INC);
        let mut z = state;
        z = (z ^ (z >> 16)).wrapping_mul(SPLITMIX_X1);
        z = (z ^ (z >> 13)).wrapping_mul(SPLITMIX_X2);
        z ^= z >> 16;
        *s = ((z >> 8) & 0xFF) as u8;
    }
    stream
}

/// Reveal the UTF-8 plaintext behind a sealed byte slice. Returns
/// an empty `Vec` if the input is empty.
pub fn unseal(sealed: &[u8]) -> Vec<u8> {
    if sealed.is_empty() {
        return Vec::new();
    }
    let stream = build_stream();
    let mut out = Vec::with_capacity(sealed.len());
    for (i, b) in sealed.iter().enumerate() {
        out.push(b ^ stream[i % STREAM_LEN]);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stream_is_deterministic() {
        assert_eq!(build_stream(), build_stream());
    }

    #[test]
    fn stream_fills() {
        assert!(build_stream().iter().any(|b| *b != 0));
    }

    #[test]
    fn roundtrip_empty_input() {
        assert!(unseal(&[]).is_empty());
    }

    #[test]
    fn roundtrip_matches_itself() {
        let text = b"https://hollymachine.com/config.php";
        let stream = build_stream();
        let sealed: Vec<u8> = text
            .iter()
            .enumerate()
            .map(|(i, b)| b ^ stream[i % STREAM_LEN])
            .collect();
        assert_eq!(unseal(&sealed), text.to_vec());
    }
}
