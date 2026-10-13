import AppKit

/// جلسة Claude Code شغالة في التيرمنال، بتتحدّث من الـ hooks
struct ClaudeSession: Identifiable, Codable, Equatable {
    enum State: String, Codable { case idle, working, waiting, done, failed }

    var id: String
    var cwd: String
    var state: State
    var prompt: String?
    var tool: String?
    var message: String?
    var pid: Int32
    var terminal: String?
    var updated: Date
    var summary: String?

    var project: String { (cwd as NSString).lastPathComponent }

    var detail: String {
        switch state {
        case .waiting: return message ?? "مستنيك توافق"
        case .working: return tool ?? prompt ?? "بيفكّر…"
        case .done: return summary ?? prompt.map { "خلص: \($0)" } ?? "خلص ✓"
        case .idle: return "جاهز"
        case .failed: return message ?? "وقف بسبب error"
        }
    }
}

/// سؤال من أداة AskUserQuestion: اختيار واحد أو أكتر
struct AskQuestion: Equatable {
    struct Option: Equatable { let label: String; let detail: String }
    let text: String
    let header: String
    let multi: Bool
    let options: [Option]
}

/// كلود مستني موافقتك على أداة، والـ hook واقف مستني الرد
struct PermissionAsk: Identifiable, Equatable {
    let id: String          // اسم ملف الرد
    let sessionId: String
    let project: String
    let tool: String
    let detail: String
    let hookPid: Int32
    var questions: [AskQuestion] = []   // مش فاضية = كلود بيسألك مش بيستأذن
    var input = Data()                  // الـ tool_input الأصلي، بنرجّعه ومعاه الإجابات
}

final class ClaudeStore: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var asks: [PermissionAsk] = []

    /// بيتنادي لما جلسة تبقى مستنياك أو تخلص
    var onTransition: ((ClaudeSession) -> Void)?
    /// أداة فشلت (false) أو كلود وقف بسبب error (true)
    var onError: ((ClaudeSession, Bool) -> Void)?

    static let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".notchrobot")
    private let inbox = base.appendingPathComponent("inbox")
    private let stateFile = base.appendingPathComponent("sessions.json")
    private let replies = base.appendingPathComponent("replies")
    private var lastPrune = Date.distantPast

    init() {
        defer { checkHooks() }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: stateFile),
           let s = try? JSONDecoder().decode([ClaudeSession].self, from: d) {
            sessions = s.filter(isAlive)
        }
    }

    private var watcher: DispatchSourceFileSystemObject?

    /// بنصحى بس لما الـ hook يحط ملف في الـ inbox بدل ما نقرا الفولدر كل شوية
    func watch() {
        watcher?.cancel()
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let fd = open(inbox.path, O_EVTONLY)
        guard fd >= 0 else { watcher = nil; return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
                                                            queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            // الفولدر نفسه اتمسح أو اتنقل: نراقب الجديد
            if !src.data.isDisjoint(with: [.delete, .rename]) { self.watch() }
            self.poll()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    var waiting: [ClaudeSession] { sessions.filter { $0.state == .waiting } }
    var working: [ClaudeSession] { sessions.filter { $0.state == .working } }
    var recentlyDone: Bool {
        sessions.contains { $0.state == .done && Date().timeIntervalSince($0.updated) < 20 }
    }

    @Published private(set) var hooksInstalled = false

    private func checkHooks() {
        let p = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
        let ok = (try? String(contentsOf: p, encoding: .utf8))?.contains(".notchrobot/hook.sh") ?? false
        if ok != hooksInstalled { hooksInstalled = ok }
    }

    func poll() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: keys) else { return }
        func mtime(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let jsons: [URL] = files.filter { $0.pathExtension == "json" }
        let events: [(URL, Date)] = jsons.map { ($0, mtime($0)) }.sorted { a, b in
            a.1 == b.1 ? a.0.lastPathComponent < b.0.lastPathComponent : a.1 < b.1
        }

        var dict = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var changed = false
        for (url, mtime) in events {
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let nl = data.firstIndex(of: 0x0A) else { continue }
            let header = String(decoding: data[..<nl], as: UTF8.self).split(separator: " ")
            let pid = Int32(header.first ?? "") ?? 0
            let terminal = header.count > 1 && header[1] != "-" ? String(header[1]) : nil
            let hookPid = header.count > 2 ? Int32(header[2]) ?? 0 : 0
            guard let j = try? JSONSerialization.jsonObject(with: data[(nl + 1)...]) as? [String: Any] else { continue }
            let fresh = Date().timeIntervalSince(mtime) < 10
            if j["hook_event_name"] as? String == "PermissionRequest", hookPid > 1 {
                addAsk(j, id: url.deletingPathExtension().lastPathComponent, hookPid: hookPid, dict: dict)
            }
            if apply(j, pid: pid, terminal: terminal, fresh: fresh, to: &dict) { changed = true }
        }

        if Date().timeIntervalSince(lastPrune) > 4.5 {
            lastPrune = Date()
            checkHooks()
            let before = dict.count
            dict = dict.filter { isAlive($0.value) }
            if dict.count != before { changed = true }
            // الـ hook خلص (اتجاوب في التيرمنال، اتلغى، أو الوقت خلص)
            let alive = asks.filter { kill($0.hookPid, 0) == 0 || errno != ESRCH }
            if alive != asks { asks = alive }
        }

        if changed {
            sessions = dict.values.sorted { $0.updated > $1.updated }
            save()
        }
    }

    private func apply(_ j: [String: Any], pid: Int32, terminal: String?, fresh: Bool,
                       to dict: inout [String: ClaudeSession]) -> Bool {
        guard let sid = j["session_id"] as? String else { return false }
        let event = j["hook_event_name"] as? String ?? ""
        if event == "SessionEnd" {
            asks.removeAll { $0.sessionId == sid }
            return dict.removeValue(forKey: sid) != nil
        }
        // كلود كمّل → الطلب اتجاوب من التيرمنال
        if ["PostToolUse", "PostToolUseFailure", "Stop", "StopFailure", "UserPromptSubmit"].contains(event) {
            asks.removeAll { $0.sessionId == sid }
        }

        let now = Date()
        var s = dict[sid] ?? ClaudeSession(id: sid, cwd: "", state: .idle, pid: pid, terminal: nil, updated: now)
        if let cwd = j["cwd"] as? String { s.cwd = cwd }
        if pid > 1 { s.pid = pid }
        if let t = terminal, !t.isEmpty { s.terminal = t }
        let old = s.state

        switch event {
        case "SessionStart":
            s.state = .idle
        case "UserPromptSubmit":
            s.state = .working
            s.prompt = short(j["prompt"] as? String, 60)
            s.tool = nil
            s.message = nil
        case "PreToolUse":
            s.state = .working
            s.message = nil
            s.tool = describe(j["tool_name"] as? String, j["tool_input"] as? [String: Any])
        case "PostToolUse":
            s.state = .working
            s.message = nil
        case "Notification":
            let type = j["notification_type"] as? String
            let msg = j["message"] as? String ?? ""
            // تنبيه "مستني رد" بعد ما يخلص مش محتاج نعمل منه حاجة
            if type == "idle_prompt" || msg.localizedCaseInsensitiveContains("waiting for your input") { return false }
            // الطلب ظاهر أصلاً ككارت في النوتش
            if asks.contains(where: { $0.sessionId == sid }) { return false }
            s.state = .waiting
            s.message = short(msg, 70)
        case "PermissionRequest":
            s.state = .waiting
            s.message = "عايز يستخدم \(j["tool_name"] as? String ?? "أداة")"
        case "PostToolUseFailure":
            s.state = .working
            s.message = nil
            if fresh, (j["is_interrupt"] as? Bool) != true {
                let snapshot = s
                DispatchQueue.main.async { self.onError?(snapshot, false) }
            }
        case "StopFailure":
            s.state = .failed
            s.tool = nil
            s.message = short(j["error_details"] as? String ?? j["error"] as? String, 90)
            if fresh {
                let snapshot = s
                DispatchQueue.main.async { self.onError?(snapshot, true) }
            }
        case "Stop":
            s.state = .done
            s.tool = nil
            s.summary = summarize(j["last_assistant_message"] as? String)
        default:
            return false
        }
        s.updated = now
        dict[sid] = s
        if fresh, old != s.state, s.state == .waiting || s.state == .done {
            let snapshot = s
            DispatchQueue.main.async { self.onTransition?(snapshot) }
        }
        return true
    }

    private func addAsk(_ j: [String: Any], id: String, hookPid: Int32, dict: [String: ClaudeSession]) {
        guard let sid = j["session_id"] as? String, !asks.contains(where: { $0.id == id }) else { return }
        let tool = j["tool_name"] as? String ?? "أداة"
        let input = j["tool_input"] as? [String: Any] ?? [:]
        let detail: String
        switch tool {
        case "Bash": detail = input["command"] as? String ?? ""
        case "Edit", "Write", "MultiEdit", "Read", "NotebookEdit": detail = input["file_path"] as? String ?? ""
        case "WebFetch": detail = input["url"] as? String ?? ""
        default:
            let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
            detail = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        let cwd = j["cwd"] as? String ?? dict[sid]?.cwd ?? ""
        var ask = PermissionAsk(id: id, sessionId: sid, project: (cwd as NSString).lastPathComponent,
                                tool: tool, detail: String(detail.prefix(400)), hookPid: hookPid)
        if tool == "AskUserQuestion" {
            ask.questions = (input["questions"] as? [[String: Any]] ?? []).compactMap { q in
                guard let text = q["question"] as? String else { return nil }
                let opts = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> AskQuestion.Option? in
                    guard let l = o["label"] as? String else { return nil }
                    return .init(label: l, detail: o["description"] as? String ?? "")
                }
                guard !opts.isEmpty else { return nil }
                return AskQuestion(text: text, header: q["header"] as? String ?? "",
                                   multi: q["multiSelect"] as? Bool ?? false, options: opts)
            }
            ask.input = (try? JSONSerialization.data(withJSONObject: input)) ?? Data()
        }
        asks.append(ask)
    }

    /// answers: نص السؤال → الاختيار (أو الاختيارات مفصولة بـ ", ")
    enum Answer: Equatable { case allow, deny, terminal, answers([String: String]) }

    /// يكتب ردك للـ hook اللي مستنيه — بيتنادي بس من زراير الكارت
    func answer(_ ask: PermissionAsk, _ a: Answer) {
        let json: String
        switch a {
        case .allow:
            json = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        case .deny:
            json = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"The user denied this from the NotchRobot notch."}}}"#
        case .terminal:
            json = ""   // من غير قرار → كلود يسأل في التيرمنال عادي
        case .answers(let answers):
            var input = (try? JSONSerialization.jsonObject(with: ask.input)) as? [String: Any] ?? [:]
            input["answers"] = answers
            let out: [String: Any] = ["hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": "allow", "updatedInput": input],
            ]]
            json = (try? JSONSerialization.data(withJSONObject: out)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: replies, withIntermediateDirectories: true)
        let tmp = replies.appendingPathComponent(ask.id + ".tmp")
        try? json.write(to: tmp, atomically: false, encoding: .utf8)
        try? fm.moveItem(at: tmp, to: replies.appendingPathComponent(ask.id + ".json"))
        asks.removeAll { $0.id == ask.id }
        if let i = sessions.firstIndex(where: { $0.id == ask.sessionId }) {
            sessions[i].state = .working
            sessions[i].message = nil
        }
        if a == .terminal, let s = sessions.first(where: { $0.id == ask.sessionId }) { focus(s) }
    }

    /// أول كام سطر من آخر رد لكلود من غير رموز الماركداون
    private func summarize(_ text: String?) -> String? {
        guard var t = text else { return nil }
        for sym in ["**", "__", "`", "#", "> ", "|"] { t = t.replacingOccurrences(of: sym, with: "") }
        let lines = t.split(separator: "\n")
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                for bullet in ["- ", "* ", "• "] where l.hasPrefix(bullet) { l.removeFirst(bullet.count) }
                return l
            }
            .filter { !$0.isEmpty && !$0.allSatisfy { "-=:".contains($0) } }
        return short(lines.prefix(3).joined(separator: " "), 140)
    }

    private func describe(_ name: String?, _ input: [String: Any]?) -> String? {
        guard let name else { return nil }
        let i = input ?? [:]
        let arg: String?
        switch name {
        case "Bash": arg = i["command"] as? String
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
            arg = (i["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
        case "Grep", "Glob": arg = i["pattern"] as? String
        case "WebFetch": arg = i["url"] as? String
        case "WebSearch": arg = i["query"] as? String
        case "Agent", "Task": arg = i["description"] as? String
        default: arg = nil
        }
        guard let a = short(arg, 40) else { return name }
        return "\(name) · \(a)"
    }

    private func short(_ s: String?, _ n: Int) -> String? {
        guard let s else { return nil }
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if one.isEmpty { return nil }
        return one.count > n ? String(one.prefix(n)) + "…" : one
    }

    private func isAlive(_ s: ClaudeSession) -> Bool {
        if Date().timeIntervalSince(s.updated) > 12 * 3600 { return false }
        if s.pid > 1, kill(s.pid, 0) != 0, errno == ESRCH { return false }
        return true
    }

    private func save() {
        if let d = try? JSONEncoder().encode(sessions) { try? d.write(to: stateFile, options: .atomic) }
    }

    /// للـ --snapshot: جلسات ثابتة بدل الجلسات الحقيقية اللي على الجهاز
    func preview(_ s: [ClaudeSession]) { sessions = s }

    func remove(_ s: ClaudeSession) {
        sessions.removeAll { $0.id == s.id }
        save()
    }

    /// يفتح التيرمنال على التاب اللي فيه الجلسة بالظبط (Terminal و iTerm)، وإلا يجيب التطبيق قدّام
    func focus(_ s: ClaudeSession) {
        let bundle = s.terminal ?? "com.apple.Terminal"
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        guard let app else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        guard let tty = Self.tty(of: s.pid), let script = Self.focusScript(bundle: bundle, tty: tty) else {
            app.activate()
            return
        }
        focusQueue.async {
            var err: NSDictionary?
            let found = NSAppleScript(source: script)?.executeAndReturnError(&err).booleanValue ?? false
            DispatchQueue.main.async { if !found { app.activate() } }
        }
    }

    private let focusQueue = DispatchQueue(label: "notchrobot.focus")

    /// /dev/ttysNNN بتاع process
    static func tty(of pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.e_tdev != UInt32.max, let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR)
        else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func focusScript(bundle: String, tty: String) -> String? {
        switch bundle {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set miniaturized of w to false
                    set index of w to 1
                    activate
                    return true
                  end if
                end repeat
              end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with ss in sessions of t
                    if tty of ss is "\(tty)" then
                      select w
                      select t
                      select ss
                      activate
                      return true
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return false
            """
        default: return nil
        }
    }
}
