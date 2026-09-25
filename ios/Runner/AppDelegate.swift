import Flutter
import ObjectiveC
import UIKit
import UserNotifications
import WebKit

// Firebase auto-configures from GoogleService-Info.plist via
// firebase_core (`FirebaseAppDelegateProxyEnabled = true`). We claim
// FlutterAppDelegate as the `UNUserNotificationCenter` delegate so we
// can capture every tap into `PushCapture` — the Firebase SDK's own
// `getInitialMessage()` becomes unreliable after ~10s of the app being
// suspended / killed (Vortixa uses this same pattern and it works
// through long waits where Firebase alone fails).

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate =
      self as UNUserNotificationCenterDelegate

    // Backup capture path — some iOS launches deliver the tap payload
    // via `launchOptions.remoteNotification` (pre-scene UIApplication).
    if let launch = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      PushCapture.store(launch)
    }

    application.registerForRemoteNotifications()
    OrbitWebKit.preferMobilePages()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Grab the URL BEFORE Firebase's swizzled handler runs. Both
    // handlers still fire (super forwards to Firebase via
    // FlutterAppDelegate → firebase_messaging), so `onMessageOpenedApp`
    // and `getInitialMessage` continue to work when they can.
    PushCapture.store(response.notification.request.content.userInfo)
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NpdPush") {
      FlutterMethodChannel(
        name: "npd/push",
        binaryMessenger: registrar.messenger()
      ).setMethodCallHandler { call, result in
        switch call.method {
        case "consume":
          result(PushCapture.take())
        default:
          result(FlutterMethodNotImplemented)
        }
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
