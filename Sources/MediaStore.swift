import AppKit
import SwiftUI

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var bundle: String?
    var duration: Double
    var elapsed: Double
    var timestamp: Date?
    var rate: Double
    var playing: Bool

    func position(at now: Date) -> Double {
        guard playing, let ts = timestamp else { return elapsed }
        return min(duration > 0 ? duration : .infinity, elapsed + now.timeIntervalSince(ts) * max(rate, 1))
    }
}

/// بيقرا الأغنية الشغالة من أي تطبيق (Spotify / Music / YouTube في المتصفح…)
/// عن طريق helper جوه /usr/bin/perl لأن MediaRemote مقفولة على التطبيقات العادية
final class MediaStore: ObservableObject {
    @Published private(set) var info: NowPlaying?
    @Published private(set) var artwork: NSImage? {
        didSet { accent = artwork.flatMap(Self.vividColor) }
    }
    @Published private(set) var accent: Color?

    var isPlaying: Bool { info?.playing == true }

    private var process: Process?
    private var buffer = Data()
    private let dylib = Bundle.main.resourceURL?.appendingPathComponent("libnowplaying.dylib").path

    func start() {
        guard let dylib, FileManager.default.fileExists(atPath: dylib) else { return }
        let p = makeProcess(mode: "stream", dylib: dylib)
        let pipe = Pipe()
        p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            self?.consume(chunk)
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.start() }
        }
        try? p.run()
        process = p
    }

    private func makeProcess(mode: String, dylib: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", "use DynaLoader; DynaLoader::dl_load_file($ARGV[0], 0) or exit 1;", dylib]
        var env = ProcessInfo.processInfo.environment
        env["NOTCHROBOT_MR"] = mode
        p.environment = env
        p.standardError = FileHandle.nullDevice
        return p
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            DispatchQueue.main.async { self.update(j) }
        }
    }

    private func update(_ j: [String: Any]) {
        if let art = j["artwork"] as? String {
            artwork = art.isEmpty ? nil : Data(base64Encoded: art).flatMap(NSImage.init(data:))
        }
        guard let title = j["title"] as? String, !title.isEmpty else {
            if info != nil { info = nil }
            return
        }
        let new = NowPlaying(
            title: title,
            artist: j["artist"] as? String ?? "",
            bundle: j["bundle"] as? String,
            duration: (j["duration"] as? NSNumber)?.doubleValue ?? 0,
            elapsed: (j["elapsed"] as? NSNumber)?.doubleValue ?? 0,
            timestamp: (j["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
            rate: (j["rate"] as? NSNumber)?.doubleValue ?? 0,
            playing: (j["playing"] as? NSNumber)?.boolValue ?? false)
        if new.bundle != info?.bundle { resolveApp(new.bundle) }
        if new.title != info?.title {
            artwork = nil
            fetchYouTubeArtwork(title: new.title, bundle: new.bundle)
        }
        if new != info { info = new }
    }

    // MARK: صورة الأغنية من يوتيوب

    /// المتصفحات اللي بنقدر نقرا تابّاتها بـ AppleScript (Safari بيسمي العنوان name بدل title)
    private static let browsers: [String: String] = [
        "com.google.Chrome": "title", "com.brave.Browser": "title", "com.microsoft.edgemac": "title",
        "company.thebrowser.Browser": "title", "com.vivaldi.Vivaldi": "title", "com.operasoftware.Opera": "title",
        "com.apple.Safari": "name",
    ]
    private let scriptQueue = DispatchQueue(label: "notchrobot.applescript")

    /// macOS 26 مبقاش بيدّي صورة الأغنية، فبنجيب thumbnail الفيديو من تاب يوتيوب اللي شغال
    private func fetchYouTubeArtwork(title: String, bundle: String?) {
        guard let bundle, let titleKey = Self.browsers[bundle] else { return }
        let source = """
        tell application id "\(bundle)"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (URL of t) & tab & (\(titleKey) of t) & linefeed
                end repeat
            end repeat
            return out
        end tell
        """
        scriptQueue.async { [weak self] in
            var err: NSDictionary?
            guard let out = NSAppleScript(source: source)?.executeAndReturnError(&err).stringValue,
                  let id = Self.youTubeID(in: out, title: title) else { return }
            self?.downloadThumbnail(id: id, title: title,
                                    names: ["maxresdefault", "sddefault", "mqdefault"])
        }
    }

    private static func youTubeID(in tabs: String, title: String) -> String? {
        var candidates: [(id: String, matches: Bool)] = []
        for line in tabs.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let url = parts.first.flatMap(URLComponents.init(string:)),
                  let host = url.host, host.contains("youtube.com") || host.contains("youtu.be") else { continue }
            let id: String?
            if host.contains("youtu.be") {
                id = url.path.split(separator: "/").first.map(String.init)
            } else if url.path.hasPrefix("/shorts/") {
                id = url.path.split(separator: "/").dropFirst().first.map(String.init)
            } else {
                id = url.queryItems?.first { $0.name == "v" }?.value
            }
            guard let id, !id.isEmpty else { continue }
            let tabTitle = parts.count > 1 ? parts[1] : ""
            candidates.append((id, tabTitle.localizedCaseInsensitiveContains(title)
                               || title.localizedCaseInsensitiveContains(tabTitle.replacingOccurrences(of: " - YouTube", with: ""))))
        }
        return (candidates.first { $0.matches } ?? candidates.first)?.id
    }

    /// أكتر لون حيوي في الصورة، متفتّح كفاية إنه يبان على الأسود
    static func vividColor(_ img: NSImage) -> Color? {
        let n = 12
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
        NSGraphicsContext.restoreGraphicsState()

        var best: (score: CGFloat, h: CGFloat, s: CGFloat, b: CGFloat)?
        for x in 0..<n {
            for y in 0..<n {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
                let score = sat * b
                if score > (best?.score ?? 0.12) { best = (score, h, sat, b) }
            }
        }
        guard let best else { return nil }
        return Color(hue: best.h, saturation: min(1, max(0.55, best.s)), brightness: max(0.9, best.b))
    }

    /// نصغّر الصورة عشان متاخدش رام على الفاضي
    private static func thumb(_ img: NSImage) -> NSImage {
        let h: CGFloat = 256
        let w = img.size.height > 0 ? h * img.size.width / img.size.height : h
        let out = NSImage(size: NSSize(width: w, height: h))
        out.lockFocus()
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        out.unlockFocus()
        return out
    }

    /// maxres مش موجودة لكل الفيديوهات، فبنجرب اللي بعدها
    private func downloadThumbnail(id: String, title: String, names: [String]) {
        guard let name = names.first,
              let url = URL(string: "https://i.ytimg.com/vi/\(id)/\(name).jpg") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, resp, _ in
            guard let self else { return }
            if (resp as? HTTPURLResponse)?.statusCode == 200, let data, let img = NSImage(data: data) {
                DispatchQueue.main.async {
                    if self.info?.title == title, self.artwork == nil { self.artwork = Self.thumb(img) }
                }
            } else {
                self.downloadThumbnail(id: id, title: title, names: Array(names.dropFirst()))
            }
        }.resume()
    }

    enum Command: Int { case toggle = 2, next = 4, previous = 5 }

    func send(_ c: Command) {
        guard let dylib else { return }
        try? makeProcess(mode: String(c.rawValue), dylib: dylib).run()
    }

    private(set) var appName: String?
    private(set) var appIcon: NSImage?

    private func resolveApp(_ bundle: String?) {
        guard let b = bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else {
            appName = nil; appIcon = nil; return
        }
        appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    func stop() { process?.terminationHandler = nil; process?.terminate() }
}
