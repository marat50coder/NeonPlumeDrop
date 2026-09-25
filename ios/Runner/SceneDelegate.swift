import Flutter
import UIKit

// Cold-start push tap capture — same contract as Featherfield / Bolt.
// Do NOT claim AppsFlyer Universal Links here: associated domains plus
// handleOpen before the SDK starts intercept Safari clicks so OneLink
// never records, then GCD comes back Organic / NOT_FOUND.

class SceneDelegate: FlutterSceneDelegate {
  // Universal Link / URL scheme tap. May carry a OneLink URL — the Dart
  // side runs it through the AppsFlyer attribution filter before
  // deciding whether to open it.
  // Must stay in sync with `OrbitTapReader.dartKey`.
  private let tapUrlKey = "flutter.plume_orbit_tap"
  // Cold-start push notification tap URL. Kept SEPARATE from tapUrlKey
  // because the AppsFlyer attribution filter (`_isCampaignHost`) would
  // otherwise swallow OneLink promo URLs that the partner sent through
  // FCM — the user explicitly tapped a notification with this URL, it
  // must open as a destination, not be re-attributed.
  private let pushUrlKey = "flutter.plume_orbit_push"
  // Set to `true` the moment iOS wakes the app from a notification tap.
  private let coldNotifKey = "flutter.plume_orbit_cold_notification"
  // Full push payload JSON — always written when a notification launches
  // the scene, so Dart can log what really came through.
  private let coldNotifDumpKey = "flutter.plume_orbit_cold_notification_dump"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let response = connectionOptions.notificationResponse {
      let userInfo = response.notification.request.content.userInfo
      let store = UserDefaults.standard
      store.set(true, forKey: coldNotifKey)
      let dump = dumpJson(userInfo) ?? "<un-jsonable>"
      store.set(dump, forKey: coldNotifDumpKey)
      NSLog("[NPD.scene] cold-start notification userInfo=%@", dump)
      // Delegates to `PushCapture` — same slot the AppDelegate hook
      // uses so Dart's single MethodChannel read picks up the URL no
      // matter which iOS entry point delivered the tap.
      PushCapture.store(userInfo)
      store.synchronize()
    }
    for activity in connectionOptions.userActivities {
      if activity.activityType == NSUserActivityTypeBrowsingWeb,
         let url = activity.webpageURL {
        persist(url.absoluteString)
        NSLog("[NPD.scene] cold-start web url captured %@", url.absoluteString)
      }
    }
    for context in connectionOptions.urlContexts {
      persist(context.url.absoluteString)
      NSLog("[NPD.scene] cold-start url scheme captured %@", context.url.absoluteString)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      persist(url.absoluteString)
    }
    super.scene(scene, continue: userActivity)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    if let url = URLContexts.first?.url {
      persist(url.absoluteString)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  // MARK: - URL extraction

  private static let urlKeys: [String] = [
    "click_url", "clickUrl",
    "target", "url", "deep_link", "link", "deeplink", "destination",
  ]

  /// Non-URL-carrying keys that Firebase / Google plumbing owns. We skip
  /// them in the last-resort http-scan to avoid opening telemetry links.
  private static let ignoredKeyPrefixes: [String] = [
    "google.", "gcm.", "aps", "fcm_", "com.google.",
  ]

  struct ExtractedUrl {
    let url: String
    let source: String
  }

  static func extractUrl(from userInfo: [AnyHashable: Any]) -> ExtractedUrl? {
    if let hit = scan(userInfo) { return hit }
    return httpScan(userInfo)
  }

  private static func scan(
    _ dict: [AnyHashable: Any],
    keyPath: String = ""
  ) -> ExtractedUrl? {
    for key in urlKeys {
      if let raw = dict[key] as? String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          let source = keyPath.isEmpty ? key : "\(keyPath).\(key)"
          return ExtractedUrl(url: trimmed, source: source)
        }
      }
    }
    for (key, value) in dict {
      let keyText = "\(key)"
      let nextPath = keyPath.isEmpty ? keyText : "\(keyPath).\(keyText)"
      if let nested = value as? [AnyHashable: Any] {
        if let hit = scan(nested, keyPath: nextPath) { return hit }
      }
      if let stringified = value as? String,
         let hit = parseBlob(stringified, keyPath: nextPath) {
        return hit
      }
    }
    return nil
  }

  private static func httpScan(
    _ value: Any,
    keyPath: String = ""
  ) -> ExtractedUrl? {
    if let map = value as? [AnyHashable: Any] {
      for (key, nested) in map {
        let keyText = "\(key)"
        let path = keyPath.isEmpty ? keyText : "\(keyPath).\(keyText)"
        if ignoredKeyPrefixes.contains(where: { path.hasPrefix($0) }) {
          continue
        }
        if let hit = httpScan(nested, keyPath: path) { return hit }
      }
      return nil
    }
    if let list = value as? [Any] {
      for item in list {
        if let hit = httpScan(item, keyPath: keyPath) { return hit }
      }
      return nil
    }
    if let text = value as? String {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
        return ExtractedUrl(url: trimmed, source: keyPath.isEmpty ? "<root>" : keyPath)
      }
    }
    return nil
  }

  private static func parseBlob(
    _ blob: String,
    keyPath: String
  ) -> ExtractedUrl? {
    let trimmed = blob.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data)
            as? [AnyHashable: Any]
    else { return nil }
    return scan(json, keyPath: keyPath)
  }

  // MARK: - Universal link / URL scheme

  private func persist(_ url: String) {
    guard !url.isEmpty else { return }
    let defaults = UserDefaults.standard
    defaults.set(url, forKey: tapUrlKey)
    defaults.synchronize()
  }

  /// Serialise anything JSON-able for Dart-side debug logs.
  private func dumpJson(_ payload: [AnyHashable: Any]) -> String? {
    let sanitized = sanitize(payload)
    guard JSONSerialization.isValidJSONObject(sanitized) else { return nil }
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: sanitized, options: [.sortedKeys]
      )
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func sanitize(_ value: Any) -> Any {
    if let map = value as? [AnyHashable: Any] {
      var out: [String: Any] = [:]
      for (key, val) in map {
        out["\(key)"] = sanitize(val)
      }
      return out
    }
    if let list = value as? [Any] {
      return list.map(sanitize)
    }
    if let text = value as? String { return text }
    if let num = value as? NSNumber { return num }
    if let bool = value as? Bool { return bool }
    return "\(value)"
  }
}
