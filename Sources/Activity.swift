import Foundation

enum Phase: String, CaseIterable {
    case idle, reading, thinking, building, answering, complete, waiting
    var title: String {
        switch self {
        case .idle: return "Codex is ready"
        case .reading: return "Reading files"
        case .thinking: return "Thinking"
        case .building: return "Building"
        case .answering: return "Answering"
        case .complete: return "All done"
        case .waiting: return "Waiting"
        }
    }
    var active: Bool { [.reading, .thinking, .building, .answering].contains(self) }
}

struct Activity {
    var phase: Phase
    var detail: String
    var date: Date = Date()
    var session: String = ""
}

/// Reads event metadata only. No transcript content is displayed, saved, or sent anywhere.
enum EventParser {
    static func parse(_ data: Data) -> Activity? {
        guard let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = record["payload"] as? [String: Any] else { return nil }
        let timestamp = record["timestamp"] as? String ?? ""
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) ?? Date()
        func activity(_ phase: Phase, _ detail: String) -> Activity { Activity(phase: phase, detail: detail, date: date) }
        let type = p["type"] as? String ?? ""
        if record["type"] as? String == "event_msg" {
            switch type {
            case "task_started", "turn_started": return activity(.thinking, "A new idea is taking shape")
            case "task_complete", "task_completed", "turn_completed": return activity(.complete, "Your response is ready in Codex")
            case "turn_aborted", "task_aborted": return activity(.waiting, "Task stopped")
            case "agent_reasoning": return activity(.thinking, "Working through the details")
            default: return nil
            }
        }
        guard record["type"] as? String == "response_item" else { return nil }
        switch type {
        case "reasoning": return activity(.thinking, "Working through the details")
        case "message":
            guard p["role"] as? String == "assistant" else { return nil }
            return activity(.answering, p["phase"] as? String == "final_answer" ? "Finishing your response" : "Sharing an update in Codex")
        case "function_call", "custom_tool_call":
            let name = p["name"] as? String ?? "tool"
            let arguments = (p["arguments"] as? String ?? p["input"] as? String ?? "")
            let result = classify(name: name, input: arguments)
            return activity(result.0, result.1)
        default: return nil
        }
    }

    static func classify(name: String, input: String) -> (Phase, String) {
        let n = name.lowercased()
        var command = input
        // Extract actual shell commands from structured calls, rather than classifying arbitrary output.
        if let data = input.data(using: .utf8), let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            command = args["cmd"] as? String ?? args["command"] as? String ?? ""
        } else if n == "exec", let range = input.range(of: #"(?:cmd|command)\s*:\s*\"((?:\\.|[^\"\\])*)\""#, options: .regularExpression) {
            command = String(input[range])
        }
        let c = command.lowercased()
        if n.contains("request_user_input") || c.contains("tools.request_user_input") { return (.waiting, "Codex has a question for you") }
        if n.contains("apply_patch") || (n == "exec" && input.contains("tools.apply_patch")) { return (.building, filename(in: input).map { "Editing \($0)" } ?? "Shaping your prototype") }
        if n.contains("search") || n.contains("read") || n.contains("fetch") || n.contains("view_image") { return (.reading, filename(in: input).map { "Read \($0)" } ?? "Gathering context") }
        if n.contains("exec") || n.contains("command") {
            if c.range(of: #"\b(swiftc|swift build|xcodebuild|npm run|pnpm|vite|cargo|make|pytest|swift test|mkdir|touch)\b|cat\s*>|write_text|writeFile"#, options: .regularExpression) != nil {
                return (.building, filename(in: command).map { "Working on \($0)" } ?? "Bringing the pieces together")
            }
            if c.range(of: #"\b(cat|sed|rg|head|tail|ls|find|read_text)\b"#, options: .regularExpression) != nil {
                return (.reading, filename(in: command).map { "Read \($0)" } ?? "Exploring your files")
            }
            return (.thinking, "Working with tools")
        }
        if n.contains("write") || n.contains("create") || n.contains("edit") { return (.building, "Making changes") }
        return (.thinking, "Working with tools")
    }

    static func filename(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_@+.-]+\.(?:tsx|jsx|ts|js|swift|py|rs|go|html|css|json|md|toml|yaml|yml)\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range].prefix(56))
    }
}

/// Incremental bounded tail reader. Keeps partial UTF-8 / JSON lines until the next append.
final class TailReader {
    var offset: UInt64 = 0
    var pending = Data()
    var identity: UInt64?
    func read(_ url: URL) -> [Data] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let inode = attrs[.systemFileNumber] as? UInt64
        if size < offset || (identity != nil && identity != inode) { offset = 0; pending.removeAll() }
        identity = inode
        var clipped = false
        if size - offset > 2_097_152 { offset = size - 2_097_152; pending.removeAll(); clipped = true }
        do {
            try handle.seek(toOffset: offset)
            let bytes = try handle.read(upToCount: 2_097_152) ?? Data()
            offset += UInt64(bytes.count)
            pending.append(bytes)
        } catch { return [] }
        var result: [Data] = []
        while let end = pending.firstIndex(of: 10) {
            let line = Data(pending[..<end])
            pending.removeSubrange(...end)
            if clipped { clipped = false } else if !line.isEmpty { result.append(line) }
        }
        if pending.count > 2_097_152 { pending.removeAll() }
        return result
    }
}

final class ActivityMonitor {
    var onActivity: ((Activity) -> Void)?
    var onConnection: ((String) -> Void)?
    var root: URL
    private var readers: [URL: TailReader] = [:]
    private var candidates: [URL] = []
    private var lastScan = Date.distantPast
    private var latest = Date().addingTimeInterval(-120)
    private let queue = DispatchQueue(label: "local.codexnotch.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?

    init(root: URL) { self.root = root }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.75)
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    deinit { stop() }
    private func poll() {
        if Date().timeIntervalSince(lastScan) > 3 {
            lastScan = Date()
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
                DispatchQueue.main.async { [weak self] in self?.onConnection?("Choose your Codex sessions folder") }; return
            }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
            var files: [(URL, Date)] = []
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if Date().timeIntervalSince(date) < 86_400 { files.append((url, date)) }
            }
            candidates = files.sorted { $0.1 > $1.1 }.prefix(16).map(\.0)
            readers = readers.filter { candidates.contains($0.key) }
            DispatchQueue.main.async { [weak self] in self?.onConnection?("Following local Codex activity") }
        }
        var events: [Activity] = []
        for url in candidates {
            let reader = readers[url] ?? TailReader(); readers[url] = reader
            for line in reader.read(url) {
                if var event = EventParser.parse(line), event.date > latest {
                    event.session = url.lastPathComponent
                    events.append(event)
                }
            }
        }
        // Follow the most recently active task. No attempt is made to infer the focused UI task.
        if let newest = events.max(by: { $0.date < $1.date }) {
            latest = newest.date
            DispatchQueue.main.async { [weak self] in self?.onActivity?(newest) }
        }
    }
}
