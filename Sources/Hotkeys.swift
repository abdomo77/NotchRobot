import AppKit
import Carbon.HIToolbox

/// اختصارات من الكيبورد شغالة في أي تطبيق. Carbon hotkeys مش محتاجة صلاحية Accessibility
final class Hotkeys {
    var onScreenshot: (() -> Void)?
    private var refs: [EventHotKeyRef?] = []

    /// ⌃⌥S = سكرين شوت. بيترسم أزرار لوحدها، عشان الرموز بتتقلب جوه الجملة العربي
    static let screenshotKeys = ["⌃", "⌥", "S"]

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            guard let event, let ctx else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<Hotkeys>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { if id.id == 1 { me.onScreenshot?() } }
            return noErr
        }, 1, &spec, me, nil)

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4E52_4254), id: 1) // "NRBT"
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}

/// سكرين شوت لحتة من الشاشة عن طريق screencapture بتاع النظام
enum Screenshot {
    /// بتتحفظ هنا مش في temp، عشان الرف بيشيل أي ملف اتمسح
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/NotchRobot", isDirectory: true)

    private static let names: DateFormatter = {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return d
    }()

    /// done بيتنادي على الـ main thread بس لو الصورة اتاخدت فعلاً (Esc = مفيش ملف)
    static func take(_ done: @escaping (URL) -> Void) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Screenshot \(names.string(from: Date())).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i تحدد بالماوس (Space = شباك كامل)، -x من غير صوت الكاميرا
        p.arguments = ["-i", "-x", url.path]
        p.terminationHandler = { _ in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            DispatchQueue.main.async {
                if let img = NSImage(contentsOf: url) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([img, url as NSURL])
                }
                done(url)
            }
        }
        try? p.run()
    }
}
