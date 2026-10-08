import '../../orbit_guard/orbit_guard.dart';

/// Static gray-flow configuration.
///
/// Only two kinds of values live here:
///   • timing / numeric constants that are safe in plaintext,
///   • the WHITE-part public URLs (privacy, support) which the Play /
///     App Store listings reference verbatim.
///
/// Every partner-facing secret (endpoint, AppsFlyer dev key, Firebase
/// project number, OneLink host, UA fragments, link-fix JS) lives
/// inside the native `npd_guard` static archive and is read on demand
/// through `OrbitGuard.read(...)`. The old Dart XOR codec and inline
/// byte arrays have been removed — a reverse-engineer walking the Dart
/// AOT snapshot finds no partner strings here.
abstract final class FlareConfig {
  static const String appTitle = 'Neon Plume Drop';
  static const String bundleId = 'com.neonplumedrop.neonplumedropgame';
  static const String iosStoreId = '6802372375';

  /// 2d 19h 6m — under a 3-day clock jump so QA sees the invite again.
  static const int pushSnoozeSeconds = 241560;
  static const int organicRecheckSeconds = 8;
  static const int savedUrlExpiryDays = 6;
  static const int exchangeTimeoutMs = 18400;
  static const int installSignalTimeoutMs = 60000;
  static const int returningSignalTimeoutMs = 7100;
  static const int attPromptDelayMs = 540;
  static const int redirectLoopBudget = 2;
  static const int apnsPollTries = 7;
  static const int apnsPollStepMs = 640;
  static const int pageSettleMs = 1100;
  static const int coldViewportMs = 410;

  static const List<int> reflowPokesMs = <int>[55, 190, 380, 620, 940];

  /// White-part Privacy Policy URL. Public, must match the Play /
  /// App Store listing and never 404 (FINAL_CHECKLIST Part C.5).
  static const String privacyUrl =
      'https://neonplumedrop.com/privacy-policy.html';

  /// White-part Support URL. Public per Play / App Store policy.
  static const String supportUrl = 'https://neonplumedrop.com/support.html';

  /// Hex-prefixed iOS App Store identifier used in gray config bodies.
  static const String storeToken = 'id$iosStoreId';

  // ── Lazy accessors into the native guard ─────────────────
  // Each getter unseals on demand and caches the plaintext for the
  // process lifetime. Returns `""` when the guard is not available
  // on the current platform (desktop test runs, debug builds without
  // the Rust archive linked) so callers only need to branch on
  // `isEmpty`.

  static String? _attributionKey;
  static String get appsFlyerKey {
    final cached = _attributionKey;
    if (cached != null) return cached;
    return _attributionKey = OrbitGuard.read(SealedIndex.attributionKey);
  }

  static String? _messagingProject;
  static String get firebaseProjectNumber {
    final cached = _messagingProject;
    if (cached != null) return cached;
    return _messagingProject = OrbitGuard.read(SealedIndex.messagingProject);
  }

  static String? _gcdBase;
  static String get gcdBase {
    final cached = _gcdBase;
    if (cached != null) return cached;
    return _gcdBase = OrbitGuard.read(SealedIndex.gcdBase);
  }

  static String? _oneLinkHost;
  static String get oneLinkHost {
    final cached = _oneLinkHost;
    if (cached != null) return cached;
    return _oneLinkHost = OrbitGuard.read(SealedIndex.oneLinkHost);
  }

  /// Gate stays dormant until the native guard loads AND the three
  /// mandatory secrets unseal to non-empty strings. This means a QA
  /// build without the Rust archive degrades to white-only, never
  /// crashes, and never partially-enables the gray branch.
  static bool get grayCredentialsReady =>
      OrbitGuard.isAvailable &&
      appsFlyerKey.isNotEmpty &&
      firebaseProjectNumber.isNotEmpty;
}
