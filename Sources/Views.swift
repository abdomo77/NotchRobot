import SwiftUI

// MARK: - شكل النوتش

/// زي الـ Dynamic Island: كبسولة وهو مقفول، ومستطيل بحواف Apple كبيرة وهو مفتوح.
/// نص القطر بيتحرك مع الـ spring فالشكل بيتمط ويرجع زي الآيفون
struct IslandShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in r: CGRect) -> Path {
        let c = min(radius, r.height / 2, r.width / 2)
        return RoundedRectangle(cornerRadius: c, style: .continuous).path(in: r)
    }
}

/// المحتوى بيظهر ويختفي بـ blur وتصغير بسيط، زي محتوى الـ Dynamic Island
struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}

extension AnyTransition {
    static var island: AnyTransition {
        .modifier(active: BlurFade(radius: 10, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
            .combined(with: .scale(scale: 0.9, anchor: .top))
    }
}

/// الـ spring بتاع الجزيرة: سريع وفيه نطّة خفيفة في الآخر
extension Animation {
    static let island = Animation.spring(response: 0.5, dampingFraction: 0.7)
}

// MARK: - Root

struct NotchView: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        let shape = IslandShape(radius: min(m.size.height / 2, m.expanded ? 42 : 36))
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                background
                if m.expanded {
                    ExpandedContent(m: m).transition(.island)
                } else {
                    CollapsedContent(m: m).transition(.island)
                }
            }
            .frame(width: m.size.width, height: m.size.height)
            .clipShape(shape)
            .overlay {
                if m.skin == .neon {
                    shape.stroke(glow.opacity(0.9), lineWidth: 1.5).shadow(color: glow, radius: 6)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                ShelfStore.log("drop على النوتش: \(providers.count)")
                ShelfStore.load(providers) { urls in m.shelf.add(urls) }
                return true
            }
            // وميض خفيف بلون الأغنية، زي الـ Dynamic Island
            .shadow(color: m.skin == .minimal ? .clear
                        : m.media.isPlaying ? m.accent.opacity(m.expanded ? 0.18 : 0.28)
                                            : .black.opacity(m.expanded ? 0.5 : 0),
                    radius: m.media.isPlaying ? 7 : 12, y: m.media.isPlaying ? 1 : 4)
            .animation(.easeInOut(duration: 0.6), value: m.accent)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.island, value: m.expanded)
        .animation(.island, value: m.size)
        .environment(\.colorScheme, .dark)
    }

    /// الزجاج بيبان بس تحت النوتش الحقيقي؛ الشريط اللي فوقه لازم يفضل أسود عشان الكاميرا متبانش
    @ViewBuilder private var background: some View {
        if m.skin == .glass {
            let solid = m.baseSize.height / (m.baseSize.height + 16)
            ZStack(alignment: .top) {
                GlassBackground(radius: min(m.size.height / 2, m.expanded ? 42 : 36))
                Color.black.opacity(0.35)
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: solid),
                                       .init(color: .black.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: m.baseSize.height + 16)
            }
        } else {
            Color.black
        }
    }
}

// MARK: - النوتش المقفول (Live Activities)

/// دايرة تقدم صغيرة (التايمر، مهام كلود)
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var size: CGFloat = 11
    var line: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: line)
            Circle().trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

/// بطارية بتتملي قدامك: وانت بتوصّل الشاحن بتطلع من الصفر لحد النسبة
struct BatteryGlyph: View {
    let level: Int
    let color: Color
    let charging: Bool
    @State private var fill: Double = 0

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(color.opacity(0.6), lineWidth: 1.2)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color)
                    .frame(width: max(2, 22 * fill))
                    .padding(2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 26, height: 13)
            Capsule().fill(color.opacity(0.6)).frame(width: 2, height: 5)
        }
        .fixedDirection()
        .onAppear {
            fill = charging ? 0 : Double(level) / 100
            withAnimation(.easeOut(duration: 1.2)) { fill = Double(level) / 100 }
        }
    }
}

/// سطر الـ Live Activity تحت النوتش: أغنية جديدة أو مهمة كلود اللي بعدها
struct ActivityRow: View {
    @ObservedObject var m: NotchModel
    let a: Activity
    private var song: Bool { a.icon == "music.note" }

    var body: some View {
        HStack(spacing: 10) {
            if song {
                EqualizerBars(color: m.accent).frame(width: 20)
            } else if let p = a.progress {
                ProgressRing(progress: p, color: a.color, size: 20, line: 2.5)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(a.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(a.subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            if song {
                Artwork(image: m.media.artwork, size: 30, radius: 7)
            } else {
                AppGlyph(icon: a.icon, color: a.color, size: 30)
            }
        }
        .langDirection()
        .padding(.horizontal, 18)
        .frame(height: 42)
    }
}

struct ClaudeBadge: View {
    @ObservedObject var m: NotchModel
    var body: some View {
        let c = m.claude
        HStack(spacing: 3) {
            if !c.waiting.isEmpty {
                AnimatedSymbol(name: "exclamationmark.bubble.fill", color: claudeOrange, motion: .pulse)
            } else if !c.working.isEmpty {
                AnimatedSymbol(name: "sparkle", color: claudeOrange, motion: .spin)
                if c.working.count > 1 {
                    Text("\(c.working.count)").foregroundStyle(claudeOrange)
                } else if let p = c.working[0].progress {
                    // تقدم قايمة المهام
                    ProgressRing(progress: Double(p.done) / Double(max(p.total, 1)), color: claudeOrange)
                }
            } else if c.recentlyDone {
                AnimatedSymbol(name: "checkmark.circle.fill", color: Theme.green, motion: .still)
            } else {
                // جلسة مفتوحة بس مستنية أمر منك
                AnimatedSymbol(name: "sparkle", color: claudeOrange.opacity(0.55), motion: .still)
                if c.sessions.count > 1 {
                    Text("\(c.sessions.count)").foregroundStyle(claudeOrange.opacity(0.55))
                }
            }
        }
        .font(.system(size: 12, weight: .bold))
        .frame(width: 34)
    }
}

func clock(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up))
    return String(format: "%d:%02d", s / 60, s % 60)
}

struct CollapsedContent: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if m.media.isPlaying {
                    Artwork(image: m.media.artwork, size: 20, radius: 5)
                        .frame(width: m.leftWingWidth, alignment: .leading)
                }
                PeekingEyes(m: m, e: m.eyes)
                    .padding(.top, 2)
                    // الشكل الهادي: العيون بتظهر بس لما يحصل حاجة
                    .opacity(m.skin == .minimal && (m.mood == .idle || m.mood == .sleepy) ? 0 : 1)
                    .frame(maxWidth: .infinity)
                if m.rightWingWidth > 0 {
                    HStack(spacing: 6) {
                        if m.voice.active { VoiceBadge(v: m.voice) }
                        if m.hasClaudeBadge { ClaudeBadge(m: m) }
                        if m.timerActive {
                            let c = m.timerEnd == nil ? Theme.secondary : Theme.orange
                            HStack(spacing: 4) {
                                ProgressRing(progress: 1 - m.timerLeft / max(m.timerTotal, 1), color: c)
                                Text(clock(m.timerLeft))
                                    .font(.system(size: 11, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(c)
                            }
                            .fixedDirection()
                            .frame(width: 58)
                        }
                        if m.media.isPlaying { EqualizerBars(color: m.accent).frame(width: 20) }
                        if m.lowBattery {
                            AnimatedSymbol(name: "battery.25", color: Theme.red, motion: .pulse, size: 13).frame(width: 26)
                        }
                    }
                    .frame(width: m.rightWingWidth, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: m.baseSize.height)

            if let ask = m.claude.asks.first, !ask.questions.isEmpty {
                QuestionCard(m: m, ask: ask)
                    .id(ask.id)
                    .transition(.island)
            } else if let ask = m.claude.asks.first {
                PermissionCard(m: m, ask: ask)
                    .transition(.island)
            } else if let b = m.banner {
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Text(b.text).lineLimit(1)
                        if let level = b.battery {
                            BatteryGlyph(level: level, color: b.color, charging: b.icon == "bolt.fill")
                        } else {
                            Image(systemName: b.icon)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(b.color)
                    if let d = b.detail {
                        Text(d)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(height: b.detail == nil ? 30 : 54)
                .padding(.horizontal, 20)
                .transition(.island)
                .id(b.id)
            } else if let a = m.activity {
                ActivityRow(m: m, a: a)
                    .transition(.island)
                    .id(a.id)
            }
        }
        .animation(.island, value: m.banner)
        .animation(.island, value: m.activity)
        .animation(.island, value: m.claude.asks)
    }
}

/// أيقونة مربعة بحواف Apple، زي أيقونة التطبيق في الـ Dynamic Island
struct AppGlyph: View {
    let icon: String
    var color: Color = claudeOrange
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: icon).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white))
    }
}

/// كلود مستني موافقتك — زي مكالمة جاية في الـ Dynamic Island. الرد بيتكتب بس لما تدوس زرار
struct PermissionCard: View {
    @ObservedObject var m: NotchModel
    let ask: PermissionAsk

    private var icon: String {
        switch ask.tool {
        case "Bash": return "terminal.fill"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "pencil"
        case "Read": return "doc.text.fill"
        case "WebFetch", "WebSearch": return "globe"
        default: return "wrench.and.screwdriver.fill"
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 10) {
                circle("checkmark", Theme.green, tr("وافق", "Allow")) { m.claude.answer(ask, .allow) }
                circle("xmark", Theme.red, tr("ارفض", "Deny")) { m.claude.answer(ask, .deny) }
                circle("arrow.up.forward.app", Theme.fill, tr("جاوب من التيرمنال", "Answer in the terminal")) {
                    m.claude.answer(ask, .terminal)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if m.claude.asks.count > 1 {
                            Text("+\(m.claude.asks.count - 1)").foregroundStyle(claudeOrange)
                        }
                        Text(ask.project).foregroundStyle(Theme.secondary)
                    }
                    .font(.system(size: 11, weight: .medium))
                    Text(tr("عايز يستخدم \(ask.tool)", "Wants to use \(ask.tool)"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .lineLimit(1)
                AppGlyph(icon: icon)
            }
            Text(ask.detail.isEmpty ? ask.tool : ask.detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .environment(\.layoutDirection, .leftToRight)
        }
        .langDirection()
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func circle(_ icon: String, _ bg: Color, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(bg))
                .fixedDirection()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// كلود بيسألك (AskUserQuestion): سؤال في كل صفحة زي قايمة iOS، والإجابات بتتبعت مرة واحدة في الآخر
struct QuestionCard: View {
    @ObservedObject var m: NotchModel
    let ask: PermissionAsk
    @State private var page = 0
    @State private var picked: [Int: Set<Int>] = [:]

    private var q: AskQuestion { ask.questions[page] }
    private var isLast: Bool { page == ask.questions.count - 1 }
    private var answered: Bool { !(picked[page] ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 6) {
                if ask.questions.count > 1 {
                    Text(tr("\(page + 1) من \(ask.questions.count)", "\(page + 1) of \(ask.questions.count)"))
                        .foregroundStyle(Theme.tertiary)
                }
                if m.claude.asks.count > 1 {
                    Text("+\(m.claude.asks.count - 1)").foregroundStyle(claudeOrange)
                }
                Spacer(minLength: 0)
                Text("\(q.header.isEmpty ? tr("كلود بيسألك", "Claude asks") : q.header) · \(ask.project)")
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                AppGlyph(icon: "questionmark", size: 20)
            }
            .font(.system(size: 11, weight: .medium))
            Text(q.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(spacing: 0) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                    if i > 0 { Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 12) }
                    option(i, o)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            HStack(spacing: 8) {
                Button { m.claude.answer(ask, .terminal) } label: {
                    Text(tr("جاوب من التيرمنال", "Answer in Terminal"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if page > 0 {
                    capsule(tr("السابق", "Back"), primary: false) { page -= 1 }
                }
                capsule(isLast ? tr("ابعت", "Send") : tr("التالي", "Next"), primary: true) { next() }
                    .disabled(!answered)
            }
        }
        .langDirection()
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .onReceive(NotificationCenter.default.publisher(for: .demoQuestion)) { n in
            guard ask.sessionId.hasPrefix("demo-"), let c = n.object as? String else { return }
            if c == "send" { next() } else if let i = Int(c.dropFirst(5)), q.options.indices.contains(i) { select(i) }
        }
    }

    private func select(_ i: Int) {
        var set = picked[page] ?? []
        if q.multi {
            if set.contains(i) { set.remove(i) } else { set.insert(i) }
        } else {
            set = [i]
        }
        picked[page] = set
    }

    /// اختيار واحد: علامة صح في الآخر. أكتر من اختيار: دايرة في الأول (زي وضع التعديل في iOS)
    private func option(_ i: Int, _ o: AskQuestion.Option) -> some View {
        let on = picked[page]?.contains(i) ?? false
        return Button { select(i) } label: {
            HStack(spacing: 10) {
                if !q.multi {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                        .opacity(on ? 1 : 0)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(o.label)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                    if !o.detail.isEmpty {
                        Text(o.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                if q.multi {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(on ? Theme.blue : Theme.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: AskQuestion.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func next() {
        guard answered else { return }
        if !isLast { page += 1; return }
        var answers: [String: String] = [:]
        for (n, question) in ask.questions.enumerated() {
            let labels = (picked[n] ?? []).sorted().map { question.options[$0].label }
            answers[question.text] = labels.joined(separator: ", ")
        }
        m.claude.answer(ask, .answers(answers))
    }

    private func capsule(_ title: String, primary: Bool, _ action: @escaping () -> Void) -> some View {
        let on = !primary || answered
        return Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primary ? (on ? Color.white : Theme.tertiary) : .white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(primary && on ? Theme.blue : Theme.fill))
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    /// سكريبت الـ demo بيختار في كارت السؤال
    static let demoQuestion = Notification.Name("NotchRobotDemoQuestion")
}

extension AskQuestion {
    static let rowHeight: CGFloat = 34
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [glow.opacity(0.5), .purple.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    /// التصميم معمول يمين لشمال بإيدينا جوه LTR؛ في الإنجليزي بنعكسه
    func langDirection() -> some View {
        environment(\.layoutDirection, Lang.current == .en ? .rightToLeft : .leftToRight)
    }
    /// حاجات ترتيبها ثابت في اللغتين (أزرار التشغيل، شريط التبويبات)
    func fixedDirection() -> some View { environment(\.layoutDirection, .leftToRight) }
}

// MARK: - النوتش المفتوح

struct ExpandedContent: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            // الشكل الهادي من غير الشخصية، إلا في الترحيب
            if m.skin != .minimal || m.onboarding != nil {
                RobotFace(m: m, e: m.eyes, s: 84)
                    .contentShape(Rectangle())
                    .onTapGesture { m.poke() }
                    .help(tr("دوس عليا 🤖", "Poke me 🤖"))
            }

            VStack(alignment: .trailing, spacing: 8) {
                if let page = m.onboarding {
                    OnboardingView(m: m, page: page)
                        .id(page)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else {
                    TabBar(m: m)
                    Group {
                        switch m.tab {
                        case .home: HomeTab(m: m)
                        case .music: MusicTab(m: m)
                        case .claude: ClaudeTab(m: m)
                        case .clipboard: ClipboardTab(m: m)
                        case .shelf: ShelfTab(m: m)
                        case .timer: TimerTab(m: m)
                        case .style: StyleTab(m: m)
                        case .settings: SettingsTab(m: m)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .id(m.tab)
                    .transition(tabTransition)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.95), value: m.tab)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: m.onboarding)
            .clipped()
            .langDirection()
        }
        .padding(.horizontal, 30)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

/// زي الـ segmented control في iOS: كبسولة واحدة والمختار جواها أفتح
extension ExpandedContent {
    /// المحتوى بيتزحلق شوية صغيرين من ناحية التبويب الجديد مع fade. الترتيب ثابت شمال ليمين
    /// في اللغتين، بس العمود معكوس في الإنجليزي فالإزاحة بتتعكس معاه
    var tabTransition: AnyTransition {
        let d: CGFloat = 14
        let x = (m.tabForward == (Lang.current == .ar)) ? d : -d
        return .asymmetric(insertion: .offset(x: x).combined(with: .opacity),
                           removal: .offset(x: -x).combined(with: .opacity))
    }
}

struct TabBar: View {
    @ObservedObject var m: NotchModel
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { m.tab = t } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 30, height: 20)
                        .foregroundStyle(m.tab == t ? Color.white : Theme.secondary)
                        .background {
                            if m.tab == t {
                                Capsule().fill(Theme.selected)
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if t == .claude, !m.claude.waiting.isEmpty {
                                Circle().fill(claudeOrange).frame(width: 6, height: 6)
                            } else if t == .settings, m.updates.latest != nil {
                                Circle().fill(Theme.blue).frame(width: 6, height: 6)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.fill))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: m.tab)
        .fixedDirection()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct HomeTab: View {
    @ObservedObject var m: NotchModel

    private var greeting: String {
        switch Calendar.current.component(.hour, from: m.now) {
        case 5..<12: return tr("صباح الخير ☀️", "Good morning ☀️")
        case 12..<17: return tr("يومك سعيد 🌤", "Good afternoon 🌤")
        case 17..<22: return tr("مساء الخير 🌙", "Good evening 🌙")
        default: return tr("لسه صاحي؟ 🌌", "Still up? 🌌")
        }
    }

    private static let fmts: [Lang: (time: DateFormatter, date: DateFormatter)] = [
        .ar: (make("h:mm a", "ar_EG"), make("EEEE، d MMMM", "ar_EG")),
        .en: (make("h:mm a", "en_US"), make("EEEE, MMMM d", "en_US")),
    ]
    private static var timeFmt: DateFormatter { fmts[Lang.current]!.time }
    private static var dateFmt: DateFormatter { fmts[Lang.current]!.date }
    private static func make(_ f: String, _ locale: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: locale)
        d.dateFormat = f
        return d
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(m.speech ?? greeting)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(m.speech == nil ? Color.white.opacity(0.7) : glow)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let b = m.battery {
                    HStack(spacing: 4) {
                        Text("\(b)%").font(.system(size: 11, weight: .semibold))
                        Image(systemName: m.charging ? "battery.100.bolt"
                              : b > 75 ? "battery.100" : b > 50 ? "battery.75"
                              : b > 25 ? "battery.50" : "battery.25")
                    }
                    .foregroundStyle(b <= 20 && !m.charging ? Theme.red : Theme.green)
                }
                Text(Self.timeFmt.string(from: m.now))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Text(Self.dateFmt.string(from: m.now))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                if let s = m.claude.sessions.first {
                    Label(m.claude.sessions.count > 1 ? tr("\(m.claude.sessions.count) جلسات", "\(m.claude.sessions.count) sessions") : s.project,
                          systemImage: "sparkle")
                        .foregroundStyle(claudeOrange)
                        .onTapGesture { m.tab = .claude }
                }
                if let i = m.media.info {
                    Label(i.title, systemImage: i.playing ? "play.fill" : "pause.fill")
                        .foregroundStyle(glow)
                        .onTapGesture { m.tab = .music }
                }
            }
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.top, 2)
        }
        .animation(.easeOut(duration: 0.25), value: m.speech)
    }
}

struct MusicTab: View {
    @ObservedObject var m: NotchModel
    /// مكان الصباع على الشريط (من 0 لـ 1) وانت بتسحب
    @State private var scrub: Double?

    var body: some View {
        if let i = m.media.info {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(i.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        Text(i.artist).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                        if let app = m.media.appName {
                            HStack(spacing: 4) {
                                Text(app)
                                if let icon = m.media.appIcon {
                                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                                }
                            }
                            .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .lineLimit(1)
                    Artwork(image: m.media.artwork, size: 56, radius: 10)
                }
                if i.duration > 0 {
                    // وانت بتسحب بنعرض مكان صباعك، ولما تسيب بنبعت التقديم
                    let pos = scrub.map { $0 * i.duration } ?? i.position(at: m.now)
                    let en = Lang.current == .en
                    HStack(spacing: 6) {
                        Text(clock(en ? pos : i.duration))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15))
                                Capsule().fill(scrub == nil ? m.accent : .white)
                                    .frame(width: g.size.width * min(1, pos / i.duration))
                            }
                            .frame(height: scrub == nil ? 4 : 8)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { v in scrub = min(max(0, v.location.x / g.size.width), 1) }
                                .onEnded { v in
                                    m.media.seek(to: min(max(0, v.location.x / g.size.width), 1) * i.duration)
                                    scrub = nil
                                })
                            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: scrub == nil)
                        }
                        .frame(height: 14)
                        Text(clock(en ? i.duration : pos))
                    }
                    .fixedDirection()
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 22) {
                    control("backward.fill") { m.media.send(.previous) }
                    control(i.playing ? "pause.fill" : "play.fill", size: 18) { m.media.send(.toggle) }
                    control("forward.fill") { m.media.send(.next) }
                }
                .fixedDirection()
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                Text(tr("مفيش حاجة شغالة 🎧", "Nothing playing 🎧")).font(.system(size: 14, weight: .bold))
                Text(tr("شغّل أغنية من Spotify أو Music أو YouTube وهتظهر هنا", "Play something on Spotify, Music, or YouTube and it shows up here"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            .foregroundStyle(.white)
            .padding(.top, 14)
        }
    }

    private func control(_ icon: String, size: CGFloat = 14, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain)
    }
}

struct ClaudeTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if m.claude.usage5h != nil || m.claude.usageWeek != nil { UsageRow(m: m) }
            sessions
        }
    }

    @ViewBuilder private var sessions: some View {
        if m.claude.sessions.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text(tr("مفيش جلسات كلود مفتوحة ✳️", "No Claude sessions open ✳️")).font(.system(size: 14, weight: .bold))
                Text(m.claude.hooksInstalled
                     ? tr("افتح claude في التيرمنال وهيظهر هنا", "Run claude in a terminal and it shows up here")
                     : tr("الـ hooks مش متركّبة في ~/.claude/settings.json", "Hooks aren't installed in ~/.claude/settings.json"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            .foregroundStyle(.white)
            .padding(.top, 14)
        } else {
            VStack(spacing: 6) {
                ForEach(m.claude.sessions.prefix(4)) { s in
                    SessionRow(s: s, now: m.now)
                        .contentShape(Rectangle())
                        .onTapGesture { m.claude.focus(s) }
                        .contextMenu { Button(tr("شيلها من القايمة", "Remove from list")) { m.claude.remove(s) } }
                }
            }
        }
    }
}

/// استهلاك الحساب كله (مش الجلسة): نافذة الـ 5 ساعات والأسبوع — لمشتركين Pro و Max
struct UsageRow: View {
    @ObservedObject var m: NotchModel

    private static let fmts: [Lang: (time: DateFormatter, day: DateFormatter)] = [
        .ar: (make("h:mm", "ar_EG"), make("EEEE", "ar_EG")),
        .en: (make("h:mm a", "en_US"), make("EEE", "en_US")),
    ]
    private static func make(_ f: String, _ locale: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: locale)
        d.dateFormat = f
        return d
    }

    var body: some View {
        let c = m.claude
        let f = Self.fmts[Lang.current]!
        // الأرقام بتتحدّث بس وفيه جلسة شغالة، فلو قديمة بنبهتها
        let stale = c.usageUpdated.map { m.now.timeIntervalSince($0) > 30 * 60 } ?? true
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let w = c.usageWeek { meter(tr("الأسبوع", "Week"), w, f.day) }
            if let w = c.usage5h { meter(tr("5 ساعات", "5h"), w, f.time) }
        }
        .opacity(stale ? 0.5 : 1)
        .help(tr("استهلاك حسابك من الـ status line بتاع كلود كود", "Your account usage, from Claude Code's status line"))
    }

    private func meter(_ title: String, _ w: UsageWindow, _ fmt: DateFormatter) -> some View {
        let color: Color = w.percent < 70 ? Theme.green : w.percent < 90 ? Theme.orange : Theme.red
        return HStack(spacing: 5) {
            Text("↻ " + fmt.string(from: w.resetsAt)).foregroundStyle(Theme.tertiary)
            Text("\(Int(w.percent.rounded()))%").foregroundStyle(color).monospacedDigit()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color).frame(width: g.size.width * min(1, w.percent / 100))
                }
            }
            .frame(width: 28, height: 4)
            .fixedDirection()
            Text(title).foregroundStyle(Theme.secondary)
        }
        .font(.system(size: 10, weight: .semibold))
        .lineLimit(1)
    }
}

struct SessionRow: View {
    let s: ClaudeSession
    let now: Date

    private var chip: (String, Color) {
        switch s.state {
        case .working: return (tr("شغال", "Working"), claudeOrange)
        case .waiting: return (tr("مستنيك", "Waiting"), Theme.yellow)
        case .done: return (tr("خلص", "Done"), Theme.green)
        case .idle: return (tr("جاهز", "Ready"), .gray)
        case .failed: return ("error", Theme.red)
        }
    }

    private var ago: String {
        let d = Int(now.timeIntervalSince(s.updated))
        if d < 60 { return tr("دلوقتي", "now") }
        if d < 3600 { return tr("\(d / 60)د", "\(d / 60)m") }
        return tr("\(d / 3600)س", "\(d / 3600)h")
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(ago).font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(s.project).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                if let p = s.progress {
                    Text("\(p.done)/\(p.total) · \(s.activeTask ?? s.detail)")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                } else {
                    Text(s.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            Text(chip.0)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(chip.1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(chip.1.opacity(0.18)))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(alignment: .bottom) {
            // شريط تقدم المهام في أسفل الكارت
            if let p = s.progress {
                GeometryReader { g in
                    Capsule().fill(claudeOrange)
                        .frame(width: g.size.width * CGFloat(p.done) / CGFloat(max(p.total, 1)))
                }
                .frame(height: 2)
                .fixedDirection()
                .padding(.horizontal, 12)
                .padding(.bottom, 1)
            }
        }
        .help(tr("اضغط عشان تروح للتيرمنال", "Click to jump to the terminal"))
    }
}

struct ClipboardTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        let c = m.clipboard
        if c.visible.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text(tr("الكليب بورد فاضي 📋", "Clipboard is empty 📋")).font(.system(size: 14, weight: .bold))
                Text(tr("أي حاجة تعملها copy هتتحفظ هنا (آخر 20)، وتقدر تثبّت اللي بتستخدمه كتير", "Anything you copy shows up here (last 20). Pin the ones you use a lot"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(.white)
            .padding(.top, 14)
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(c.visible) { item in row(item, c) }
            }
        }
    }

    private func row(_ item: ClipItem, _ c: ClipboardStore) -> some View {
        let pinned = c.isPinned(item)
        let copied = c.lastCopied == item.id
        return HStack(spacing: 8) {
            Group {
                if copied {
                    Text(tr("اتنسخ ✓", "Copied ✓")).foregroundStyle(Theme.green)
                } else if pinned {
                    Image(systemName: "pin.fill").foregroundStyle(Theme.orange)
                } else {
                    Text(ago(item.date)).foregroundStyle(.white.opacity(0.35))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .frame(width: 46, alignment: .leading)
            if let a = action(item.kind) {
                Button { c.act(item) } label: {
                    Text(a)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.blue.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            Text(item.preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            kindMark(item.kind)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
        .contentShape(Rectangle())
        .onTapGesture { c.copy(item) }
        .contextMenu {
            Button(tr("انسخ", "Copy")) { c.copy(item) }
            Button(pinned ? tr("شيل التثبيت", "Unpin") : tr("ثبّت", "Pin")) { c.togglePin(item) }
                .disabled(!pinned && c.pinned.count >= ClipboardStore.maxPins)
            Button(tr("امسح", "Delete")) { c.remove(item) }
            Divider()
            Button(tr("امسح الكل (المثبّت بيفضل)", "Clear all (keeps pinned)")) { c.clear() }
        }
        .help(String(item.text.prefix(500)))
    }

    /// زرار صغير على حسب النوع
    private func action(_ k: ClipKind) -> String? {
        switch k {
        case .text: return nil
        case .link: return tr("افتح", "Open")
        case .email: return tr("ابعت", "Mail")
        case .color: return "rgb()"
        case .json: return tr("رتّب", "Format")
        case .path: return "Finder"
        }
    }

    @ViewBuilder private func kindMark(_ k: ClipKind) -> some View {
        switch k {
        case .text: EmptyView()
        case let .color(col, _):
            Circle().fill(col).overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1)).frame(width: 12, height: 12)
        default:
            Image(systemName: k.icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
    }

    private func ago(_ d: Date) -> String {
        let s = Int(m.now.timeIntervalSince(d))
        if s < 60 { return tr("دلوقتي", "now") }
        if s < 3600 { return tr("\(s / 60)د", "\(s / 60)m") }
        return tr("\(s / 3600)س", "\(s / 3600)h")
    }
}

struct ShelfTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        let shelf = m.shelf
        if m.dragging {
            HStack(spacing: 10) {
                DropZone(icon: "dot.radiowaves.left.and.right", title: tr("ابعته AirDrop", "AirDrop it")) { urls in
                    ShelfStore.airDrop(urls)
                }
                DropZone(icon: "tray.and.arrow.down.fill", title: tr("حطه على الرف", "Put it on the shelf")) { urls in
                    shelf.add(urls)
                }
            }
            .padding(.top, 4)
        } else if shelf.items.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text(tr("الرف فاضي 🗂", "Shelf is empty 🗂")).font(.system(size: 14, weight: .bold))
                Text(tr("اسحب أي ملف على النوتش وسيبه هنا، أو ابعته AirDrop على طول", "Drag any file onto the notch to keep it here, or AirDrop it right away"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.trailing)
                ScreenshotButton(m: m).padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(.top, 14)
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 12) {
                    Button { shelf.clear() } label: { Text(tr("مسح", "Clear")) }
                        .foregroundStyle(Theme.tertiary)
                    Button { ShelfStore.airDrop(shelf.items) } label: {
                        Label(tr("AirDrop الكل", "AirDrop all"), systemImage: "dot.radiowaves.left.and.right")
                    }
                    .foregroundStyle(Theme.blue)
                    ScreenshotButton(m: m)
                    Spacer()
                    Text(tr("\(shelf.items.count) ملف", "\(shelf.items.count) files")).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                HStack(spacing: 8) {
                    if shelf.items.count > 4 {
                        Text("+\(shelf.items.count - 4)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                            .help(tr("الباقي في Finder: كليك يمين ← وريهولي", "The rest: right-click → Show in Finder"))
                    }
                    ForEach(shelf.items.prefix(4).reversed(), id: \.self) { u in ShelfItem(url: u, shelf: shelf) }
                }
                Text(tr("اسحب الملف من هنا لأي مكان، أو كليك يمين للاختيارات", "Drag a file out from here, or right-click for options"))
                    .font(.system(size: 9)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

/// سكرين شوت لحتة من الشاشة وتتحط على الرف
struct ScreenshotButton: View {
    @ObservedObject var m: NotchModel
    var body: some View {
        Button { m.screenshot() } label: {
            HStack(spacing: 5) {
                KeyCaps(keys: Hotkeys.screenshotKeys)
                Label(tr("سكرين شوت", "Screenshot"), systemImage: "camera.viewfinder")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.blue)
        }
        .buttonStyle(.plain)
        .help(tr("حدد حتة من الشاشة (Space = شباك كامل)، وهتتحط هنا وتتنسخ", "Select part of the screen (Space = whole window); it lands here and on the clipboard"))
    }
}

/// اختصار كيبورد مرسوم أزرار صغيرة
struct KeyCaps: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(keys, id: \.self) { k in
                Text(k)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 14, minHeight: 14)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.fill))
            }
        }
        .fixedDirection()
    }
}

struct ShelfItem: View {
    let url: URL
    let shelf: ShelfStore

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: ShelfStore.icon(url)).resizable().frame(width: 40, height: 40)
            Text(url.lastPathComponent)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(width: 64, height: 70)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button(tr("افتح", "Open")) { NSWorkspace.shared.open(url) }
            Button(tr("وريهولي في Finder", "Show in Finder")) { ShelfStore.reveal([url]) }
            Button(tr("ابعته AirDrop", "AirDrop it")) { ShelfStore.airDrop([url]) }
            Divider()
            Button(tr("شيله من الرف", "Remove from shelf")) { shelf.remove(url) }
        }
        .help(url.path)
    }
}

/// مكان تسيب فيه الملف وهو بيتسحب
struct DropZone: View {
    let icon: String
    let title: String
    let action: ([URL]) -> Void
    @State private var over = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(over ? Color.white : Theme.blue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(over ? Theme.blue : Theme.blue.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.blue.opacity(over ? 0 : 0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .scaleEffect(over ? 1.03 : 1)
        .animation(.spring(response: 0.25), value: over)
        .onDrop(of: [.fileURL], isTargeted: $over) { providers in
            ShelfStore.log("drop على \(title): \(providers.count)")
            ShelfStore.load(providers) { urls in if !urls.isEmpty { action(urls) } }
            return true
        }
    }
}

struct TimerTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Button { m.resetTimer() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.fill))
                    }
                    Button {
                        m.timerEnd == nil ? m.startTimer() : m.pauseTimer()
                    } label: {
                        Image(systemName: m.timerEnd == nil ? "play.fill" : "pause.fill")
                            .frame(width: 36, height: 36)
                            .background(Circle().fill((m.timerEnd == nil ? Theme.green : Theme.orange).opacity(0.25)))
                            .foregroundStyle(m.timerEnd == nil ? Theme.green : Theme.orange)
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .fixedDirection()

                Text(clock(m.timerLeft))
                    .font(.system(size: 38, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(m.timerEnd == nil ? Theme.secondary : .white)
            }
            HStack(spacing: 6) {
                ForEach([5.0, 15, 25, 50], id: \.self) { min in
                    Button { m.startTimer(minutes: min) } label: {
                        Text(tr("\(Int(min)) د", "\(Int(min)) min"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(m.timerTotal == min * 60 ? Theme.selected : Theme.fill))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedDirection()
            Text(tr("بومودورو 🍅 ركّز وأنا هنبهك", "Pomodoro 🍅 focus and I'll ping you")).font(.system(size: 10))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

struct SettingsTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            row(tr("الأصوات", "Sounds"), isOn: $m.soundsOn)
            if m.soundsOn {
                ForEach(SoundEvent.allCases, id: \.self) { e in soundRow(e) }
            }
            row(tr("يفتح مع تشغيل الماك", "Open at login"), isOn: Binding(get: { m.launchAtLogin }, set: { m.launchAtLogin = $0 }))
            row(tr("يحدّث نفسه لوحده", "Update automatically"), isOn: Binding(get: { m.updates.auto }, set: { m.updates.auto = $0 }))
            HStack(spacing: 4) {
                HStack(spacing: 0) {
                    langButton(.en, "English")
                    langButton(.ar, "العربي")
                }
                .padding(2)
                .background(Capsule().fill(Theme.fill))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: m.lang)
                Spacer(minLength: 0)
                Text(tr("اللغة", "Language")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 6) {
                if let v = m.updates.latest { updateButton(v) }
                Spacer(minLength: 0)
                Text("v\(UpdateStore.current)").foregroundStyle(Theme.tertiary)
                Text("·").foregroundStyle(Theme.tertiary)
                Text(m.claude.hooksInstalled ? tr("متوصل بكلود كود", "Connected to Claude Code") : tr("مش متوصل بكلود كود", "Not connected to Claude Code"))
                Circle().fill(m.claude.hooksInstalled ? Theme.green : Theme.red).frame(width: 7, height: 7)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary)
            Button { NSApp.terminate(nil) } label: {
                Label(tr("قفل روبو", "Quit Robo"), systemImage: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.red)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func updateButton(_ v: String) -> some View {
        switch m.updates.phase {
        case let .downloading(f):
            HStack(spacing: 5) {
                ProgressRing(progress: f, color: Theme.blue)
                Text(tr("بينزّل v\(v)", "Downloading v\(v)"))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.blue)
        case .ready:
            Text(tr("بيتسطّب…", "Installing…")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.blue)
        case .idle, .failed:
            Button { m.updates.install() } label: {
                Label(tr("حدّث لـ v\(v)", "Update to v\(v)"), systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.blue))
            }
            .buttonStyle(.plain)
            .help(tr("بينزّله من GitHub ويركّبه مكان النسخة دي ويفتحه تاني", "Downloads it from GitHub, replaces this copy, and reopens"))
        }
    }

    private func langButton(_ l: Lang, _ title: String) -> some View {
        Button { m.lang = l } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(m.lang == l ? Color.white : Theme.secondary)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(m.lang == l ? Theme.selected : .clear))
        }
        .buttonStyle(.plain)
    }

    /// دوسة = الصوت اللي بعده (وبيشغّله عشان تسمعه)
    private func soundRow(_ e: SoundEvent) -> some View {
        let cur = m.sound(e)
        return HStack(spacing: 6) {
            Button {
                let all = SoundEvent.choices
                let next = all[((all.firstIndex(of: cur) ?? -1) + 1) % all.count]
                m.setSound(e, next)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: cur.isEmpty ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    Text(cur.isEmpty ? tr("من غير", "None") : cur)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(cur.isEmpty ? Theme.tertiary : Theme.blue)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.fill))
            }
            .buttonStyle(.plain)
            .fixedDirection()
            .help(tr("دوس عشان تغيّر الصوت", "Click to change the sound"))
            Text(e.title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Capsule()
                .fill(isOn.wrappedValue ? Theme.green : Theme.track)
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2)
                }
                .fixedDirection()
                .onTapGesture { withAnimation(.spring(response: 0.25)) { isOn.wrappedValue.toggle() } }
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
        }
    }
}


// MARK: - الشكل

/// كبسولة اختيارات زي الـ segmented control
struct Chips<T: Hashable>: View {
    let items: [T]
    let selected: T
    let title: (T) -> String
    let pick: (T) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { i in
                Button { pick(i) } label: {
                    Text(title(i))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(i == selected ? Color.white : Theme.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(i == selected ? Theme.selected : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.fill))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

/// الشخصية والشكل واللون (في تبويب الشكل وفي الترحيب)
struct StylePickers: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            line(tr("الشخصية", "Character")) {
                Chips(items: Buddy.allCases, selected: m.buddy, title: \.title) { b in m.buddy = b; m.flash(.happy, for: 1.2) }
            }
            line(tr("النوتش", "Notch")) {
                Chips(items: Skin.allCases, selected: m.skin, title: \.title) { m.skin = $0 }
            }
            line(tr("اللون", "Color")) {
                HStack(spacing: 7) {
                    ForEach(Accent.allCases, id: \.self) { a in
                        Button { m.accentChoice = a } label: {
                            Circle().fill(a.color)
                                .frame(width: 15, height: 15)
                                .padding(2.5)
                                .overlay(Circle().stroke(.white, lineWidth: m.accentChoice == a ? 1.5 : 0))
                                .shadow(color: a.color.opacity(0.6), radius: m.accentChoice == a ? 4 : 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.spring(response: 0.25), value: m.accentChoice)
            }
        }
    }

    private func line<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) {
            content().fixedDirection()
            Spacer(minLength: 0)
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
    }
}

struct StyleTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            StylePickers(m: m)
            Button { m.startOnboarding() } label: {
                Label(tr("اعرض الترحيب تاني", "Show the welcome again"), systemImage: "hand.wave.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - الترحيب

/// أول مرة تفتح التطبيق: أربع صفحات بتعرّفك على روبو وتختار شكله وتجهّز الحاجات اللي محتاجة إذن
struct OnboardingView: View {
    @ObservedObject var m: NotchModel
    let page: Int
    static let pages = 4

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Group {
                switch page {
                case 0: welcome
                case 1: features
                case 2: style
                default: setup
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            nav
        }
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(t).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Text(sub).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        VStack(alignment: .trailing, spacing: 10) {
            title(tr("أهلاً! أنا روبو 👋", "Hi! I'm Robo 👋"),
                  tr("بعيش في النوتش بتاعتك. قرّب الماوس فوق وهتفتح، وابعد وهتقفل.",
                     "I live in your notch. Move the mouse up there to open me, move away to close."))
            hint("hand.draw.fill", tr("اسحب بصباعين يمين وشمال عشان تقلّب التبويبات", "Swipe with two fingers to switch tabs"))
            hint("tray.and.arrow.down.fill", tr("اسحب أي ملف على النوتش وهيتحط على الرف", "Drag any file onto the notch to shelve it"))
        }
    }

    private var features: some View {
        VStack(alignment: .trailing, spacing: 8) {
            title(tr("بعمل إيه؟", "What I do"), tr("كل حاجة في مكان واحد فوق", "Everything in one place, up top"))
            Grid(horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    feature("music.note", glow, tr("المزيكا", "Music"))
                    feature("sparkle", claudeOrange, tr("كلود كود", "Claude Code"))
                }
                GridRow {
                    feature("tray.fill", Theme.blue, tr("الرف و AirDrop", "Shelf & AirDrop"))
                    feature("doc.on.clipboard", Theme.green, tr("كليب بورد ذكي", "Smart clipboard"))
                }
                GridRow {
                    feature("battery.75", Theme.green, tr("البطارية", "Battery"))
                    feature("timer", Theme.orange, tr("بومودورو", "Pomodoro"))
                }
            }
        }
    }

    private var style: some View {
        VStack(alignment: .trailing, spacing: 10) {
            title(tr("اختار شكلي 🎨", "Pick my look 🎨"), tr("تقدر تغيّره بعدين من تبويب الشكل", "You can change it later in the style tab"))
            StylePickers(m: m)
        }
    }

    private var setup: some View {
        VStack(alignment: .trailing, spacing: 8) {
            title(tr("آخر حاجة ⚙️", "One last thing ⚙️"), tr("دي الحاجات اللي ممكن تحتاج إذن", "These might need your permission"))
            hint("camera.viewfinder", tr("سكرين شوت على الرف. أول مرة الماك هيطلب إذن Screen Recording",
                                         "Screenshot to the shelf. macOS asks for Screen Recording the first time"),
                 keys: Hotkeys.screenshotKeys)
            hint(m.claude.hooksInstalled ? "checkmark.circle.fill" : "sparkle",
                 m.claude.hooksInstalled ? tr("متوصل بكلود كود ✓", "Connected to Claude Code ✓")
                                         : tr("شغّل ./install-hooks.sh عشان توصّلني بكلود كود", "Run ./install-hooks.sh to connect me to Claude Code"),
                 color: m.claude.hooksInstalled ? Theme.green : claudeOrange)
            HStack(spacing: 7) {
                Spacer(minLength: 0)
                Capsule()
                    .fill(m.launchAtLogin ? Theme.green : Theme.track)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: m.launchAtLogin ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    }
                    .fixedDirection()
                    .onTapGesture { withAnimation(.spring(response: 0.25)) { m.launchAtLogin.toggle() } }
                Text(tr("افتح معاك لما الماك يشتغل", "Open me at login")).font(.system(size: 11)).foregroundStyle(.white)
                Image(systemName: "power").font(.system(size: 11, weight: .semibold)).foregroundStyle(glow).frame(width: 16)
            }
        }
    }

    private func hint(_ icon: String, _ text: String, color: Color = glow, keys: [String]? = nil) -> some View {
        HStack(alignment: .top, spacing: 7) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if let keys { KeyCaps(keys: keys) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(color).frame(width: 16)
        }
    }

    private func feature(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            AppGlyph(icon: icon, color: color, size: 22)
        }
    }

    private var nav: some View {
        let last = page == Self.pages - 1
        return HStack(spacing: 8) {
            if !last {
                Button { m.finishOnboarding() } label: {
                    Text(tr("تخطّي", "Skip")).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(0..<Self.pages, id: \.self) { i in
                    Capsule().fill(i == page ? Color.white : Theme.tertiary)
                        .frame(width: i == page ? 14 : 5, height: 5)
                }
            }
            .fixedDirection()
            .animation(.spring(response: 0.3), value: page)
            Spacer(minLength: 0)
            if page > 0 {
                pill(tr("السابق", "Back"), primary: false) { m.onboarding = page - 1 }
            }
            pill(last ? tr("يلا بينا 🚀", "Let's go 🚀") : tr("التالي", "Next"), primary: true) {
                if last { m.finishOnboarding() } else { m.onboarding = page + 1 }
            }
        }
    }

    private func pill(_ t: String, primary: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Capsule().fill(primary ? Theme.blue : Theme.fill))
        }
        .buttonStyle(.plain)
    }
}
