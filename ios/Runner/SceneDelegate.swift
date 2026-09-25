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
  // Dart reads it in FlarePulse to know it must wait a bit longer for
  // the URL — Firebase on iOS sometimes delivers the payload via
  // `onMessageOpenedApp` a beat AFTER `getInitialMessage()` returns.
  private let coldNotifKey = "flutter.plume_orbit_cold_notification"
  // Full push payload JSON. Written whenever a cold-start tap arrived
  // WITHOUT a resolvable URL — lets us see in the log what actually
  // came through and confirm whether the sender included any URL field.
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
      if let dump = dumpJson(userInfo) {
        store.set(dump, forKey: coldNotifDumpKey)
      }
      if let url = extractUrl(from: userInfo) {
        // Push destination — never routed through campaign attribution.
        store.set(url, forKey: pushUrlKey)
        #if DEBUG
        NSLog("[NPD.scene] cold-start push url captured (push key)")
        #endif
      } else {
        #if DEBUG
        NSLog("[NPD.scene] cold-start push HAD NO URL — payload dumped for Dart")
        #endif
      }
      store.synchronize()
    }
    for activity in connectionOptions.userActivities {
      if activity.activityType == NSUserActivityTypeBrowsingWeb,
         let url = activity.webpageURL {
        persist(url.absoluteString)
        #if DEBUG
        NSLog("[NPD.scene] cold-start web url captured")
        #endif
      }
    }
    for context in connectionOptions.urlContexts {
      persist(context.url.absoluteString)
      #if DEBUG
      NSLog("[NPD.scene] cold-start url scheme captured")
      #endif
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

  private static let urlKeys: [String] = [
    "click_url", "clickUrl",
    "target", "url", "deep_link", "link", "deeplink", "destination",
  ]

  private func extractUrl(from userInfo: [AnyHashable: Any]) -> String? {
    guard let dict = userInfo as? [String: Any] else { return nil }
    if let hit = scan(dict) { return hit }
    // Last resort: some senders shove the URL under an ad-hoc key we do
    // not know about. Rather than miss the tap, walk every string in the
    // payload and pick the first `http(s)://` value. Skip the noisy
    // Firebase / Google plumbing keys so we do not open telemetry links.
    return httpScan(dict)
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

  private static let ignoredKeyPrefixes: [String] = [
    "google.", "gcm.", "aps", "fcm_", "com.google.",
  ]

  private func httpScan(_ value: Any, keyPath: String = "") -> String? {
    if let map = value as? [String: Any] {
      for (key, nested) in map {
        let path = keyPath.isEmpty ? key : "\(keyPath).\(key)"
        if Self.ignoredKeyPrefixes.contains(where: { path.hasPrefix($0) }) {
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
        return trimmed
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
