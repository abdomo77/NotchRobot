import AppKit

/// بيشوف آخر إصدار على GitHub، ولو أجدد من اللي عندك بينزّله ويركّبه مكانه.
/// مش بنستخدم Sparkle: محتاج framework ومفاتيح وملف appcast مستضاف، وإحنا عندنا NotchRobot.zip جاهز في كل release
final class UpdateStore: ObservableObject {
    static let repo = "abdomo77/NotchRobot"
    static let page = URL(string: "https://github.com/\(repo)/releases/latest")!
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    enum Phase: Equatable { case idle, downloading(Double), ready, failed(String) }

    /// أحدث إصدار لو أجدد من اللي عندك
    @Published private(set) var latest: String?
    @Published private(set) var phase: Phase = .idle
    /// ينزّل ويركّب لوحده من غير ما يسألك
    @Published var auto = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(auto, forKey: "autoUpdate") }
    }
    var onNew: ((String) -> Void)?
    /// النسخة الجديدة اتفكت وجاهزة: الموديل بيختار إمتى يقفل ويفتحها
    var onReady: ((String) -> Void)?
    var onFail: ((String) -> Void)?

    private var timer: Timer?
    private var asset: URL?
    private var staged: URL?
    private var progress: NSKeyValueObservation?

    /// الـ API من غير توكن مسموحله 60 طلب في الساعة، فمرة كل 12 ساعة كفاية
    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String else { return }
            let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let zip = (j["assets"] as? [[String: Any]])?
                .first { ($0["name"] as? String) == "NotchRobot.zip" }?["browser_download_url"] as? String
            DispatchQueue.main.async {
                guard let self else { return }
                self.asset = zip.flatMap(URL.init(string:))
                let new = Self.newer(v, than: Self.current) ? v : nil
                self.latest = new
                if let new, self.phase == .idle { self.onNew?(new) }
            }
        }.resume()
    }

    /// ينزّل الـ zip ويفكه ويتأكد إنه NotchRobot فعلاً وأجدد، وبعدين onReady
    func install() {
        guard let v = latest, let asset else { NSWorkspace.shared.open(Self.page); return }
        switch phase {
        case .downloading, .ready: return
        default: break
        }
        phase = .downloading(0)
        let task = URLSession.shared.downloadTask(with: asset) { [weak self] tmp, resp, err in
            // الملف المؤقت بيتمسح أول ما الـ handler يخلص، فبنفكه هنا على طول
            guard let self else { return }
            guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                return self.fail(err?.localizedDescription ?? tr("التحميل منفعش", "Download failed"))
            }
            do {
                let app = try Self.unpack(tmp, version: v)
                DispatchQueue.main.async {
                    self.staged = app
                    self.phase = .ready
                    self.onReady?(v)
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
        progress = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let f = p.fractionCompleted
            DispatchQueue.main.async {
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(f)
            }
        }
        task.resume()
    }

    /// بنقفل، وسكريبت صغير بيستنانا نقفل ويحط النسخة الجديدة مكاننا ويفتحها
    func relaunch() {
        guard let staged else { return }
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            return fail(tr("مش قادر أكتب في \(target.deletingLastPathComponent().path)", "Can't write to \(target.deletingLastPathComponent().path)"))
        }
        // بننسخ جنبه الأول وبعدين نبدّل، عشان لو النسخ وقع في النص التطبيق القديم يفضل موجود.
        // ومعاه hook.sh و statusline.sh الجداد لو كانوا في الـ zip
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        ditto "$3" "$2.new" || exit 1
        rm -rf "$2" && mv "$2.new" "$2" || exit 1
        for f in hook.sh statusline.sh; do
          [ -f "$4/$f" ] && cp "$4/$f" "$HOME/.notchrobot/$f" && chmod +x "$HOME/.notchrobot/$f"
        done
        open "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", "\(getpid())", target.path, staged.path,
                       staged.deletingLastPathComponent().path]
        do { try p.run() } catch { return fail(error.localizedDescription) }
        NSApp.terminate(nil)
    }

    private func fail(_ why: String) {
        DispatchQueue.main.async {
            self.phase = .failed(why)
            self.onFail?(why)
        }
    }

    private struct Problem: LocalizedError {
        let errorDescription: String?
    }

    private static func unpack(_ zip: URL, version: String) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("NotchRobot-update-\(version)")
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("NotchRobot.zip")
        try fm.moveItem(at: zip, to: file)
        guard run("/usr/bin/ditto", ["-x", "-k", file.path, dir.path]) else {
            throw Problem(errorDescription: tr("مش قادر أفك الـ zip", "Couldn't unzip the update"))
        }
        let candidates = [dir.appendingPathComponent("NotchRobot/NotchRobot.app"), dir.appendingPathComponent("NotchRobot.app")]
        guard let app = candidates.first(where: { fm.fileExists(atPath: $0.path) }),
              let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let v = info["CFBundleShortVersionString"] as? String, newer(v, than: current) else {
            throw Problem(errorDescription: tr("الملف اللي نزل مش نسخة أجدد من NotchRobot", "The download isn't a newer NotchRobot"))
        }
        // التوقيع بيتأكد إن مفيش ملف جوه التطبيق اتغيّر أو ناقص
        guard run("/usr/bin/codesign", ["--verify", "--deep", app.path]) else {
            throw Problem(errorDescription: tr("توقيع النسخة الجديدة مش سليم", "The new version's signature is invalid"))
        }
        return app
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// مقارنة رقم رقم: 2.10 أجدد من 2.9
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
