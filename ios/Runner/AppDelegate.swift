import Flutter
import ObjectiveC
import UIKit
import WebKit

// Deliberately minimal — matches the proven pattern from Bolt-of-Aether
// and FeatherfieldFrenzy. Firebase auto-configures via firebase_core at
// GeneratedPluginRegistrant time (`FirebaseAppDelegateProxyEnabled =
// true` in Info.plist). Once the proxy is enabled Firebase installs
// itself as the UNUserNotificationCenterDelegate so `getInitialMessage`
// / `onMessageOpenedApp` fire correctly. Overriding that delegate here
// — or calling `FirebaseApp.configure()` before plugin registration —
// breaks the delivery chain (tapped pushes silently never reach Dart).
//
// The only extra work is kicking APNs registration so a token can be
// minted on the very first cold start, before Dart asks for permission.

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.registerForRemoteNotifications()
    OrbitWebKit.preferMobilePages()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NpdLog") {
      FlutterMethodChannel(
        name: "npd/log",
        binaryMessenger: registrar.messenger()
      ).setMethodCallHandler { call, result in
        if call.method == "line", let line = call.arguments as? String {
          NSLog("%@", line)
        }
        result(nil)
      }
    }
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }
}

/// iPadOS WKWebView defaults to desktop browsing. Partner pages then
/// reject the session even when config.php already returned a URL.
enum OrbitWebKit {
  static func preferMobilePages() {
    guard #available(iOS 13.0, *) else { return }
    let original = class_getInstanceMethod(
      WKWebView.self,
      #selector(WKWebView.init(frame:configuration:))
    )
    let swizzled = class_getInstanceMethod(
      WKWebView.self,
      #selector(WKWebView.npd_init(frame:configuration:))
    )
    guard let original, let swizzled else { return }
    method_exchangeImplementations(original, swizzled)
  }
}

extension WKWebView {
  @objc func npd_init(
    frame: CGRect,
    configuration: WKWebViewConfiguration
  ) -> WKWebView {
    if #available(iOS 13.0, *) {
      configuration.defaultWebpagePreferences.preferredContentMode = .mobile
    }
    return npd_init(frame: frame, configuration: configuration)
  }
}
