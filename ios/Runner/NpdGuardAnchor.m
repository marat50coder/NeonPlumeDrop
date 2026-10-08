// ─────────────────────────────────────────────────────────────
// NpdGuardAnchor — forces the libnpd_guard.a static archive into
// the final Runner binary.
// ─────────────────────────────────────────────────────────────
// `libnpd_guard.a` is reachable from Dart only through
// `DynamicLibrary.process()`; nothing in Swift / ObjC calls the
// `ng_*` exports directly. Without a hard reference the ld64 drops
// the whole archive, `dlsym` returns null, and the gray gate goes
// dormant for every user.
//
// `__attribute__((used, visibility("default")))` tells both the
// compiler (do not optimise away) AND the linker (export in dynsym),
// so Dart's `lookup` finds the symbols at runtime.
// ─────────────────────────────────────────────────────────────

#include <stddef.h>
#include <stdint.h>

extern uint8_t *ng_u(uint32_t idx, size_t *out_len);
extern void ng_f(uint8_t *ptr, size_t len);
extern uint8_t *ng_c(const char *body, const char *ua, size_t *out_len);

__attribute__((used, visibility("default")))
const void *const npd_guard_anchor[] = {
    (const void *)ng_u,
    (const void *)ng_f,
    (const void *)ng_c,
};
