import UserNotifications

/// Notification Service Extension.
///
/// Matches the proven Bolt-of-Aether / FeatherfieldFrenzy pattern:
/// deliberately does NOT link Firebase Messaging here. Linking Firebase
/// in the NSE produces `Redefinition of module 'Firebase'` when the
/// Runner target pulls firebase-ios-sdk via SPM, and the "populate…"
/// call is not required for tap URLs to reach Dart — cold-start taps
/// arrive via `SceneDelegate.notificationResponse` and warm taps via
/// `FirebaseMessaging.onMessageOpenedApp`, both entirely independent
/// of what the NSE does.
///
/// This extension only enriches the banner with remote media. Each
/// `didReceive` keeps its own state so two pushes handled on the same
/// extension instance never clobber each other.
final class NotificationService: UNNotificationServiceExtension {
  private var pending: [ObjectIdentifier: Pending] = [:]

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    let key = ObjectIdentifier(request)
    Self.log("didReceive id=\(request.identifier) collapse=\(request.content.userInfo["apns-collapse-id"] ?? "-")")

    guard
      let draft = request.content.mutableCopy() as? UNMutableNotificationContent
    else {
      Self.log("mutableCopy failed — delivering original")
      contentHandler(request.content)
      return
    }

    let once = OnceGate(contentHandler)
    let record = Pending(once: once, draft: draft, task: nil)
    pending[key] = record

    guard let picture = Self.pictureURL(from: request.content.userInfo) else {
      Self.log("no picture url — delivering plain banner id=\(request.identifier)")
      once.fire(draft)
      pending.removeValue(forKey: key)
      return
    }

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 2.4
    config.timeoutIntervalForResource = 2.8
    config.waitsForConnectivity = false
    let session = URLSession(configuration: config)
    let task = session.downloadTask(with: picture) { [weak self] location, response, error in
      if let error {
        Self.log("picture download failed: \(error.localizedDescription)")
      } else if let location {
        Self.pinPicture(location, response: response, source: picture, onto: draft)
        Self.log("picture attached id=\(request.identifier)")
      }
      once.fire(draft)
      self?.pending.removeValue(forKey: key)
    }
    record.task = task
    task.resume()

    // Per-request 3.1s ceiling: iOS gives ~30s but we prefer to hand
    // the banner over fast even if the CDN is slow. Never touches
    // another push's state — everything is captured locally.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) { [weak self] in
      task.cancel()
      once.fire(draft)
      self?.pending.removeValue(forKey: key)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    Self.log("timeWillExpire — flushing \(pending.count) pending push(es)")
    for record in pending.values {
      record.task?.cancel()
      record.once.fire(record.draft)
    }
    pending.removeAll()
  }

  private final class Pending {
    let once: OnceGate
    let draft: UNMutableNotificationContent
    var task: URLSessionDownloadTask?

    init(
      once: OnceGate,
      draft: UNMutableNotificationContent,
      task: URLSessionDownloadTask?
    ) {
      self.once = once
      self.draft = draft
      self.task = task
    }
  }

  private static func pictureURL(from payload: [AnyHashable: Any]) -> URL? {
    let labels = ["image_url", "imageUrl", "image", "media-url", "attachment-url"]
    if let found = firstLink(in: payload, labels: labels) {
      return found
    }
    if let options = payload["fcm_options"] as? [AnyHashable: Any],
       let found = firstLink(in: options, labels: ["image"]) {
      return found
    }
    if let nested = payload["data"] as? [AnyHashable: Any],
       let found = firstLink(in: nested, labels: labels) {
      return found
    }
    return nil
  }

  private static func firstLink(
    in bag: [AnyHashable: Any],
    labels: [String]
  ) -> URL? {
    for label in labels {
      guard let raw = bag[label] as? String else { continue }
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
      else { continue }
      return url
    }
    return nil
  }

  private static func pinPicture(
    _ location: URL,
    response: URLResponse?,
    source: URL,
    onto content: UNMutableNotificationContent
  ) {
    let ext = suffix(for: source, response: response)
    let dest = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(ext)
    do {
      try FileManager.default.moveItem(at: location, to: dest)
      content.attachments = [
        try UNNotificationAttachment(identifier: "npd.orbit.media", url: dest),
      ]
    } catch {}
  }

  private static func suffix(for url: URL, response: URLResponse?) -> String {
    let path = url.pathExtension.lowercased()
    if path == "png" || path == "jpg" || path == "jpeg" || path == "gif" {
      return path == "jpeg" ? "jpg" : path
    }
    let mime = ((response as? HTTPURLResponse)?
      .value(forHTTPHeaderField: "Content-Type") ?? response?.mimeType ?? "")
      .split(separator: ";").first?
      .trimmingCharacters(in: .whitespaces)
      .lowercased() ?? ""
    if mime.contains("png") { return "png" }
    if mime.contains("gif") { return "gif" }
    return "jpg"
  }

  private static func log(_ message: String) {
    NSLog("[NPD.nse] %@", message)
  }
}

/// Fires the OS content handler exactly once for a single `didReceive`.
private final class OnceGate {
  private let handler: (UNNotificationContent) -> Void
  private var done = false
  private let lock = NSLock()

  init(_ handler: @escaping (UNNotificationContent) -> Void) {
    self.handler = handler
  }

  func fire(_ content: UNNotificationContent) {
    lock.lock()
    defer { lock.unlock() }
    guard !done else { return }
    done = true
    handler(content)
  }
}
