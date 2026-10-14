import AppKit
import Combine
import IOKit.ps
import ServiceManagement
import SwiftUI

enum Mood { case idle, happy, sleepy, surprised, thinking, alert, listening }

enum Tab: CaseIterable {
    case home, music, claude, clipboard, shelf, timer, style, settings
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .music: return "music.note"
        case .claude: return "sparkle"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .style: return "paintbrush.fill"
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
    /// بدل الأيقونة: بطارية بتتملي (للشحن والبطارية الضعيفة)
    var battery: Int? = nil
}

/// Live Activity: سطر صغير تحت النوتش المقفول لثواني (أغنية جديدة، مهمة كلود اللي بعدها…)
struct Activity: Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var artwork: NSImage? = nil
    /// من 0 لـ 1، بيترسم دايرة جنب الكلام
    var progress: Double? = nil
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
    let hotkeys = Hotkeys()
    private var bag = Set<AnyCancellable>()

    @Published var expanded = false {
        // الوقت مش بيتحدّث والنوتش مقفول، فنحدّثه أول ما يتفتح
        didSet { if expanded, !oldValue { now = Date() } }
    }
    @Published var fullscreenHidden = false
    /// سكريبت الـ demo ماسك النوتش: الماوس مبيفتحوش ولا يقفله
    var demoHold = false
    /// صفحة الترحيب اللي ظاهرة (أول مرة بس)
    @Published var onboarding: Int?
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
    @Published var activity: Activity?
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

    @Published var skin = Appearance.skin {
        didSet { Appearance.skin = skin; UserDefaults.standard.set(skin.rawValue, forKey: "skin") }
    }
    @Published var buddy = Appearance.buddy {
        didSet { Appearance.buddy = buddy; UserDefaults.standard.set(buddy.rawValue, forKey: "buddy") }
    }
    @Published var accentChoice = Appearance.accent {
        didSet { Appearance.accent = accentChoice; UserDefaults.standard.set(accentChoice.rawValue, forKey: "accent") }
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
        claude.onUsageAlert = { [weak self] a in self?.usageAlert(a) }
        updates.onReady = { [weak self] v in self?.updateReady(v) }
        updates.onFail = { [weak self] t in self?.updateFailed(t) }
        hotkeys.onScreenshot = { [weak self] in self?.screenshot() }
        media.$info.sink { [weak self] i in self?.songChanged(i) }.store(in: &bag)
        claude.$sessions.sink { [weak self] s in self?.tasksChanged(s) }.store(in: &bag)
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
        if timerActive { items.append(58) }
        if media.isPlaying { items.append(20) }
        if lowBattery { items.append(26) }
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
        if activity != nil { return CGSize(width: max(w, 400), height: baseSize.height + 46) }
        return CGSize(width: w, height: baseSize.height)
    }

    var expandedSize: CGSize {
        if onboarding != nil { return CGSize(width: 480, height: 230) }
        if tab == .clipboard {
            let rows = CGFloat(min(max(clipboard.visible.count, 1), ClipboardStore.shown))
            return CGSize(width: 480, height: max(180, 84 + rows * 32))
        }
        if tab == .settings { return CGSize(width: 480, height: soundsOn ? 290 : 224) }
        if tab == .style { return CGSize(width: 480, height: 230) }
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
    var needsAttention: Bool { banner != nil || !claude.asks.isEmpty || voice.active || onboarding != nil }

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
    private static let usageTime: [Lang: DateFormatter] = {
        func make(_ f: String, _ l: String) -> DateFormatter {
            let d = DateFormatter(); d.locale = Locale(identifier: l); d.dateFormat = f; return d
        }
        return [.ar: make("EEEE h:mm a", "ar_EG"), .en: make("EEE h:mm a", "en_US")]
    }()

    private func usageAlert(_ a: UsageAlert) {
        func name(_ k: UsageAlert.Kind) -> String {
            k == .fiveHour ? tr("ليمت الـ 5 ساعات", "5-hour limit") : tr("الليمت الأسبوعي", "weekly limit")
        }
        switch a {
        case let .high(k, pct, resetsAt):
            let when = Self.usageTime[Lang.current]!.string(from: resetsAt)
            let full = pct >= 100
            show(Banner(icon: full ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                        text: full ? tr("وصلت لـ\(name(k))", "You've hit your \(name(k))")
                                   : tr("استهلكت \(pct)% من \(name(k))", "\(pct)% of your \(name(k)) used"),
                        color: full ? Theme.red : Theme.orange,
                        detail: tr("بيرجع \(when)", "Resets \(when)")),
                 sound: sound(.error), seconds: 7)
        case let .reset(k):
            show(Banner(icon: "arrow.counterclockwise.circle.fill", text: tr("\(name(k)) رجع ✨", "Your \(name(k)) is back ✨"),
                        color: Theme.green, detail: tr("تقدر تكمّل شغل مع كلود", "You can get back to work with Claude")),
                 sound: sound(.done), seconds: 6)
        }
    }

    /// إصدار جديد على GitHub: لو التحديث التلقائي شغال بننزّله، وإلا نقولك مرة واحدة بس لكل إصدار
    private func updateAvailable(_ v: String) {
        if updates.auto { updates.install(); return }
        let key = "notifiedVersion"
        guard UserDefaults.standard.string(forKey: key) != v else { return }
        UserDefaults.standard.set(v, forKey: key)
        show(Banner(icon: "arrow.down.circle.fill", text: tr("فيه إصدار جديد v\(v) — من الإعدادات", "NotchRobot v\(v) is out — see Settings"),
                    color: glow), seconds: 6)
    }

    /// التحديث نزل واتفك: نستنى لو كلود مستني رد منك (الرد هيضيع لو قفلنا)، وبعدين نقفل ونفتح الجديد
    private func updateReady(_ v: String) {
        guard claude.asks.isEmpty, onboarding == nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.updateReady(v) }
            return
        }
        flash(.happy, for: 2)
        show(Banner(icon: "arrow.down.circle.fill", text: tr("بتحدّث لـ v\(v)… راجع في ثانية", "Updating to v\(v)… back in a second"),
                    color: glow), seconds: 3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.updates.relaunch() }
    }

    private func updateFailed(_ why: String) {
        show(Banner(icon: "exclamationmark.triangle.fill", text: tr("التحديث منفعش", "Update failed"), color: Theme.orange,
                    detail: why), seconds: 6)
    }

    // MARK: Live Activities

    func showActivity(_ a: Activity, seconds: Double = 3.5) {
        // الكروت والتنبيهات أهم، والمفتوح مش محتاجها
        guard !expanded, claude.asks.isEmpty, banner == nil, onboarding == nil else { return }
        activity = a
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.activity?.id == a.id { self?.activity = nil }
        }
    }

    private var lastSong: String?

    /// أغنية جديدة اشتغلت: الجزيرة بتتمد وتعرض اسمها، زي الآيفون
    private func songChanged(_ i: NowPlaying?) {
        guard let i, i.playing else { return }
        defer { lastSong = i.title }
        guard let last = lastSong, last != i.title else { return }
        showActivity(Activity(icon: "music.note", title: i.title, subtitle: i.artist, color: glow))
    }

    private var lastTasks: [String: String]?

    /// كلود بدأ مهمة جديدة من قايمته
    private func tasksChanged(_ sessions: [ClaudeSession]) {
        var now: [String: String] = [:]
        for s in sessions { if let t = s.activeTask { now[s.id] = t } }
        defer { lastTasks = now }
        guard let last = lastTasks else { return }
        for s in sessions {
            guard let t = now[s.id], last[s.id] != t, let p = s.progress else { continue }
            showActivity(Activity(icon: "sparkle", title: t, subtitle: "\(s.project) · \(p.done)/\(p.total)",
                                  color: claudeOrange, progress: Double(p.done) / Double(max(p.total, 1))))
            return
        }
    }

    // MARK: سكرين شوت

    /// ⌃⌥S أو زرار الرف: تحدد حتة من الشاشة، فتتحفظ على الرف وتتنسخ
    func screenshot() {
        expanded = false
        Screenshot.take { [weak self] url in
            guard let self else { return }
            self.shelf.add([url])
            self.flash(.happy, for: 1.5)
            self.show(Banner(icon: "camera.viewfinder", text: tr("اتصورت 📸 على الرف ومنسوخة", "Captured 📸 on the shelf and copied"),
                             color: glow), sound: "Pop", seconds: 3)
        }
    }

    // MARK: الترحيب

    func startOnboarding() {
        banner = nil
        activity = nil
        onboarding = 0
        expanded = true
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        onboarding = nil
        expanded = false
        flash(.happy, for: 2)
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

    /// 10% أو أقل ومش متوصل: بتفضل ظاهرة جنب النوتش
    var lowBattery: Bool { (battery ?? 100) <= 10 && !charging }
    /// آخر حد نبّهنا عنده في المرة دي (20 ثم 10)، وبيرجع لما توصّل الشاحن
    private var lowWarned = 100
    private var fullNotified = false

    /// النظام بيقولنا أول ما الشاحن يتوصل أو النسبة تتغير، فالأنيميشن بيبان على طول
    func watchBattery() {
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<NotchModel>.fromOpaque(ctx).takeUnretainedValue().refreshBattery()
        }, me)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let pct = cap * 100 / max
            // متوصل بالشاحن، حتى لو الماك وقّف الشحن عند 80% عشان صحة البطارية
            let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            batteryChanged(pct, plugged: plugged)
            return
        }
    }

    private func batteryChanged(_ pct: Int, plugged: Bool) {
        // أول قراية بعد ما التطبيق يفتح مش "توصيل شاحن"، بس البطارية الضعيفة لازم نقول عليها
        let first = battery == nil
        defer { battery = pct; charging = plugged }
        if plugged && !charging && !first {
            lowWarned = 100
            flash(.happy)
            show(Banner(icon: "bolt.fill", text: tr("بيشحن — \(pct)%", "Charging — \(pct)%"), color: Theme.green, battery: pct),
                 sound: "Pop", seconds: 3)
        }
        if !plugged { fullNotified = false }
        if plugged, pct >= 100, !fullNotified {
            fullNotified = true
            if !first { show(Banner(icon: "bolt.fill", text: tr("اتشحن على الآخر 🔋", "Fully charged 🔋"), color: Theme.green,
                        detail: tr("تقدر تفصل الشاحن", "You can unplug the charger"), battery: 100), seconds: 4) }
        }
        guard !plugged else { return }
        if pct > 20 { lowWarned = 100; return }
        let level = pct <= 10 ? 10 : 20
        guard level < lowWarned else { return }
        lowWarned = level
        flash(.sleepy, for: 3)
        show(Banner(icon: "battery.25", text: tr("البطارية قربت تخلص — \(pct)%", "Battery low — \(pct)%"), color: Theme.red,
                    detail: tr("وصّل الشاحن 🔌", "Plug in the charger 🔌"), battery: pct),
             sound: "Funk", seconds: 6)
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
