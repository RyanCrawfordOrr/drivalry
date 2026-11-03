import Foundation

/// Append-only JSON Lines spool (docs/08 §5).
///
/// `<Application Support>/tracking/spool.jsonl`, one JSON object per line, UTF-8.
/// Rotated at 8 MB into `spool.1.jsonl`; anything older than two files is dropped.
/// `drain()` returns every line of both files in order and truncates them.
/// All file access runs on one serial queue, so callers may use it from any thread.
final class Spool {
  static let rotateBytes = 8 * 1024 * 1024

  private let queue = DispatchQueue(label: "app.drivalry.tracking.spool", qos: .utility)
  private let directory: URL
  private let currentURL: URL
  private let rotatedURL: URL
  private var cachedCount: Int = 0

  init() {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fm.temporaryDirectory
    directory = base.appendingPathComponent("tracking", isDirectory: true)
    currentURL = directory.appendingPathComponent("spool.jsonl")
    rotatedURL = directory.appendingPathComponent("spool.1.jsonl")
    queue.async { [self] in
      self.ensureDirectory()
      self.cachedCount = self.countLines(self.rotatedURL) + self.countLines(self.currentURL)
    }
  }

  /// Number of spooled events waiting to be drained (`State.spooledEvents`).
  var count: Int {
    return queue.sync { cachedCount }
  }

  /// Append one event. Invalid JSON (NaN, non-JSON types) is dropped rather than crashing.
  func append(_ event: [String: Any]) {
    queue.async { [self] in
      guard JSONSerialization.isValidJSONObject(event),
            var data = try? JSONSerialization.data(withJSONObject: event, options: [])
      else { return }
      data.append(0x0A)  // "\n"
      self.ensureDirectory()
      self.rotateIfNeeded(adding: data.count)
      if self.appendData(data, to: self.currentURL) {
        self.cachedCount += 1
      }
    }
  }

  /// Parse both files in order, delete them, and hand the events back on `completion`
  /// (called on the main queue).
  func drain(completion: @escaping ([[String: Any]]) -> Void) {
    queue.async { [self] in
      var events: [[String: Any]] = []
      events.append(contentsOf: self.readEvents(self.rotatedURL))
      events.append(contentsOf: self.readEvents(self.currentURL))
      let fm = FileManager.default
      try? fm.removeItem(at: self.rotatedURL)
      try? fm.removeItem(at: self.currentURL)
      self.cachedCount = 0
      DispatchQueue.main.async { completion(events) }
    }
  }

  // MARK: - File helpers (spool queue only)

  private func ensureDirectory() {
    let fm = FileManager.default
    if fm.fileExists(atPath: directory.path) { return }
    do {
      try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      var url = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
    } catch {
      // Nothing sensible to do; appends will fail quietly and events are lost.
    }
  }

  private func fileSize(_ url: URL) -> Int {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs?[.size] as? NSNumber)?.intValue ?? 0
  }

  private func rotateIfNeeded(adding bytes: Int) {
    let size = fileSize(currentURL)
    if size == 0 || size + bytes <= Spool.rotateBytes { return }
    let fm = FileManager.default
    let droppedLines = countLines(rotatedURL)
    try? fm.removeItem(at: rotatedURL)
    do {
      try fm.moveItem(at: currentURL, to: rotatedURL)
      cachedCount = max(0, cachedCount - droppedLines)
    } catch {
      // Could not rotate: keep appending to the current file rather than lose data.
    }
  }

  private func appendData(_ data: Data, to url: URL) -> Bool {
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
      return fm.createFile(atPath: url.path, contents: data, attributes: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return false }
    defer { try? handle.close() }
    do {
      _ = try handle.seekToEnd()
      try handle.write(contentsOf: data)
      return true
    } catch {
      return false
    }
  }

  private func countLines(_ url: URL) -> Int {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return 0 }
    var count = 0
    for byte in data where byte == 0x0A { count += 1 }
    // A last line without a trailing newline still counts.
    if let last = data.last, last != 0x0A { count += 1 }
    return count
  }

  private func readEvents(_ url: URL) -> [[String: Any]] {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
    var events: [[String: Any]] = []
    for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
      guard let object = try? JSONSerialization.jsonObject(with: Data(line), options: []),
            let map = object as? [String: Any]
      else { continue }  // a torn last line from a crash is skipped
      events.append(map)
    }
    return events
  }
}
