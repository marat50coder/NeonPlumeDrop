#ifndef NPD_GUARD_H
#define NPD_GUARD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Unseal + wire-wrap the sealed value at `idx`. Writes the byte length
// to `*out_len` and returns a freshly allocated buffer. The caller
// MUST invoke `ng_f` with the returned pointer + length to free it.
uint8_t *ng_u(uint32_t idx, size_t *out_len);

// Free a buffer previously returned by `ng_u` or `ng_c`.
void ng_f(uint8_t *ptr, size_t len);

// POST `body` (JSON, UTF-8, NUL-terminated) to the sealed endpoint
// with `ua` as the User-Agent. Writes the response byte length to
// `*out_len` and returns the UTF-8 body. Empty length means "fall back
// to the native game". Caller frees with `ng_f`.
uint8_t *ng_c(const char *body, const char *ua, size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* NPD_GUARD_H */
