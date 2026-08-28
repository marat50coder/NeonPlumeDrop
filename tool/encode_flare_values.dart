// ignore_for_file: avoid_print

const List<int> _flareMask = <int>[
  0x4E,
  0x70,
  0x64,
  0x2E,
  0x46,
  0x6C,
  0x61,
  0x72,
  0x65,
  0x2A,
  0x32,
  0x38,
];

int _mix(int index) =>
    _flareMask[index % _flareMask.length] ^ ((index * 37 + 91) & 0xff);

List<int> fold(String value) {
  return List<int>.generate(
    value.length,
    (index) => value.codeUnitAt(index) ^ _mix(index),
  );
}

String unfold(List<int> folded) {
  return String.fromCharCodes(
    List<int>.generate(
      folded.length,
      (index) => folded[index] ^ _mix(index),
    ),
  );
}

void main() {
  const values = <String, String>{
    'config': 'https://neonplumedrop.com/config.php',
    'gcd': 'https://gcdsdk.appsflyer.com/install_data/v5.0/',
    'appsFlyerDevKey': '8nyAh9JLozPkfRm2n3f6Nn',
    'firebaseProjectNumber': '857118764079',
    'oneLinkHost': 'neonplumedrop.onelink.me',
    'uaProduct': 'Mozilla/5.0',
    'uaPlatformPrefix': '(iPhone; CPU iPhone OS',
    'uaPlatformSuffix': 'like Mac OS X)',
    'uaEngine': 'AppleWebKit/605.1.15 (KHTML, like Gecko)',
    'uaMobileToken': 'Mobile/15E148',
    'safariVersion': '18.7',
    'safariTail': '604.1',
  };

  for (final entry in values.entries) {
    final encoded = fold(entry.value);
    print('${entry.key}: <int>[${encoded.join(', ')}]');
    if (unfold(encoded) != entry.value) {
      throw StateError('Round-trip failed for ${entry.key}');
    }
  }
  print('VERIFY: all values round-tripped');
}
