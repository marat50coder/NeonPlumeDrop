// ─────────────────────────────────────────────────────────────
// net — the config POST, performed inside the library
// ─────────────────────────────────────────────────────────────
// Dart hands us the already-composed partner body (flat JSON with
// the partner field names: af_id, bundle_id, os, store_id, locale,
// push_token, firebase_project_id, …) plus the forged User-Agent.
// We POST the sealed endpoint and return the response body verbatim
// as UTF-8.
//
// The endpoint lives only as a sealed byte array in `sealed.rs`
// (unsealed via `cloak::unseal`). Neither the URL nor the response
// ever appears as a Dart string literal in the AOT snapshot.
//
// No AEAD here — the current partner config.php does not speak the
// relay envelope. When a relay comes online, swap the body for a
// sealed envelope + relay endpoint without touching Dart.
// ─────────────────────────────────────────────────────────────

use std::time::Duration;

use crate::cloak;
use crate::sealed::{self, Idx};

fn unseal_str(idx: Idx) -> String {
    String::from_utf8(cloak::unseal(&sealed::fetch(idx))).unwrap_or_default()
}

fn post(endpoint: &str, body_json: &str, ua: &str) -> String {
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(8))
        .timeout(Duration::from_secs(20))
        .build();
    let req = agent
        .post(endpoint)
        .set("Content-Type", "application/json")
        .set("Accept", "application/json")
        .set("User-Agent", ua);
    match req.send_string(body_json) {
        Ok(resp) => resp.into_string().unwrap_or_default(),
        // A non-2xx carries no usable verdict — return empty so Dart
        // falls back to the native game.
        Err(_) => String::new(),
    }
}

/// Full roundtrip: look up the sealed endpoint, POST, return the
/// partner's answer verbatim. Empty string on any failure (endpoint
/// unsealable, transport error, non-2xx).
pub fn call(body_json: &str, ua: &str) -> String {
    let endpoint = unseal_str(Idx::Endpoint);
    if endpoint.is_empty() {
        return String::new();
    }
    post(&endpoint, body_json, ua)
}
