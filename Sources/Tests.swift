import Foundation

func runTests() {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ name: String) {
        guard value() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        checks += 1
    }
    func event(_ type: String, _ payload: [String: Any]) -> Activity? {
        let data = try! JSONSerialization.data(withJSONObject: ["type": type, "timestamp": "2026-09-22T11:00:00.000Z", "payload": payload])
        return EventParser.parse(data)
    }
    check(event("event_msg", ["type": "task_started"])?.phase == .thinking, "task start")
    check(event("event_msg", ["type": "task_complete"])?.phase == .complete, "task completion")
    check(event("event_msg", ["type": "turn_aborted"])?.phase == .waiting, "cancelled task")
    check(event("response_item", ["type": "message", "role": "user"]) == nil, "ignore user content")
    check(event("response_item", ["type": "message", "role": "assistant", "phase": "final_answer"])?.phase == .answering, "assistant answer")
    check(event("response_item", ["type": "reasoning"])?.phase == .thinking, "reasoning metadata")
    check(EventParser.parse(Data("not json".utf8)) == nil, "malformed input")
    check(EventParser.classify(name: "exec_command", input: #"{"cmd":"cat /private/project/app.tsx"}"#).0 == .reading, "structured file read")
    check(EventParser.classify(name: "exec_command", input: #"{"cmd":"xcrun swiftc Sources/main.swift"}"#).0 == .building, "build command")
    check(EventParser.classify(name: "exec", input: #"text(await tools.exec_command({cmd: "sed -n '1,20p' src/main.swift"}));"#).0 == .reading, "wrapped tool call")
    check(EventParser.classify(name: "exec", input: "text(await tools.apply_patch('*** Add File: main.swift'))").0 == .building, "wrapped patch")
    check(EventParser.classify(name: "request_user_input_async", input: "{}").0 == .waiting, "user question")
    check(EventParser.filename(in: "/secret/client/project/app.tsx") == "app.tsx", "only basename displayed")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("events.jsonl")
    try! Data("first\nsec".utf8).write(to: file)
    let reader = TailReader()
    check(reader.read(file).map { String(decoding: $0, as: UTF8.self) } == ["first"], "hold partial record")
    let handle = try! FileHandle(forWritingTo: file); try! handle.seekToEnd(); try! handle.write(contentsOf: Data("ond\n".utf8)); try! handle.close()
    check(reader.read(file).map { String(decoding: $0, as: UTF8.self) } == ["second"], "append without duplication")
    check(reader.read(file).isEmpty, "unchanged file")
    try! Data("new\n".utf8).write(to: file)
    check(reader.read(file).map { String(decoding: $0, as: UTF8.self) } == ["new"], "file replacement / truncation")
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let started = try! JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": iso.string(from: Date()), "payload": ["type": "task_started"]])
    try! (started + Data([10])).write(to: file)
    var observed: Phase?
    let monitor = ActivityMonitor(root: dir)
    monitor.onActivity = { observed = $0.phase }
    monitor.start()
    RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    check(observed == .thinking, "monitor discovers and dispatches an actual JSONL file")
    let finished = try! JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": iso.string(from: Date()), "payload": ["type": "task_complete"]])
    let append = try! FileHandle(forWritingTo: file); try! append.seekToEnd(); try! append.write(contentsOf: finished + Data([10])); try! append.close()
    RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    monitor.stop()
    check(observed == .complete, "monitor delivers completion from an appended event")
    print("Passed \(checks) checks: event classification, privacy, incremental reads, rotation, and live monitoring.")
}
