import '../core/plume_codec.dart';

abstract final class FlareConfig {
  static const String appTitle = 'Neon Plume Drop';
  static const String bundleId = 'com.neonplumedrop.neonplumedropgame';
  static const String iosStoreId = '6802372375';

  /// 2d 19h 6m — under a 3-day clock jump so QA sees the invite again.
  static const int pushSnoozeSeconds = 241560;
  static const int organicRecheckSeconds = 11;
  static const int savedUrlExpiryDays = 6;
  static const int exchangeTimeoutMs = 18400;
  static const int installSignalTimeoutMs = 7400;
  static const int returningSignalTimeoutMs = 7100;
  static const int attPromptDelayMs = 540;
  static const int redirectLoopBudget = 2;
  static const int apnsPollTries = 7;
  static const int apnsPollStepMs = 640;
  static const int pageSettleMs = 1100;
  static const int coldViewportMs = 410;

  static const List<int> reflowPokesMs = <int>[55, 190, 380, 620, 940];

  static const String privacyUrl =
      'https://neonplumedrop.com/privacy-policy.html';
  static const String supportUrl = 'https://neonplumedrop.com/support.html';

  static const List<int> _endpoint = <int>[
    125, 132, 181, 148, 218, 66, 119, 3, 136, 231, 144, 164, 41, 32, 112, 197,
    136, 216, 230, 7, 42, 96, 216, 249, 240, 167, 26, 3, 79, 134, 185, 195,
    176, 122, 31, 34,
  ];
  static const List<int> _gcd = <int>[
    125, 132, 181, 148, 218, 66, 119, 3, 129, 225, 155, 185, 61, 39, 43, 201,
    157, 204, 231, 14, 54, 55, 222, 228, 179, 235, 22, 1, 14, 137, 190, 215,
    234, 107, 27, 62, 158, 160, 220, 164, 4, 11, 122, 213, 252, 198, 28,
  ];
  static const List<int> _appsFlyerKey = <int>[
    45, 158, 184, 165, 193, 65, 18, 96, 137, 248, 175, 161, 63, 30, 104, 154,
    131, 143, 242, 94, 20, 32,
  ];
  static const List<int> _firebaseProject = <int>[
    45, 197, 246, 213, 152, 64, 111, 26, 210, 178, 200, 243,
  ];
  static const List<int> _oneLinkHost = <int>[
    123, 149, 174, 138, 217, 20, 45, 65, 131, 230, 141, 165, 41, 98, 106, 198,
    136, 208, 253, 6, 49, 96, 214, 243,
  ];
  static const List<int> _uaProduct = <int>[
    88, 159, 187, 141, 197, 20, 57, 3, 211, 172, 207,
  ];
  static const List<int> _uaPlatformPrefix = <int>[
    61, 153, 145, 140, 198, 22, 61, 23, 198, 193, 175, 159, 121, 37, 85, 192,
    130, 210, 241, 72, 21, 29,
  ];
  static const List<int> _uaPlatformSuffix = <int>[
    121, 153, 170, 129, 137, 53, 57, 79, 198, 205, 172, 234, 1, 101,
  ];
  static const List<int> _uaEngine = <int>[
    84, 128, 177, 136, 204, 47, 61, 78, 173, 235, 139, 229, 111, 124, 48, 134,
    220, 146, 165, 93, 122, 102, 240, 222, 201, 197, 53, 64, 1, 140, 185, 207,
    251, 42, 48, 55, 162, 175, 210, 249,
  ];
  static const List<int> _uaMobileToken = <int>[
    88, 159, 163, 141, 197, 29, 119, 29, 211, 199, 206, 254, 97,
  ];
  static const List<int> _safariVersion = <int>[36, 200, 239, 211];
  static const List<int> _safariTail = <int>[35, 192, 245, 202, 152];

  static String get endpoint => unwrapPlume(_endpoint);
  static String get gcdBase => unwrapPlume(_gcd);
  static String get appsFlyerKey => unwrapPlume(_appsFlyerKey);
  static String get firebaseProjectNumber => unwrapPlume(_firebaseProject);
  static String get oneLinkHost => unwrapPlume(_oneLinkHost);
  static String get uaProduct => unwrapPlume(_uaProduct);
  static String get uaPlatformPrefix => unwrapPlume(_uaPlatformPrefix);
  static String get uaPlatformSuffix => unwrapPlume(_uaPlatformSuffix);
  static String get uaEngine => unwrapPlume(_uaEngine);
  static String get uaMobileToken => unwrapPlume(_uaMobileToken);
  static String get safariVersion => unwrapPlume(_safariVersion);
  static String get safariTail => unwrapPlume(_safariTail);

  static String get storeToken => 'id$iosStoreId';

  /// Gate needs endpoint + AF key + Firebase project number only.
  /// OneLink is optional and must never disable the flow.
  static bool get grayCredentialsReady =>
      endpoint.isNotEmpty &&
      appsFlyerKey.isNotEmpty &&
      firebaseProjectNumber.isNotEmpty;
}
