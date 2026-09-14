import Flutter
import ObjectiveC
import UIKit
import WebKit

// Deliberately minimal — same contract as Bolt-of-Aether.
// Firebase auto-configures from GoogleService-Info.plist via firebase_core
// (`FirebaseAppDelegateProxyEnabled = true`). Once the proxy is enabled,
// Firebase installs itself as the UNUserNotificationCenterDelegate so
// `getInitialMessage` / `onMessageOpenedApp` fire correctly. Overriding
// that delegate here — or calling `FirebaseApp.configure()` before plugin
// registration — breaks the delivery chain (tapped pushes never reach Dart).
//
// The only extra work is kicking APNs registration so a token can be
// minted on the first cold start, before Dart asks for permission.

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
