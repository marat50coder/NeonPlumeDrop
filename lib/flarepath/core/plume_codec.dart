/// Position-keyed XOR (not a stream cipher). Public URLs stay plaintext
/// in [FlareConfig]; only partner-facing tokens are folded here.
const List<int> _flareMask = <int>[
  0x4E, // N
  0x70, // p
  0x64, // d
  0x2E, // .
  0x46, // F
  0x6C, // l
  0x61, // a
  0x72, // r
  0x65, // e
  0x2A, // *
  0x32, // 2
  0x38, // 8
];

int _mix(int index) =>
    _flareMask[index % _flareMask.length] ^ ((index * 37 + 91) & 0xff);

String unwrapPlume(List<int> folded) {
  if (folded.isEmpty) return '';
  return String.fromCharCodes(
    List<int>.generate(
      folded.length,
      (index) => folded[index] ^ _mix(index),
    ),
  );
}
