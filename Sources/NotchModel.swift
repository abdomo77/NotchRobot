import AppKit
import Combine
import IOKit.ps
import ServiceManagement
import SwiftUI

enum Mood { case idle, happy, sleepy, surprised, thinking, alert, listening }

enum Tab: CaseIterable {
    case home, music, claude, clipboard, shelf, timer, settings
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .music: return "music.note"
        case .claude: return "sparkle"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .settings: return "gearshape.fill"
        }
    }
}

struct Banner: Equatable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
    var detail: String? = nil
}

/// صوت مختلف لكل حالة من حالات كلود، وتقدر تغيّره من الإعدادات
enum SoundEvent: String, CaseIterable {
    case waiting, done, error
    var title: String {
        switch self {
        case .waiting: return tr("كلود مستنيك", "Claude is waiting")
        case .done: return tr("كلود خلص", "Claude is done")
        case .error: return tr("حصل error", "Error")
        }
    }
    var fallback: String {
        switch self {
        case .waiting: return "Ping"
        case .done: return "Glass"
        case .error: return "Basso"
        }
    }
    /// "" = من غير صوت
    static let choices = ["Ping", "Glass", "Basso", "Hero", "Pop", "Tink", "Funk", "Purr",
                          "Submarine", "Blow", "Bottle", "Frog", "Morse", "Sosumi", ""]
}

let glow = Color(red: 0.31, green: 0.96, blue: 1.0)
let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

/// ألوان iOS في الوضع الغامق (زي الـ Dynamic Island وقوايم الإعدادات)
enum Theme {
    static let card = Color(red: 0.110, green: 0.110, blue: 0.118)      // secondarySystemBackground
    static let fill = Color(red: 0.173, green: 0.173, blue: 0.180)      // tertiarySystemBackground
    static let track = Color(red: 0.224, green: 0.224, blue: 0.239)     // سويتش مقفول
    static let selected = Color(red: 0.388, green: 0.388, blue: 0.400)  // الجزء المختار في الـ segmented control
    static let separator = Color.white.opacity(0.1)
    static let secondary = Color(red: 0.922, green: 0.922, blue: 0.961).opacity(0.6)
    static let tertiary = Color(red: 0.922, green: 0.922, blue: 0.961).opacity(0.3)
    static let blue = Color(nsColor: .systemBlue)
    static let green = Color(nsColor: .systemGreen)
    static let red = Color(nsColor: .systemRed)
    static let orange = Color(nsColor: .systemOrange)
    static let yellow = Color(nsColor: .systemYellow)
}

/// النظر والرمش، منفصلين عن الموديل عشان يتحدّثوا كتير من غير ما يرسموا كل حاجة
final class EyeState: ObservableObject {
    @Published var look: CGPoint = .zero
    @Published var blinking = false
}

final class NotchModel: ObservableObject {
    let eyes = EyeState()
    let claude = ClaudeStore()
    let media = MediaStore()
    let clipboard = ClipboardStore()
    let shelf = ShelfStore()
    let voice = VoiceStore()
    let updates = UpdateStore()
    private var bag = Set<AnyCancellable>()

    @Published var expanded = false {
        // الوقت مش بيتحدّث والنوتش مقفول، فنحدّثه أول ما يتفتح
        didSet { if expanded, !oldValue { now = Date() } }
    }
    @Published var fullscreenHidden = false
    @Published var tab: Tab = .home {
        didSet {
            let all = Tab.allCases
            let forward = (all.firstIndex(of: tab) ?? 0) > (all.firstIndex(of: oldValue) ?? 0)
            if forward != tabForward { tabForward = forward }
        }
    }
    /// رايح للتبويب اللي بعده (يمين) ولا اللي قبله، عشان المحتوى يتزحلق من الناحية الصح
    @Published private(set) var tabForward = true
    @Published var transient: Mood?
    @Published var sleepy = false
    @Published var speech: String?
    @Published var banner: Banner?
    @Published var now = Date()
    @Published var battery: Int?
    @Published var charging = false
    /// فيه ملف بيتسحب فوق النوتش
    @Published var dragging = false

    // تايمر / بومودورو
    @Published var timerTotal: TimeInterval = 25 * 60
    @Published var timerEnd: Date?
    @Published var timerPausedLeft: TimeInterval?

    @Published var lang = Lang.current {
        didSet { Lang.current = lang; UserDefaults.standard.set(lang.rawValue, forKey: "lang") }
    }

    @Published var soundsOn = UserDefaults.standard.object(forKey: "soundsOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundsOn, forKey: "soundsOn") }
    }

    var baseSize = CGSize(width: 190, height: 32)
    static let maxSize = CGSize(width: 480, height: 300)

    init() {
        claude.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        media.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        clipboard.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        shelf.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        voice.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        updates.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        updates.onNew = { [weak self] v in self?.updateAvailable(v) }
        voice.onResult = { [weak self] t in self?.voiceTyped(t) }
        voice.onError = { [weak self] t in self?.voiceFailed(t) }
        claude.onTransition = { [weak self] s in self?.claudeChanged(s) }
        claude.onError = { [weak self] s, fatal in self?.claudeFailed(s, fatal: fatal) }
    }

    // MARK: المزاج

    var mood: Mood {
        if let transient { return transient }
        if voice.state == .listening { return .listening }
        if voice.state == .processing { return .thinking }
        if !claude.waiting.isEmpty { return .alert }
        if !claude.working.isEmpty { return .thinking }
        return sleepy ? .sleepy : .idle
    }

    /// سحب بصباعين على التراك باد: التبويب اللي بعده أو اللي قبله (من غير لف)
    func swipeTab(_ step: Int) {
        let all = Tab.allCases
        guard let i = all.firstIndex(of: tab), all.indices.contains(i + step) else { return }
        tab = all[i + step]
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func flash(_ m: Mood, for t: Double = 2.5) {
        transient = m
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            if self?.transient == m { self?.transient = nil }
        }
    }

    // MARK: المقاسات

    var timerActive: Bool { timerEnd != nil || timerPausedLeft != nil }

    var hasClaudeBadge: Bool { !claude.sessions.isEmpty }

    var rightWingWidth: CGFloat {
        var items: [CGFloat] = []
        if voice.active { items.append(30) }
        if hasClaudeBadge { items.append(34) }
        if timerActive { items.append(44) }
        if media.isPlaying { items.append(20) }
        guard !items.isEmpty else { return 0 }
        return items.reduce(0, +) + CGFloat(items.count - 1) * 6 + 10
    }

    var leftWingWidth: CGFloat { media.isPlaying ? 40 : 0 }

    var collapsedSize: CGSize {
        let w = baseSize.width + leftWingWidth + rightWingWidth
        if let ask = claude.asks.first, !ask.questions.isEmpty {
            // على أطول سؤال عشان النوتش ميتنططش وانت بتقلّب بين الأسئلة
            let rows = CGFloat(ask.questions.map(\.options.count).max() ?? 1)
            return CGSize(width: max(w, 480), height: baseSize.height + 108 + rows * (AskQuestion.rowHeight + 1))
        }
        if !claude.asks.isEmpty { return CGSize(width: max(w, 460), height: baseSize.height + 100) }
        if let banner {
            return CGSize(width: max(w, banner.detail == nil ? 380 : 440),
                          height: baseSize.height + (banner.detail == nil ? 34 : 58))
        }
        return CGSize(width: w, height: baseSize.height)
    }

    var expandedSize: CGSize {
        if tab == .clipboard {
            let rows = CGFloat(min(max(clipboard.items.count, 1), 5))
            return CGSize(width: 480, height: max(180, 84 + rows * 34))
        }
        if tab == .settings { return CGSize(width: 480, height: soundsOn ? 262 : 196) }
        if tab == .claude {
            let rows = CGFloat(min(max(claude.sessions.count, 1), 4))
            let usage: CGFloat = claude.usage5h != nil || claude.usageWeek != nil ? 26 : 0
            return CGSize(width: 480, height: min(Self.maxSize.height, max(180, 90 + rows * 46 + usage)))
        }
        return CGSize(width: 480, height: 180)
    }

    var size: CGSize { expanded ? expandedSize : collapsedSize }

    /// لون مأخوذ من صورة الأغنية (زي الـ Dynamic Island)، وإلا السماوي بتاع روبو
    /// حاجة لازم تبان حتى في الـ fullscreen
    var needsAttention: Bool { banner != nil || !claude.asks.isEmpty || voice.active }

    var accent: Color { media.isPlaying || tab == .music ? media.accent ?? glow : glow }

    // MARK: أحداث

    private var lines: [String] { [
        tr("أهلاً! أنا روبو 🤖", "Hi! I'm Robo 🤖"), tr("بيب بوب… بشتغل معاك 🔊", "Beep boop… working with you 🔊"), tr("متنساش تشرب مية 💧", "Don't forget to drink water 💧"),
        tr("يلا نشتغل! 💪", "Let's get to work! 💪"), tr("خد بريك صغير ☕️", "Take a short break ☕️"), tr("إنت جامد النهارده 😎", "You're crushing it today 😎"),
    ] }

    func poke() {
        flash(.happy, for: 2.8)
        speech = lines.randomElement()
        let token = speech
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            if self?.speech == token { self?.speech = nil }
        }
    }

    func show(_ b: Banner, sound: String? = nil, seconds: Double = 4) {
        banner = b
        if let sound { play(sound) }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.banner?.id == b.id { self?.banner = nil }
        }
    }

    private func claudeChanged(_ s: ClaudeSession) {
        switch s.state {
        case .waiting where claude.asks.contains { $0.sessionId == s.id }:
            // الكارت نفسه هو التنبيه
            flash(.surprised, for: 1.5)
            play(.waiting)
        case .waiting:
            tab = .claude
            flash(.surprised, for: 1.5)
            show(Banner(icon: "exclamationmark.bubble.fill", text: tr("كلود محتاجك في \(s.project)", "Claude needs you in \(s.project)"), color: claudeOrange),
                 sound: sound(.waiting), seconds: 6)
        case .done:
            flash(.happy)
            show(Banner(icon: "checkmark.circle.fill", text: tr("كلود خلص في \(s.project) ✨", "Claude finished in \(s.project) ✨"), color: .green,
                        detail: s.summary),
                 sound: sound(.done), seconds: s.summary == nil ? 4 : 8)
        default: break
        }
    }

    // MARK: الإملاء بالصوت (sp2txt)

    private func voiceTyped(_ text: String) {
        flash(.happy, for: 1.8)
        show(Banner(icon: "mic.fill", text: tr("سمعتك وكتبتها ✍️", "Heard you and typed it ✍️"), color: glow, detail: text),
             seconds: min(8, 3 + Double(text.count) / 25))
    }

    private func voiceFailed(_ message: String) {
        flash(.surprised, for: 1.2)
        show(Banner(icon: "mic.slash.fill", text: message.isEmpty ? tr("مسمعتكش كويس 🙉", "Didn't catch that 🙉") : message, color: .orange),
             seconds: 3)
    }

    private var lastErrorSound: [String: Date] = [:]

    /// fatal = كلود وقف خالص (API error مثلاً)، غير كده أداة فشلت وهو كمّل
    /// إصدار جديد على GitHub: نقولك مرة واحدة بس لكل إصدار
    private func updateAvailable(_ v: String) {
        let key = "notifiedVersion"
        guard UserDefaults.standard.string(forKey: key) != v else { return }
        UserDefaults.standard.set(v, forKey: key)
        show(Banner(icon: "arrow.down.circle.fill", text: tr("فيه إصدار جديد v\(v) — من الإعدادات", "NotchRobot v\(v) is out — see Settings"),
                    color: glow), seconds: 6)
    }

    private func claudeFailed(_ s: ClaudeSession, fatal: Bool) {
        if fatal {
            flash(.surprised, for: 1.5)
            show(Banner(icon: "xmark.octagon.fill", text: tr("كلود وقف بسبب error في \(s.project)", "Claude stopped on an error in \(s.project)"), color: .red,
                        detail: s.message),
                 sound: sound(.error), seconds: 8)
            return
        }
        // أوامر كتير بتفشل عادي (grep مالقاش حاجة مثلاً)، فمنزعجكش أكتر من مرة كل 30 ثانية
        if let t = lastErrorSound[s.id], Date().timeIntervalSince(t) < 30 { return }
        lastErrorSound[s.id] = Date()
        flash(.surprised, for: 0.9)
        play(.error)
    }

    // MARK: الأصوات

    func sound(_ e: SoundEvent) -> String {
        UserDefaults.standard.string(forKey: "sound." + e.rawValue) ?? e.fallback
    }

    func setSound(_ e: SoundEvent, _ name: String) {
        objectWillChange.send()
        UserDefaults.standard.set(name, forKey: "sound." + e.rawValue)
        if !name.isEmpty { NSSound(named: name)?.stop(); NSSound(named: name)?.play() }
    }

    func play(_ e: SoundEvent) { play(sound(e)) }

    func play(_ name: String) {
        guard soundsOn, !name.isEmpty, let snd = NSSound(named: name) else { return }
        snd.stop()
        snd.play()
    }

    // MARK: البطارية

    func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let pct = cap * 100 / max
            let isCharging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            if isCharging && !charging && battery != nil {
                show(Banner(icon: "bolt.fill", text: tr("بيشحن — \(pct)%", "Charging — \(pct)%"), color: .green), sound: "Pop", seconds: 3)
                flash(.happy)
            }
            battery = pct
            charging = isCharging
            return
        }
    }

    // MARK: التايمر

    var timerLeft: TimeInterval {
        if let p = timerPausedLeft { return p }
        if let e = timerEnd { return max(0, e.timeIntervalSince(now)) }
        return timerTotal
    }

    func startTimer(minutes: Double? = nil) {
        if let minutes { timerTotal = minutes * 60; timerPausedLeft = nil }
        now = Date()
        timerEnd = now.addingTimeInterval(timerPausedLeft ?? timerTotal)
        timerPausedLeft = nil
    }

    func pauseTimer() {
        guard let e = timerEnd else { return }
        timerPausedLeft = max(0, e.timeIntervalSinceNow)
        timerEnd = nil
    }

    func resetTimer() { timerEnd = nil; timerPausedLeft = nil }

    func tickSecond() {
        let t = Date()
        // تحديث now بيعيد رسم النوتش كله، والمقفول مش بيعرض الوقت غير في التايمر
        if expanded || timerEnd != nil { now = t }
        if expanded, tab == .shelf { shelf.prune() }
        if let e = timerEnd, e <= t {
            timerEnd = nil
            flash(.happy, for: 4)
            show(Banner(icon: "alarm.fill", text: tr("الوقت خلص! ⏰ خد بريك", "Time's up! ⏰ Take a break"), color: glow), sound: "Hero", seconds: 6)
        }
    }

    // MARK: الإعدادات

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }
}
