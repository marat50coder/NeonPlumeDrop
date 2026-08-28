import UserNotifications

/// Attaches a remote image and returns the banner immediately.
/// Firebase is not linked here — loading it in the extension stalls
/// delivery (~30s) and iOS drops a second simultaneous push.
///
/// Each `didReceive` captures its own `contentHandler`. The extension
/// process is reused; an instance-level "already delivered" flag would
/// swallow every push after the first.
final class NotificationService: UNNotificationServiceExtension {
  private var deliver: ((UNNotificationContent) -> Void)?
  private var draft: UNMutableNotificationContent?
  private var transfer: URLSessionDownloadTask?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    transfer?.cancel()
    transfer = nil

    guard let draft = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    self.draft = draft

    let once = OnceGate(contentHandler)
    deliver = { once.fire($0) }

    guard let picture = Self.pictureURL(from: request.content.userInfo) else {
      once.fire(draft)
      return
    }

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 2.4
    config.timeoutIntervalForResource = 2.8
    config.waitsForConnectivity = false
    let session = URLSession(configuration: config)
    let task = session.downloadTask(with: picture) { location, response, _ in
      if let location {
        Self.pinPicture(location, response: response, source: picture, onto: draft)
      }
      once.fire(draft)
    }
    transfer = task
    task.resume()

    DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
      task.cancel()
      once.fire(draft)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    transfer?.cancel()
    if let deliver, let draft {
      deliver(draft)
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
