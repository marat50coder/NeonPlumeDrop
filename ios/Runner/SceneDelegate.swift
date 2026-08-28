import Flutter
import UIKit

// Cold-start push tap capture — same two-channel contract as Bolt-of-Aether.
//
// iOS delivers a terminated-app notification tap through TWO channels:
//   1. UNUserNotificationCenterDelegate — Firebase Proxy captures this and
//      exposes it via `FirebaseMessaging.getInitialMessage()` on Dart.
//   2. Scene connection options — `connectionOptions.notificationResponse`.
//      Firebase does NOT intercept the scene lifecycle, so this is the
//      redundant safety net when Firebase swizzling missed the delivery.
//
// Written to UserDefaults under `flutter.plume_orbit_tap`
// (Dart key: `OrbitTapReader.dartKey`). Flutter's SharedPreferences
// strips `flutter.`.

class SceneDelegate: FlutterSceneDelegate {
  // Must stay in sync with `OrbitTapReader.dartKey`.
  private let tapUrlKey = "flutter.plume_orbit_tap"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let response = connectionOptions.notificationResponse,
       let url = extractUrl(from: response.notification.request.content.userInfo) {
      persist(url)
      #if DEBUG
      NSLog("[NPD.scene] cold-start push url captured")
      #endif
    }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL?.absoluteString {
      persist(url)
    }
    super.scene(scene, continue: userActivity)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    if let url = URLContexts.first?.url.absoluteString {
      persist(url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  // Payload URL extractor — MUST match Dart `FlarePulse._extract` so the
  // terminated-tap path and the Firebase-swizzled path pick the SAME link.
  // Historical bug: an "any string containing ://" catch-all loaded
  // `fcm_options.image` / `image_url` instead of the campaign destination.
  //
  // Strict rules (Bolt):
  //   • Only strings under one of the known URL keys count.
  //   • Recurse into nested dictionaries (any depth).
  //   • JSON-encoded blobs are parsed and rescanned, still key-restricted.
  // `click_url` is first — partner pnsynd payloads use that key.
  private static let urlKeys: [String] = [
    "click_url", "clickUrl",
    "target", "url", "deep_link", "link", "deeplink", "destination",
  ]

  private func extractUrl(from userInfo: [AnyHashable: Any]) -> String? {
    guard let dict = userInfo as? [String: Any] else { return nil }
    return scan(dict)
  }

  private func scan(_ dict: [String: Any]) -> String? {
    for key in Self.urlKeys {
      if let raw = dict[key] as? String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    for (_, value) in dict {
      if let nested = value as? [String: Any], let hit = scan(nested) {
        return hit
      }
      if let stringified = value as? String, let hit = parseBlob(stringified) {
        return hit
      }
    }
    return nil
  }

  private func parseBlob(_ blob: String) -> String? {
    let trimmed = blob.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any]
    else { return nil }
    return scan(json)
  }

  private func persist(_ url: String) {
    guard !url.isEmpty else { return }
    let defaults = UserDefaults.standard
    defaults.set(url, forKey: tapUrlKey)
    defaults.synchronize()
  }
}
