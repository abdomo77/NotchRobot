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
    /// قايمة مهام كلود (TaskCreate/TaskUpdate أو TodoWrite). optional عشان sessions.json القديم يتقري
    var tasks: [TaskItem]?

    struct TaskItem: Codable, Equatable {
        var id: String
        var title: String
        var status: String   // pending, in_progress, completed
    }

    var project: String { (cwd as NSString).lastPathComponent }

    /// (اللي خلص، الكل) — nil لو مفيش مهام أو كلها خلصت والجلسة مش شغالة
    var progress: (done: Int, total: Int)? {
        guard let t = tasks, !t.isEmpty else { return nil }
        let done = t.filter { $0.status == "completed" }.count
        if done == t.count, state != .working { return nil }
        return (done, t.count)
    }

    var activeTask: String? { tasks?.first { $0.status == "in_progress" }?.title }

    var detail: String {
        switch state {
        case .waiting: return message ?? tr("مستنيك توافق", "Waiting for you")
        case .working: return tool ?? prompt ?? tr("بيفكّر…", "Thinking…")
        case .done: return summary ?? prompt.map { tr("خلص: \($0)", "Done: \($0)") } ?? tr("خلص ✓", "Done ✓")
        case .idle: return tr("جاهز", "Ready")
        case .failed: return message ?? tr("وقف بسبب error", "Stopped on an error")
        }
    }
}

/// استهلاك الحساب في نافذة (5 ساعات أو أسبوع)، جاي من الـ status line بتاع Claude Code
struct UsageWindow: Equatable {
    let percent: Double
    let resetsAt: Date
}

/// تنبيه استهلاك: وصلت 90% في نافذة، أو النافذة رجعت بعد ما كنت وصلت
enum UsageAlert {
    enum Kind: String, CaseIterable { case fiveHour = "five_hour", week = "seven_day" }
    case high(Kind, percent: Int, resetsAt: Date)
    case reset(Kind)
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
    var key = ""                        // اسم الأداة + مدخلاتها، عشان نعرف نتيجتها لما توصل
}

final class ClaudeStore: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var asks: [PermissionAsk] = []
    @Published private(set) var usage5h: UsageWindow?
    @Published private(set) var usageWeek: UsageWindow?
    /// آخر مرة الـ status line كتب الأرقام (بيتحدّث بس وفيه جلسة شغالة)
    @Published private(set) var usageUpdated: Date?

    var onUsageAlert: ((UsageAlert) -> Void)?
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
            readUsage()
            let before = dict.count
            dict = dict.filter { isAlive($0.value) }
            if dict.count != before { changed = true }
        }
        // الـ hook خلص (اتجاوب في التيرمنال، اتلغى، أو الوقت خلص): ده الدليل الأكيد إن الطلب مبقاش مستني
        let alive = asks.filter { kill($0.hookPid, 0) == 0 || errno != ESRCH }
        if alive != asks { asks = alive }

        if changed {
            sessions = dict.values.sorted { $0.updated > $1.updated }
            save()
        }
    }

    private func apply(_ j: [String: Any], pid: Int32, terminal: String?, fresh: Bool,
                       to dict: inout [String: ClaudeSession]) -> Bool {
        guard let sid = j["session_id"] as? String else { return false }
        let event = j["hook_event_name"] as? String ?? ""
        if event == "PostToolUse", var s = dict[sid] {
            if trackTasks(j, in: &s) { dict[sid] = s }
        }
        if event == "SessionEnd" {
            asks.removeAll { $0.sessionId == sid }
            return dict.removeValue(forKey: sid) != nil
        }
        // نفس الأداة خلصت → الطلب اتجاوب من التيرمنال. أدوات تانية شغالة جنبها (أو subagents)
        // بتخلص وطلبك لسه مستني، فمنشيلش كروت الجلسة كلها
        if event == "PostToolUse" || event == "PostToolUseFailure" {
            let k = Self.key(j)
            asks.removeAll { $0.sessionId == sid && $0.key == k }
        }
        // الدور خلص أو كتبت رسالة جديدة → مفيش طلب مستني
        if ["Stop", "StopFailure", "UserPromptSubmit"].contains(event) {
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
            // /clear أو جلسة جديدة: القايمة القديمة خلاص
            if (j["source"] as? String) != "compact" { s.tasks = nil }
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
            s.message = tr("عايز يستخدم \(j["tool_name"] as? String ?? "أداة")", "Wants to use \(j["tool_name"] as? String ?? "a tool")")
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

    /// بيميّز استخدام أداة بعينه: اسمها + مدخلاتها مترتبة
    private static func key(_ j: [String: Any]) -> String {
        let input = j["tool_input"] as? [String: Any] ?? [:]
        let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        return (j["tool_name"] as? String ?? "") + ":" + (data.map { String(decoding: $0, as: UTF8.self) } ?? "")
    }

    /// بيحدّث قايمة المهام من نتيجة أداة؛ true لو اتغيّرت
    private func trackTasks(_ j: [String: Any], in s: inout ClaudeSession) -> Bool {
        let input = j["tool_input"] as? [String: Any] ?? [:]
        func str(_ v: Any?) -> String? { (v as? String) ?? (v as? Int).map(String.init) }
        var t = s.tasks ?? []
        switch j["tool_name"] as? String {
        case "TaskCreate":
            // الـ id بيتحدد في النتيجة؛ لو مش موجود بنعدّ (الأرقام بتمشي 1، 2، 3…)
            let res = j["tool_response"] as? [String: Any]
            let id = str((res?["task"] as? [String: Any])?["id"])
                ?? String((t.compactMap { Int($0.id) }.max() ?? 0) + 1)
            t.removeAll { $0.id == id }
            t.append(.init(id: id, title: input["subject"] as? String ?? "", status: "pending"))
        case "TaskUpdate":
            guard let id = str(input["taskId"]), let i = t.firstIndex(where: { $0.id == id }) else { return false }
            if let st = input["status"] as? String {
                if st == "deleted" { t.remove(at: i) } else { t[i].status = st }
            }
            if let sub = input["subject"] as? String, t.indices.contains(i), t[i].id == id { t[i].title = sub }
        case "TodoWrite":
            let todos = input["todos"] as? [[String: Any]] ?? []
            t = todos.enumerated().map { n, d in
                .init(id: String(n + 1), title: d["content"] as? String ?? "", status: d["status"] as? String ?? "pending")
            }
        default:
            return false
        }
        s.tasks = t.isEmpty ? nil : t
        return true
    }

    private var usageMtime: Date?

    /// ~/.notchrobot/usage.json بيكتبه statusline.sh؛ النوافذ اللي وقتها عدّى بنشيلها
    func readUsage() {
        let url = Self.base.appendingPathComponent("usage.json")
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let mtime, mtime != usageMtime {
            usageMtime = mtime
            if let d = try? Data(contentsOf: url),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let r = j["rate_limits"] as? [String: Any] {
                func window(_ k: String) -> UsageWindow? {
                    guard let w = r[k] as? [String: Any], let p = (w["used_percentage"] as? NSNumber)?.doubleValue,
                          let t = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
                    return UsageWindow(percent: p, resetsAt: Date(timeIntervalSince1970: t))
                }
                usage5h = window("five_hour")
                usageWeek = window("seven_day")
                usageUpdated = mtime
            }
        }
        let now = Date()
        if let w = usage5h, w.resetsAt < now { usage5h = nil }
        if let w = usageWeek, w.resetsAt < now { usageWeek = nil }
        checkUsageAlerts(now)
    }

    /// كل نافذة بتنبهك مرة لما توصل 90%، ومرة لما ترجع. بنحفظ وقت رجوعها في UserDefaults
    /// عشان لو التطبيق اتقفل واتفتح ميكررش التنبيه، ولسه يقولك لما ترجع
    private func checkUsageAlerts(_ now: Date) {
        let d = UserDefaults.standard
        for kind in UsageAlert.Kind.allCases {
            let key = "usageAlert." + kind.rawValue
            let warned = d.object(forKey: key) as? Double
            if let warned, warned < now.timeIntervalSince1970 {
                d.removeObject(forKey: key)
                onUsageAlert?(.reset(kind))
                continue
            }
            guard let w = kind == .fiveHour ? usage5h : usageWeek, w.percent >= 90 else { continue }
            let t = w.resetsAt.timeIntervalSince1970
            // نفس النافذة (وقت الرجوع ممكن يتحرك ثواني بين تحديث والتاني)
            if let warned, abs(warned - t) < 600 { continue }
            d.set(t, forKey: key)
            onUsageAlert?(.high(kind, percent: Int(w.percent.rounded()), resetsAt: w.resetsAt))
        }
    }

    private func addAsk(_ j: [String: Any], id: String, hookPid: Int32, dict: [String: ClaudeSession]) {
        guard let sid = j["session_id"] as? String, !asks.contains(where: { $0.id == id }) else { return }
        let tool = j["tool_name"] as? String ?? tr("أداة", "a tool")
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
        ask.key = Self.key(j)
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
    func preview(_ s: [ClaudeSession], asks a: [PermissionAsk] = [], usage: (Double, Double)? = nil) {
        sessions = s
        asks = a
        if let (h, w) = usage {
            usage5h = UsageWindow(percent: h, resetsAt: Date().addingTimeInterval(2 * 3600))
            usageWeek = UsageWindow(percent: w, resetsAt: Date().addingTimeInterval(4 * 86400))
            usageUpdated = Date()
        }
    }

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
