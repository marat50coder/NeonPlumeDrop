/// AppsFlyer dashboard keys. Override at build time:
/// `--dart-define=APPSFLYER_DEV_KEY=... --dart-define=APPSFLYER_APPLE_APP_ID=...`
///
/// Leave the defaults empty to skip native init (conversion stays `unknown`).
class AppsFlyerConfig {
  AppsFlyerConfig._();

  static const String devKey = String.fromEnvironment(
    'APPSFLYER_DEV_KEY',
    defaultValue: '',
  );

  /// Numeric App Store id, without the `id` prefix.
  static const String appleAppId = String.fromEnvironment(
    'APPSFLYER_APPLE_APP_ID',
    defaultValue: '',
  );

  static bool get isConfigured => devKey.isNotEmpty && appleAppId.isNotEmpty;
}
