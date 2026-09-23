import Flutter
import UIKit

// Cold-start push tap capture — same contract as Featherfield / Bolt.
// Do NOT claim AppsFlyer Universal Links here: associated domains plus
// handleOpen before the SDK starts intercept Safari clicks so OneLink
// never records, then GCD comes back Organic / NOT_FOUND.

class SceneDelegate: FlutterSceneDelegate {
  // Must stay in sync with `OrbitTapReader.dartKey`.
  private let tapUrlKey = "flutter.plume_orbit_tap"
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
        store.set(url, forKey: tapUrlKey)
        #if DEBUG
        NSLog("[NPD.scene] cold-start push url captured")
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
