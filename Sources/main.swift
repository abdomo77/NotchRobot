import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class ClickThroughHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = NotchModel()
    var panel: NotchPanel!
    var lastMouse = NSPoint.zero
    var lastMove = Date()
    var leftAt: Date?
    var nextBlink = Date().addingTimeInterval(2)
    var nextGlance = Date()
    let margin: CGFloat = 30

    var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.contentView = ClickThroughHost(rootView: NotchView(m: model))

        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.layout() }

        DistributedNotificationCenter.default().addObserver(forName: .init("com.gendy.notchrobot.demo"),
                                                            object: nil, queue: .main) { [weak self] n in
            self?.demo(n.object as? String ?? "")
        }

        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.handleSwipe(e)
            return e
        }

        model.refreshBattery()
        model.watchBattery()
        model.hotkeys.register()
        model.media.start()
        model.claude.watch()
        model.voice.watch()
        model.claude.poll()
        model.updates.start()

        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.model.refreshBattery() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.model.tickSecond() }
        // الأحداث بتوصل من الـ watcher؛ ده احتياطي وبيشيل الجلسات اللي اتقفلت
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.model.claude.poll() }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.model.clipboard.poll() }
        // الدخول والخروج من الـ fullscreen بيوصلوا من الإشعارات اللي تحت؛ ده احتياطي بس
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkFullscreen() }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // التحويل لـ fullscreen بياخد ثانية أنيميشن
                self?.checkFullscreen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.checkFullscreen() }
            }
        }
        startMouseMonitors()
        scheduleTick()

        // أول مرة خالص: صفحات الترحيب. اللي كان مسطّبه قبل كده منزعجوش بيها
        if UserDefaults.standard.object(forKey: "onboarded") == nil {
            if firstRun {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.model.startOnboarding() }
            } else {
                UserDefaults.standard.set(true, forKey: "onboarded")
            }
        }

        // NOTCHROBOT_DUMP=<file.png>: يصوّر النوتش الحقيقي (بالـ layers) ويقفل — للمراجعة
        if let out = ProcessInfo.processInfo.environment["NOTCHROBOT_DUMP"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let view = self.panel.contentView, let layer = view.layer else { exit(1) }
                let scale: CGFloat = 2
                let size = view.bounds.size
                guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
                ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                ctx.scaleBy(x: scale, y: scale)
                layer.render(in: ctx)
                if let img = ctx.makeImage() {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: out))
                }
                exit(0)
            }
        }
    }

    private var tickTimer: Timer?
    private var lastMouseEvent = Date.distantPast

    /// أي حركة ماوس في أي حتة بتصحّي الـ tick لو كان نايم
    func startMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.mouseActivity() }
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in self?.mouseActivity(); return e }
    }

    private func mouseActivity() {
        lastMouseEvent = Date()
        if let t = tickTimer, t.fireDate.timeIntervalSinceNow > 1.0 / 8 { scheduleTick() }
    }

    /// قريب من النوتش أو مفتوح: 30 مرة في الثانية. الماوس بيتحرك بعيد: 8.
    /// واقف: بنصحى بس عشان الرمشة أو النظرة الجاية (مرة في الثانية على الأكتر)
    func scheduleTick() {
        tickTimer?.invalidate()
        tick()
        let now = Date()
        let near = notchRect(model.size).insetBy(dx: -250, dy: -200).contains(NSEvent.mouseLocation)
        let interval: TimeInterval
        if model.expanded || near || model.dragging || leftAt != nil {
            interval = 1.0 / 30
        } else if now.timeIntervalSince(lastMouseEvent) < 0.5 {
            interval = 1.0 / 8
        } else {
            let next = model.mood == .thinking ? min(nextBlink, nextGlance) : nextBlink
            interval = min(1, max(1.0 / 8, next.timeIntervalSince(now)))
        }
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.scheduleTick() }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    func applicationWillTerminate(_ n: Notification) { model.media.stop() }

    /// فتحته تاني من Launchpad أو Spotlight وهو شغّال: نوريك إنه موجود
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.flash(.happy, for: 2)
        model.show(Banner(icon: "hand.wave.fill", text: tr("روبو شغّال فوق 👋 قرّب الماوس من النوتش", "Robo is up top 👋 move your mouse to the notch"), color: glow), seconds: 3)
        return false
    }

    /// لو الماك فيه نوتش حقيقي نغطيه، لو مفيش نعمل واحد افتراضي
    func layout() {
        let s = screen
        let menuBar = s.frame.maxY - s.visibleFrame.maxY
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            model.baseSize = CGSize(width: s.frame.width - l.width - r.width + 24, height: s.safeAreaInsets.top)
        } else {
            model.baseSize = CGSize(width: 190, height: max(menuBar, 24) + 6)
        }
        let w = NotchModel.maxSize.width + margin * 2
        let h = NotchModel.maxSize.height + margin
        panel.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h), display: true)
    }

    /// أوامر scripts/demo.sh لتصوير فيديو. بتلمس بس الطلبات اللي جلستها بتبدأ بـ demo-
    private func demo(_ cmd: String) {
        let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "hold": model.demoHold = true
        case "release": model.demoHold = false
        case "expand": model.banner = nil; model.expanded = true
        case "collapse": model.expanded = false
        case "tab": if let t = Tab.allCases.first(where: { "\($0)" == arg }) { model.tab = t }
        case "poll": model.claude.poll(); model.claude.readUsage()
        case "allow":
            if let a = model.claude.asks.first(where: { $0.sessionId.hasPrefix("demo-") }) { model.claude.answer(a, .allow) }
        case "pick", "send": NotificationCenter.default.post(name: .demoQuestion, object: cmd)
        default: break
        }
    }

    private var swipeX: CGFloat = 0
    private var swiped = false

    /// سحب بصباعين يمين أو شمال والنوتش مفتوح = تقليب التبويبات، تبويب واحد في كل سحبة
    private func handleSwipe(_ e: NSEvent) {
        guard e.window === panel, model.expanded, e.hasPreciseScrollingDeltas, e.momentumPhase.isEmpty else { return }
        if e.phase.contains(.began) { swipeX = 0; swiped = false }
        if e.phase.contains(.ended) || e.phase.contains(.cancelled) { swipeX = 0; swiped = false; return }
        guard !swiped, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return }
        // اتجاه الصوابع نفسها، أياً كان إعداد natural scrolling
        swipeX += e.isDirectionInvertedFromDevice ? e.scrollingDeltaX : -e.scrollingDeltaX
        guard abs(swipeX) > 40 else { return }
        swiped = true
        // الصوابع شمال = اللي بعده، زي تقليب الصفحات
        model.swipeTab(swipeX < 0 ? 1 : -1)
    }

    func notchRect(_ size: CGSize) -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - size.width / 2, y: s.maxY - size.height, width: size.width, height: size.height)
    }

    func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        let mood = model.mood

        // العين بتتابع الماوس، ولما كلود شغال بيبص حواليه كأنه بيفكر
        var look = model.eyes.look
        if mood == .listening {
            // بيبصلك وانت بتتكلم
            look = CGPoint(x: 0, y: 0.4)
        } else if mood == .thinking {
            if now >= nextGlance {
                look = CGPoint(x: .random(in: -0.9...0.9), y: .random(in: -0.8...0))
                nextGlance = now.addingTimeInterval(.random(in: 0.8...1.8))
            }
        } else {
            let c = notchRect(model.size)
            look = CGPoint(x: max(-1, min(1, (mouse.x - c.midX) / 500)),
                           y: max(-1, min(1, -(mouse.y - c.midY) / 300)))
        }
        let eyes = model.eyes
        if abs(look.x - eyes.look.x) > 0.02 || abs(look.y - eyes.look.y) > 0.02 { eyes.look = look }

        // نوم وصحيان
        if mouse != lastMouse {
            if model.sleepy {
                model.sleepy = false
                model.flash(.surprised, for: 0.9)
            }
            lastMouse = mouse
            lastMove = now
        } else if !model.sleepy, mood == .idle, !model.media.isPlaying, now.timeIntervalSince(lastMove) > 45 {
            model.sleepy = true
        }

        // رمش
        if now >= nextBlink {
            model.eyes.blinking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.model.eyes.blinking = false }
            nextBlink = now.addingTimeInterval(Double.random(in: 2.5...6))
        }

        applyAlpha()

        // مستخبي في الـ fullscreen: ولا hover ولا كليكات
        if model.fullscreenHidden && !model.needsAttention {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            if model.expanded { model.expanded = false }
            return
        }

        // فتح وقفل بالـ hover
        let collapsed = notchRect(model.collapsedSize).insetBy(dx: -4, dy: -4)
        let expanded = notchRect(model.expandedSize)
        if model.demoHold || model.onboarding != nil {
            // سكريبت الـ demo أو صفحات الترحيب: النوتش يفضل مفتوح لحد ما يخلصوا
        } else if !model.expanded {
            // كارت الإذن ظاهر: منفتحش النوتش فوقه
            if collapsed.contains(mouse), model.claude.asks.isEmpty {
                model.expanded = true
                model.banner = nil
                model.activity = nil
                leftAt = nil
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else if expanded.contains(mouse) {
            leftAt = nil
        } else if let t = leftAt {
            if now.timeIntervalSince(t) > 0.35 { model.expanded = false; leftAt = nil }
        } else {
            leftAt = now
        }

        trackDrag(mouse, over: model.expanded ? expanded : collapsed)

        let active = model.expanded ? expanded : collapsed
        let ignore = !active.contains(mouse)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    private var lastDragCount = NSPasteboard(name: .drag).changeCount
    private var dragReleasedAt: Date?

    /// ملف بيتسحب فوق النوتش → افتح الرف وورّي أماكن الإسقاط
    private func trackDrag(_ mouse: NSPoint, over rect: NSRect) {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let pb = NSPasteboard(name: .drag)
        if !pressed {
            lastDragCount = pb.changeCount
            // الإسقاط نفسه بيوصل بعد ما الزرار يتساب بشوية، فلو شلنا أماكن الإسقاط على طول الملف بيقع في الفاضي
            if model.dragging, dragReleasedAt == nil { dragReleasedAt = Date() }
            if let t = dragReleasedAt, Date().timeIntervalSince(t) > 0.8 {
                model.dragging = false
                dragReleasedAt = nil
            }
            return
        }
        dragReleasedAt = nil
        guard !model.dragging, pb.changeCount != lastDragCount, rect.contains(mouse),
              pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        else { return }
        model.dragging = true
        model.tab = .shelf
        if !model.expanded { model.expanded = true; model.banner = nil; leftAt = nil }
    }

    /// فيه تطبيق مالي الشاشة كلها (فيلم، يوتيوب fullscreen، Keynote…)؟ نستخبى، إلا لو فيه تنبيه
    func checkFullscreen() {
        let full = frontmostIsFullscreen()
        if full != model.fullscreenHidden { model.fullscreenHidden = full }
        applyAlpha()
    }

    private var targetAlpha: CGFloat = 1

    /// بيتنادي من الـ tick كمان عشان التنبيهات تبان على طول حتى في الـ fullscreen
    func applyAlpha() {
        let alpha: CGFloat = model.fullscreenHidden && !model.needsAttention ? 0 : 1
        if targetAlpha != alpha {
            targetAlpha = alpha
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = alpha
            }
        }
    }

    private func frontmostIsFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid(),
              front.bundleIdentifier != "com.apple.finder",
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return false }
        let size = screen.frame.size
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (b["X"] ?? 1) == 0 && (b["Y"] ?? 1) == 0
                && (b["Width"] ?? 0) >= size.width && (b["Height"] ?? 0) >= size.height
        }
    }
}

/// --snapshot <dir>: يرسم كل حالات النوتش كصور PNG (للمراجعة من غير screen recording)
@MainActor func snapshot(to dir: String) {
    if let i = CommandLine.arguments.firstIndex(of: "--lang"), i + 1 < CommandLine.arguments.count,
       let l = Lang(rawValue: CommandLine.arguments[i + 1]) { Lang.current = l }
    let m = NotchModel()
    m.battery = 76
    let tasks: [ClaudeSession.TaskItem] = [
        .init(id: "1", title: tr("أقرا الكود", "Read the code"), status: "completed"),
        .init(id: "2", title: tr("أضيف شريط الاستهلاك", "Add the usage meter"), status: "completed"),
        .init(id: "3", title: tr("أترجم الواجهة", "Translate the UI"), status: "in_progress"),
        .init(id: "4", title: tr("أجرّب البيلد", "Test the build"), status: "pending"),
    ]
    m.claude.preview([ClaudeSession(id: "demo", cwd: "/NotchRobot", state: .working, tool: "Edit · Views.swift",
                                    pid: 0, updated: Date(), tasks: tasks)], usage: (23, 41))
    func save(_ name: String) {
        let v = NotchView(m: m).frame(width: NotchModel.maxSize.width + 20, height: m.size.height + 10)
            .background(Color(white: 0.85))
        let r = ImageRenderer(content: v)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
    save("collapsed")
    m.timerEnd = Date().addingTimeInterval(754)
    m.banner = Banner(icon: "checkmark.circle.fill", text: tr("كلود خلص في NotchRobot ✨", "Claude finished in NotchRobot ✨"), color: .green)
    save("collapsed-banner")
    m.banner = nil
    m.expanded = true
    for t in Tab.allCases { m.tab = t; save("tab-\(t)") }
    m.expanded = false
    let perm = PermissionAsk(id: "p", sessionId: "demo", project: "NotchRobot", tool: "Bash",
                             detail: "swiftc -O Sources/*.swift -o NotchRobot", hookPid: 0)
    m.claude.preview(m.claude.sessions, asks: [perm])
    save("card-permission")
    var q = PermissionAsk(id: "q", sessionId: "demo", project: "NotchRobot", tool: "AskUserQuestion",
                          detail: "", hookPid: 0)
    q.questions = [AskQuestion(text: tr("نضيف أنهي مميزات؟", "Which features should we add?"), header: tr("مميزات", "Features"),
                               multi: true, options: [
                                   .init(label: tr("استهلاك الحساب", "Account usage"), detail: tr("5 ساعات وأسبوع", "5-hour and weekly limits")),
                                   .init(label: tr("تقدم المهام", "Task progress"), detail: tr("3/7 جنب الجلسة", "3/7 next to the session")),
                                   .init(label: tr("تحديثات", "Updates"), detail: tr("يقولك لما ينزل إصدار جديد", "Tells you when a new version is out")),
                               ]),
                   AskQuestion(text: "?", header: "", multi: false, options: [.init(label: "a", detail: "")])]
    m.claude.preview(m.claude.sessions, asks: [q])
    save("card-question")
    m.claude.preview(m.claude.sessions)

    // كل اللي على الجناب مرة واحدة: أوسع حالة
    m.battery = 8
    m.charging = false
    save("collapsed-busy-wings")
    m.banner = Banner(icon: "bolt.fill", text: tr("بيشحن — 64%", "Charging — 64%"), color: Theme.green, battery: 64)
    save("banner-charging")
    m.banner = Banner(icon: "battery.25", text: tr("البطارية قربت تخلص — 18%", "Battery low — 18%"), color: Theme.red,
                      detail: tr("وصّل الشاحن 🔌", "Plug in the charger 🔌"), battery: 18)
    save("banner-low")
    m.banner = nil
    m.timerEnd = nil
    m.activity = Activity(icon: "sparkle", title: tr("أترجم الواجهة", "Translate the UI"), subtitle: "NotchRobot · 2/4",
                          color: claudeOrange, progress: 0.5)
    save("activity-task")
    m.activity = nil

    m.clipboard.preview(["https://github.com/abdomo77/NotchRobot", "#FF6B35", "{\"name\":\"robo\",\"v\":2}",
                         "hello@example.com", "482913"], pins: ["git push origin main"])
    m.expanded = true
    m.tab = .clipboard
    save("tab-clipboard-smart")

    m.tab = .style
    for b in Buddy.allCases {
        m.buddy = b
        for sk in Skin.allCases { m.skin = sk; save("style-\(b)-\(sk)") }
    }
    m.skin = .dark
    m.accentChoice = .pink
    m.buddy = .cat
    save("style-accent-pink")
    m.accentChoice = .cyan
    m.buddy = .robot
    for p in 0..<OnboardingView.pages { m.onboarding = p; save("onboarding-\(p)") }
}

/// لازم تتحسب قبل أي حاجة تقرا Lang.current (هي اللي بتكتب "lang" أول مرة)
let firstRun = UserDefaults.standard.object(forKey: "lang") == nil
    && UserDefaults.standard.object(forKey: "soundsOn") == nil
    && !FileManager.default.fileExists(atPath: ClaudeStore.base.appendingPathComponent("sessions.json").path)

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { snapshot(to: CommandLine.arguments[i + 1]) }
    exit(0)
}

// نسخة تانية شغّالة (مثلاً واحدة من /Applications وواحدة من فولدر المشروع): نصحّيها ونقفل
if let other = NSRunningApplication.runningApplications(withBundleIdentifier: "com.gendy.notchrobot")
    .first(where: { $0.processIdentifier != getpid() }), let url = other.bundleURL {
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    Thread.sleep(forTimeInterval: 0.3)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
