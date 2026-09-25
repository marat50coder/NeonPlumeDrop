import Foundation
import UserNotifications

/// In-memory + UserDefaults slot for the URL that launched the app from
/// a push tap. Written by `SceneDelegate.willConnectTo` and by
/// `AppDelegate.userNotificationCenter(_:didReceive:...)`. Read by Dart
/// through the `npd/push` MethodChannel — that read hits Swift memory
/// (or UserDefaults fresh, never SharedPreferences cache), so it works
/// even after Firebase's internal message store has been dropped by iOS
/// (the "close app + wait 15s + tap push" symptom).
enum PushCapture {
  static let storageKey = "flutter.plume_orbit_push"

  private static let queue = DispatchQueue(label: "npd.push.capture")
  private static var _pending: String?

  static func store(_ userInfo: [AnyHashable: Any]) {
    guard let extracted = extract(from: userInfo) else {
      NSLog("[NPD.push] captured tap but no URL in payload")
      return
    }
    NSLog("[NPD.push] captured tap url via '%@' → %@", extracted.source, extracted.url)
    queue.sync { _pending = extracted.url }
    let store = UserDefaults.standard
    store.set(extracted.url, forKey: storageKey)
    store.synchronize()
  }

  /// Consume the pending URL. Clears both the in-memory slot and the
  /// UserDefaults key so a stale tap never replays on a later launch.
  static func take() -> String? {
    let native: String? = queue.sync {
      let v = _pending
      _pending = nil
      return v
    }
    let store = UserDefaults.standard
    let stored = store.string(forKey: storageKey)
    if stored != nil {
      store.removeObject(forKey: storageKey)
      store.synchronize()
    }
    return native ?? stored
  }

  // MARK: - Extraction

  private struct Extracted { let url: String; let source: String }

  private static let urlKeys: [String] = [
    "click_url", "clickUrl",
    "target", "url", "deep_link", "link", "deeplink", "destination",
  ]

  private static let ignoredKeyPrefixes: [String] = [
    "google.", "gcm.", "aps", "fcm_", "com.google.",
  ]

  private static func extract(from userInfo: [AnyHashable: Any]) -> Extracted? {
    if let hit = scan(userInfo) { return hit }
    return httpScan(userInfo)
  }

  private static func scan(
    _ dict: [AnyHashable: Any],
    keyPath: String = ""
  ) -> Extracted? {
    for key in urlKeys {
      if let raw = dict[key] as? String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          let source = keyPath.isEmpty ? key : "\(keyPath).\(key)"
          return Extracted(url: trimmed, source: source)
        }
      }
    }
    for (key, value) in dict {
      let keyText = "\(key)"
      let nextPath = keyPath.isEmpty ? keyText : "\(keyPath).\(keyText)"
      if let nested = value as? [AnyHashable: Any],
         let hit = scan(nested, keyPath: nextPath) {
        return hit
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
  ) -> Extracted? {
    if let map = value as? [AnyHashable: Any] {
      for (key, nested) in map {
        let keyText = "\(key)"
        let path = keyPath.isEmpty ? keyText : "\(keyPath).\(keyText)"
        if ignoredKeyPrefixes.contains(where: { path.hasPrefix($0) }) { continue }
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
        return Extracted(url: trimmed, source: keyPath.isEmpty ? "<root>" : keyPath)
      }
    }
    return nil
  }

  private static func parseBlob(_ blob: String, keyPath: String) -> Extracted? {
    let trimmed = blob.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data)
            as? [AnyHashable: Any]
    else { return nil }
    return scan(json, keyPath: keyPath)
  }
}
