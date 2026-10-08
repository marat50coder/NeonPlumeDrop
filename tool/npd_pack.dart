// ─────────────────────────────────────────────────────────────
// npd_pack — seal `tool/npd_guard.recipe.json` into Rust byte
// arrays and write them into `rust/npd_guard/src/sealed.rs`.
// ─────────────────────────────────────────────────────────────
// Mirrors `rust/npd_guard/src/cloak.rs` byte-for-byte so every
// value sealed here unseals back to the exact plaintext inside
// the Rust guard.
//
// Run locally after editing the recipe:
//
//     dart run tool/npd_pack.dart
//
// The recipe JSON is gitignored. Only the sealed byte arrays
// land in the repo, inside `sealed.rs`.
// ─────────────────────────────────────────────────────────────

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// MUST match `rust/npd_guard/src/cloak.rs::STREAM_LEN`.
const int _streamLen = 37;

/// SplitMix32 round constants — mirror of `cloak.rs`.
const int _mixInc = 0x9E377_9B9;
const int _mixX1 = 0x7F4A_7C15;
const int _mixX2 = 0xC2B2_AE35;

/// MUST match the salt bytes in `rust/npd_guard/src/cloak.rs::salt()`.
const List<int> _salt = <int>[
  0xA1, 0x3F, 0x7C, 0x95,
  0x28, 0xB4, 0x5D, 0x02,
  0xE6, 0x81, 0x49, 0x7A,
  0xD5, 0x1C, 0x9F, 0x38,
  0x6B, 0xC2, 0x04, 0xEE,
];

int _u32(int v) => v & 0xFFFFFFFF;

List<int> _buildStream() {
  var state = 0;
  for (final b in _salt) {
    state = _u32(state + b);
    state = _u32(state * _mixInc);
  }
  if (state == 0) state = _mixInc;
  final out = List<int>.filled(_streamLen, 0);
  for (var i = 0; i < _streamLen; i++) {
    state = _u32(state + _mixInc);
    var z = state;
    z = _u32((z ^ (z >> 16)) * _mixX1);
    z = _u32((z ^ (z >> 13)) * _mixX2);
    z = z ^ (z >> 16);
    out[i] = (z >> 8) & 0xFF;
  }
  return out;
}

List<int> _seal(String value, List<int> stream) {
  if (value.isEmpty) return const <int>[];
  final bytes = utf8.encode(value);
  final out = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ stream[i % _streamLen];
  }
  return out;
}

String _unseal(List<int> sealed, List<int> stream) {
  if (sealed.isEmpty) return '';
  final plain = List<int>.filled(sealed.length, 0);
  for (var i = 0; i < sealed.length; i++) {
    plain[i] = sealed[i] ^ stream[i % _streamLen];
  }
  return utf8.decode(plain);
}

/// Idx label → recipe key. Keep the order aligned with
/// `rust/npd_guard/src/sealed.rs::Idx` so a visual sweep across the
/// two files reads the same.
const List<MapEntry<String, String>> _slots = <MapEntry<String, String>>[
  MapEntry('Endpoint', 'endpoint'),
  MapEntry('GcdBase', 'gcdBase'),
  MapEntry('AttributionKey', 'attributionKey'),
  MapEntry('MessagingProject', 'messagingProject'),
  MapEntry('OneLinkHost', 'oneLinkHost'),
  MapEntry('UaProduct', 'uaProduct'),
  MapEntry('UaPlatformPrefix', 'uaPlatformPrefix'),
  MapEntry('UaPlatformSuffix', 'uaPlatformSuffix'),
  MapEntry('UaEngine', 'uaEngine'),
  MapEntry('UaMobileToken', 'uaMobileToken'),
  MapEntry('SafariVersion', 'safariVersion'),
  MapEntry('SafariTail', 'safariTail'),
  MapEntry('JsOrbitShell', 'jsOrbitShell'),
];

const Map<String, int> _idxCode = <String, int>{
  'Endpoint': 0,
  'GcdBase': 1,
  'AttributionKey': 2,
  'MessagingProject': 3,
  'OneLinkHost': 4,

  'UaProduct': 10,
  'UaPlatformPrefix': 11,
  'UaPlatformSuffix': 12,
  'UaEngine': 13,
  'UaMobileToken': 14,
  'SafariVersion': 15,
  'SafariTail': 16,

  'JsOrbitShell': 30,
};

String _formatByteArray(List<int> bytes, {int indent = 8}) {
  if (bytes.isEmpty) return '${' ' * indent}// empty';
  final buffer = StringBuffer();
  final pad = ' ' * indent;
  final line = StringBuffer()..write(pad);
  var inLine = 0;
  for (var i = 0; i < bytes.length; i++) {
    final hex = '0x${bytes[i].toRadixString(16).toUpperCase().padLeft(2, '0')}';
    final piece = i == bytes.length - 1 ? hex : '$hex, ';
    if (inLine >= 10) {
      buffer.writeln(line.toString().trimRight());
      line
        ..clear()
        ..write(pad);
      inLine = 0;
    }
    line.write(piece);
    inLine++;
  }
  final tail = line.toString().trimRight();
  if (tail.isNotEmpty) buffer.writeln(tail);
  return buffer.toString().trimRight();
}

Future<String> _resolveValue(dynamic raw) async {
  if (raw is! String) return '';
  if (raw.startsWith('file:')) {
    final path = raw.substring(5);
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Recipe references missing file $path');
    }
    return await file.readAsString();
  }
  return raw;
}

Future<void> main() async {
  final root = Directory.current.path;
  final recipePath = '$root/tool/npd_guard.recipe.json';
  final recipeFile = File(recipePath);
  if (!recipeFile.existsSync()) {
    stderr.writeln(
      '✗ Recipe not found at $recipePath. Copy '
      '`tool/npd_guard.recipe.example.json` to that path, fill it in, '
      'then re-run.',
    );
    exit(2);
  }

  final recipe = jsonDecode(await recipeFile.readAsString());
  if (recipe is! Map) {
    stderr.writeln('✗ Recipe must decode to a JSON object.');
    exit(2);
  }

  final stream = _buildStream();

  final arms = StringBuffer();
  final helpers = StringBuffer();

  for (final slot in _slots) {
    final idx = slot.key;
    final key = slot.value;
    final value = await _resolveValue(recipe[key]);
    final sealed = _seal(value, stream);
    final decoded = _unseal(sealed, stream);
    if (decoded != value) {
      throw StateError('Round-trip failed for $idx');
    }

    final helperName = _helperName(key);
    arms.writeln('        Idx::$idx => $helperName(),');
    helpers
      ..writeln('/// Idx::$idx (${sealed.length} bytes)')
      ..writeln('fn $helperName() -> Vec<u8> {')
      ..writeln('    obfbytes!(&[')
      ..writeln(_formatByteArray(sealed))
      ..writeln('    ]).to_vec()')
      ..writeln('}')
      ..writeln();
  }

  final idxEntries = StringBuffer();
  final fromRawArms = StringBuffer();
  for (final slot in _slots) {
    final idx = slot.key;
    final code = _idxCode[idx]!;
    idxEntries.writeln('    $idx = $code,');
    fromRawArms.writeln('            $code => Idx::$idx,');
  }

  final sealedRs = '''
// ─────────────────────────────────────────────────────────────
// sealed — raw byte arrays, generated by `tool/npd_pack.dart`
// from `tool/npd_guard.recipe.json` (gitignored).
//
// Each array is meaningful only after `cloak::unseal` runs on it.
// Static scanners (`strings libnpd_guard.a`) see random noise;
// every array is also wrapped in `obfstr::obfbytes!` so even a
// `.rodata` dump never contains a sealed payload as a contiguous
// run.
//
// DO NOT HAND-EDIT. Re-run `dart run tool/npd_pack.dart` after
// changing the recipe.
// ─────────────────────────────────────────────────────────────

use obfstr::obfbytes;

/// Index enum — opaque u32 crossing the FFI boundary. Keep in
/// sync with `lib/orbit_guard/orbit_guard.dart::SealedIndex`.
#[repr(u32)]
#[derive(Copy, Clone, Debug)]
#[allow(dead_code)]
pub enum Idx {
${idxEntries.toString().trimRight()}
}

impl Idx {
    pub fn from_raw(raw: u32) -> Option<Self> {
        Some(match raw {
${fromRawArms.toString().trimRight()}
            _ => return None,
        })
    }
}

pub fn fetch(idx: Idx) -> Vec<u8> {
    match idx {
${arms.toString().trimRight()}
    }
}

${helpers.toString().trimRight()}
''';

  final sealedPath = '$root/rust/npd_guard/src/sealed.rs';
  await File(sealedPath).writeAsString(sealedRs);
  print('✓ Wrote $sealedPath (${_slots.length} slots)');
}

String _helperName(String key) {
  final buf = StringBuffer()..write('bytes_');
  for (var i = 0; i < key.length; i++) {
    final ch = key[i];
    if (ch == ch.toUpperCase() && ch != ch.toLowerCase() && i > 0) {
      buf.write('_');
    }
    buf.write(ch.toLowerCase());
  }
  return buf.toString();
}
