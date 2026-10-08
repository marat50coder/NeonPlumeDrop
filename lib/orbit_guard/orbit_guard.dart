// ─────────────────────────────────────────────────────────────
// orbit_guard — Dart ↔ Rust bridge for the sealed-value codec.
// ─────────────────────────────────────────────────────────────
// The Rust side (`rust/npd_guard`) owns every sealed byte array,
// the SplitMix32 keystream codec, and the config POST. Dart calls
// `OrbitGuard.read` with an opaque index — Rust unseals the array,
// wraps it in a per-call wire envelope, and returns a freshly
// allocated buffer that Dart decodes and immediately frees.
//
// Loading:
//   • iOS       — `DynamicLibrary.process()`. The static archive is
//                 force-anchored into the Runner binary via
//                 `ios/Runner/NpdGuardAnchor.m`.
//   • Android   — `DynamicLibrary.open('libnpd_guard.so')` (not yet
//                 wired on this project; iOS-only ships for now).
//   • Platforms without the lib → every call returns `""` and the
//                 app degrades to the native game path.
//
// Wire envelope (matches `rust/npd_guard/src/wire.rs`):
//   [ nonce(4 LE) | header(4 LE) | body (plain XOR'd with
//       48-byte SplitMix32 keystream derived from the nonce) ]
//   header == nonce XOR WIRE_KEY_MASK (0x9E3779B9)
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

// SplitMix32 round constants — must mirror `cloak.rs` / `wire.rs`.
const int _mixInc = 0x9E377_9B9;
const int _mixX1 = 0x7F4A_7C15;
const int _mixX2 = 0xC2B2_AE35;

// Wire constants — must mirror `wire.rs`.
const int _wireHeader = 8;
const int _wireStreamLen = 48;
const int _wireKeyMask = 0x9E37_79B9;

/// Index enum — mirror of `rust/npd_guard/src/sealed.rs::Idx`.
/// Change in both places together, re-run `tool/npd_pack.dart`.
enum SealedIndex {
  endpoint(0),
  gcdBase(1),
  attributionKey(2),
  messagingProject(3),
  oneLinkHost(4),

  uaProduct(10),
  uaPlatformPrefix(11),
  uaPlatformSuffix(12),
  uaEngine(13),
  uaMobileToken(14),
  safariVersion(15),
  safariTail(16),

  jsOrbitShell(30);

  const SealedIndex(this.raw);
  final int raw;
}

// ─── FFI signatures ──────────────────────────────────────────
typedef _NgUNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Uint32,
  ffi.Pointer<ffi.Size>,
);
typedef _NgUDart = ffi.Pointer<ffi.Uint8> Function(
  int,
  ffi.Pointer<ffi.Size>,
);

typedef _NgFNative = ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _NgFDart = void Function(ffi.Pointer<ffi.Uint8>, int);

typedef _NgCNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Size>,
);
typedef _NgCDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Size>,
);

abstract final class OrbitGuard {
  OrbitGuard._();

  static bool _probed = false;
  static ffi.DynamicLibrary? _lib;
  static _NgUDart? _ngU;
  static _NgFDart? _ngF;
  static _NgCDart? _ngC;

  /// `true` once the library has been located and all three FFI
  /// symbols resolved. If `false`, every `read` returns `""` and
  /// `call` returns `""` — the app silently falls back to the
  /// native game path instead of crashing.
  static bool get isAvailable {
    _ensure();
    return _ngU != null && _ngF != null && _ngC != null;
  }

  static void _ensure() {
    if (_probed) return;
    _probed = true;
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        _lib = ffi.DynamicLibrary.process();
      } else if (Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('libnpd_guard.so');
      } else if (Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libnpd_guard.so');
      } else if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('npd_guard.dll');
      }
      final ffi.DynamicLibrary? lib = _lib;
      if (lib == null) return;
      _ngU = lib
          .lookup<ffi.NativeFunction<_NgUNative>>('ng_u')
          .asFunction<_NgUDart>();
      _ngF = lib
          .lookup<ffi.NativeFunction<_NgFNative>>('ng_f')
          .asFunction<_NgFDart>();
      _ngC = lib
          .lookup<ffi.NativeFunction<_NgCNative>>('ng_c')
          .asFunction<_NgCDart>();
    } catch (_) {
      _lib = null;
      _ngU = null;
      _ngF = null;
      _ngC = null;
    }
  }

  /// Unseal + decode one entry. Returns `""` on any failure so
  /// callers only need to branch on `isEmpty`.
  static String read(SealedIndex idx) {
    _ensure();
    final _NgUDart? get = _ngU;
    final _NgFDart? free = _ngF;
    if (get == null || free == null) return '';

    final ffi.Pointer<ffi.Size> outLen = _calloc<ffi.Size>();
    if (outLen == ffi.nullptr) return '';
    ffi.Pointer<ffi.Uint8> ptr = ffi.nullptr;
    try {
      ptr = get(idx.raw, outLen);
      if (ptr == ffi.nullptr) return '';
      final int len = outLen.value;
      if (len < _wireHeader) return '';
      // Copy out before freeing — the Rust buffer disappears
      // the moment `free` runs.
      final Uint8List envelope = Uint8List.fromList(ptr.asTypedList(len));
      return _decodeWire(envelope);
    } catch (_) {
      return '';
    } finally {
      if (ptr != ffi.nullptr) {
        try {
          free(ptr, outLen.value);
        } catch (_) {}
      }
      _calfree(outLen.cast<ffi.Void>());
    }
  }

  /// Config POST: hand the assembled body + forged UA to the native
  /// caller which looks up the sealed endpoint, runs the HTTPS
  /// request, and returns the partner's answer verbatim. Returns
  /// `""` on any failure (library missing, transport error, 4xx /
  /// 5xx) so the caller falls back to the native game.
  static String call(String body, String ua) {
    _ensure();
    final _NgCDart? run = _ngC;
    final _NgFDart? free = _ngF;
    if (run == null || free == null) return '';

    final ffi.Pointer<ffi.Char> bodyPtr = _toCString(body);
    final ffi.Pointer<ffi.Char> uaPtr = _toCString(ua);
    final ffi.Pointer<ffi.Size> outLen = _calloc<ffi.Size>();
    if (bodyPtr == ffi.nullptr ||
        uaPtr == ffi.nullptr ||
        outLen == ffi.nullptr) {
      _calfree(bodyPtr.cast<ffi.Void>());
      _calfree(uaPtr.cast<ffi.Void>());
      _calfree(outLen.cast<ffi.Void>());
      return '';
    }
    ffi.Pointer<ffi.Uint8> ptr = ffi.nullptr;
    try {
      ptr = run(bodyPtr, uaPtr, outLen);
      if (ptr == ffi.nullptr) return '';
      final int len = outLen.value;
      if (len == 0) return '';
      final Uint8List out = Uint8List.fromList(ptr.asTypedList(len));
      return utf8.decode(out);
    } catch (_) {
      return '';
    } finally {
      if (ptr != ffi.nullptr) {
        try {
          free(ptr, outLen.value);
        } catch (_) {}
      }
      _calfree(bodyPtr.cast<ffi.Void>());
      _calfree(uaPtr.cast<ffi.Void>());
      _calfree(outLen.cast<ffi.Void>());
    }
  }

  // ─── wire envelope decoder ─────────────────────────────────
  static String _decodeWire(Uint8List envelope) {
    if (envelope.length < _wireHeader) return '';
    final ByteData bd = ByteData.view(envelope.buffer, envelope.offsetInBytes);
    final int nonce = bd.getUint32(0, Endian.little);
    final int header = bd.getUint32(4, Endian.little);
    if ((nonce ^ _wireKeyMask) & 0xFFFFFFFF != header) return '';
    final Uint8List stream = _streamFromNonce(nonce);
    final int bodyLen = envelope.length - _wireHeader;
    if (bodyLen == 0) return '';
    final Uint8List plain = Uint8List(bodyLen);
    for (int i = 0; i < bodyLen; i++) {
      plain[i] = envelope[_wireHeader + i] ^ stream[i % _wireStreamLen];
    }
    try {
      return utf8.decode(plain);
    } catch (_) {
      return '';
    }
  }

  static Uint8List _streamFromNonce(int nonce) {
    int state = 0;
    for (int i = 0; i < 4; i++) {
      final int b = (nonce >> (i * 8)) & 0xFF;
      state = (state + b) & 0xFFFFFFFF;
      state = (state * _mixInc) & 0xFFFFFFFF;
    }
    if (state == 0) state = _mixInc;
    final Uint8List out = Uint8List(_wireStreamLen);
    for (int i = 0; i < _wireStreamLen; i++) {
      state = (state + _mixInc) & 0xFFFFFFFF;
      int z = state;
      z = ((z ^ (z >> 16)) * _mixX1) & 0xFFFFFFFF;
      z = ((z ^ (z >> 13)) * _mixX2) & 0xFFFFFFFF;
      z = z ^ (z >> 16);
      out[i] = (z >> 8) & 0xFF;
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────
// Minimal replacement for `package:ffi::calloc` — one allocation
// + free, both via libc malloc/free from the current process.
// ─────────────────────────────────────────────────────────────
typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.Size);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

final _MallocDart _mallocFn = ffi.DynamicLibrary.process()
    .lookup<ffi.NativeFunction<_MallocNative>>('malloc')
    .asFunction<_MallocDart>();

final _FreeDart _freeFn = ffi.DynamicLibrary.process()
    .lookup<ffi.NativeFunction<_FreeNative>>('free')
    .asFunction<_FreeDart>();

ffi.Pointer<T> _calloc<T extends ffi.NativeType>() {
  final int size = ffi.sizeOf<ffi.Size>();
  final ffi.Pointer<ffi.Void> raw = _mallocFn(size);
  if (raw == ffi.nullptr) return ffi.nullptr.cast<T>();
  raw.cast<ffi.Uint8>().asTypedList(size).fillRange(0, size, 0);
  return raw.cast<T>();
}

void _calfree(ffi.Pointer<ffi.Void> ptr) {
  if (ptr == ffi.nullptr) return;
  _freeFn(ptr);
}

/// Allocates a NUL-terminated UTF-8 C string via libc `malloc`.
/// Caller frees it with `_calfree(ptr.cast())`.
ffi.Pointer<ffi.Char> _toCString(String value) {
  final List<int> bytes = utf8.encode(value);
  final int size = bytes.length + 1;
  final ffi.Pointer<ffi.Void> raw = _mallocFn(size);
  if (raw == ffi.nullptr) return ffi.nullptr.cast<ffi.Char>();
  final Uint8List view = raw.cast<ffi.Uint8>().asTypedList(size);
  view.setRange(0, bytes.length, bytes);
  view[bytes.length] = 0;
  return raw.cast<ffi.Char>();
}
