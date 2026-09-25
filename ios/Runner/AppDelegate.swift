import Flutter
import ObjectiveC
import UIKit
import UserNotifications
import WebKit

// Firebase auto-configures from GoogleService-Info.plist via firebase_core
// (`FirebaseAppDelegateProxyEnabled = true`). We claim FlutterAppDelegate
// as the `UNUserNotificationCenter` delegate BEFORE Firebase's plugin
// registrar runs so that Firebase's swizzle chains to it — otherwise
// `getInitialMessage()` returns null on "close app + wait + tap" cold
// starts because Firebase never sees a delegate to hand the message to.
//
// APNs registration is kicked twice: once eagerly in
// `didFinishLaunchingWithOptions` so a token can be minted on the very
// first cold start, and once again after plugin registration so Firebase
// picks it up.

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate =
        self as UNUserNotificationCenterDelegate
    }
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
