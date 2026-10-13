import AppKit
import UniformTypeIdentifiers

/// رف مؤقت: تسحب ملفات على النوتش وتسيبها هنا لحد ما تسحبها تاني لمكان تاني أو تبعتها AirDrop.
/// الملفات نفسها مبتتنقلش، إحنا بنحفظ مكانها بس.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []
    private static let key = "shelf"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        let new = urls.filter { u in !items.contains(u) }
        guard !new.isEmpty else { return }
        items.insert(contentsOf: new, at: 0)
        save()
    }

    func remove(_ u: URL) { items.removeAll { $0 == u }; save() }
    func clear() { items = []; save() }

    /// اللي اتمسح أو اتنقل من برا يختفي من الرف
    func prune() {
        let alive = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if alive != items { items = alive; save() }
    }

    private func save() { UserDefaults.standard.set(items.map(\.path), forKey: Self.key) }

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let s = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        s.perform(withItems: urls)
    }

    static func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    /// يطلّع روابط الملفات من اللي اتساب على النوتش
    static func load(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, err in
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                else if let u = item as? NSURL { url = u as URL }
                // Finder ساعات بيبعت file reference (file:///.file/id=…)، نحوّله لمسار عادي
                if let u = url, let path = (u as NSURL).filePathURL { url = path }
                log("load: \(url?.path ?? "nil") \(err.map { "\($0)" } ?? "")")
                if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }

    /// مؤقت عشان نعرف الـ drop بيوصل ولا لأ
    static func log(_ s: String) {
        let line = "\(Date()) \(s)\n"
        let u = ClaudeStore.base.appendingPathComponent("drop.log")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: u) }
    }

    private static var iconCache: [String: NSImage] = [:]
    static func icon(_ u: URL) -> NSImage {
        if let i = iconCache[u.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: u.path)
        iconCache[u.path] = i
        return i
    }
}
