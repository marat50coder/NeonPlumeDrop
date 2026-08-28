import Flutter
import UIKit

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }
}
