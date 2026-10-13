import SwiftUI

// MARK: - شكل النوتش

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + topRadius, y: r.minY + topRadius),
                       control: CGPoint(x: r.minX + topRadius, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + topRadius, y: r.maxY - bottomRadius))
        p.addQuadCurve(to: CGPoint(x: r.minX + topRadius + bottomRadius, y: r.maxY),
                       control: CGPoint(x: r.minX + topRadius, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topRadius - bottomRadius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - topRadius, y: r.maxY - bottomRadius),
                       control: CGPoint(x: r.maxX - topRadius, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topRadius, y: r.minY + topRadius))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.maxX - topRadius, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Root

struct NotchView: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        let shape = NotchShape(topRadius: m.expanded ? 14 : 6, bottomRadius: m.expanded ? 28 : 12)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                if m.expanded {
                    ExpandedContent(m: m)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                } else {
                    CollapsedContent(m: m).transition(.opacity)
                }
            }
            .frame(width: m.size.width, height: m.size.height)
            .clipShape(shape)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                ShelfStore.log("drop على النوتش: \(providers.count)")
                ShelfStore.load(providers) { urls in m.shelf.add(urls) }
                return true
            }
            .shadow(color: m.media.isPlaying ? m.accent.opacity(m.expanded ? 0.45 : 0.6)
                                             : .black.opacity(m.expanded ? 0.5 : 0),
                    radius: m.media.isPlaying ? 10 : 12, y: m.media.isPlaying ? 2 : 4)
            .animation(.easeInOut(duration: 0.6), value: m.accent)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: m.expanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: m.size)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - النوتش المقفول (Live Activities)

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
                }
            } else if c.recentlyDone {
                AnimatedSymbol(name: "checkmark.circle.fill", color: .green, motion: .still)
            } else {
                // جلسة مفتوحة بس مستنية أمر منك
                AnimatedSymbol(name: "sparkle", color: claudeOrange.opacity(0.55), motion: .still)
                if c.sessions.count > 1 {
                    Text("\(c.sessions.count)").foregroundStyle(claudeOrange.opacity(0.55))
                }
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
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
                    .frame(maxWidth: .infinity)
                if m.rightWingWidth > 0 {
                    HStack(spacing: 6) {
                        if m.voice.active { VoiceBadge(v: m.voice) }
                        if m.hasClaudeBadge { ClaudeBadge(m: m) }
                        if m.timerActive {
                            Text(clock(m.timerLeft))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(m.timerEnd == nil ? .white.opacity(0.5) : glow)
                                .frame(width: 44)
                        }
                        if m.media.isPlaying { EqualizerBars(color: m.accent).frame(width: 20) }
                    }
                    .frame(width: m.rightWingWidth, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: m.baseSize.height)

            if let ask = m.claude.asks.first, !ask.questions.isEmpty {
                QuestionCard(m: m, ask: ask)
                    .id(ask.id)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let ask = m.claude.asks.first {
                PermissionCard(m: m, ask: ask)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let b = m.banner {
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Text(b.text).lineLimit(1)
                        Image(systemName: b.icon)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(b.color)
                    if let d = b.detail {
                        Text(d)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(height: b.detail == nil ? 30 : 54)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .id(b.id)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: m.banner)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: m.claude.asks)
    }
}

/// كلود مستني موافقتك — الرد بيتكتب بس لما تدوس زرار
struct PermissionCard: View {
    @ObservedObject var m: NotchModel
    let ask: PermissionAsk

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 6) {
                if m.claude.asks.count > 1 {
                    Text("+\(m.claude.asks.count - 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(claudeOrange.opacity(0.25)))
                        .foregroundStyle(claudeOrange)
                }
                Spacer(minLength: 0)
                Text("كلود عايز يستخدم \(ask.tool) · \(ask.project)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(claudeOrange)
                    .lineLimit(1)
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(claudeOrange)
            }
            Text(ask.detail.isEmpty ? ask.tool : ask.detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 8) {
                button("التيرمنال", "arrow.up.forward.app", .white.opacity(0.12), .white) {
                    m.claude.answer(ask, .terminal)
                }
                Spacer(minLength: 0)
                button("ارفض", "xmark", Color.red.opacity(0.25), .red) { m.claude.answer(ask, .deny) }
                button("وافق", "checkmark", Color.green, .black) { m.claude.answer(ask, .allow) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func button(_ title: String, _ icon: String, _ bg: Color, _ fg: Color,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: icon)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(bg))
        }
        .buttonStyle(.plain)
    }
}

/// كلود بيسألك (AskUserQuestion): سؤال في كل صفحة، والإجابات بتتبعت مرة واحدة في الآخر
struct QuestionCard: View {
    @ObservedObject var m: NotchModel
    let ask: PermissionAsk
    @State private var page = 0
    @State private var picked: [Int: Set<Int>] = [:]

    private var q: AskQuestion { ask.questions[page] }
    private var isLast: Bool { page == ask.questions.count - 1 }
    private var answered: Bool { !(picked[page] ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 6) {
                if m.claude.asks.count > 1 {
                    Text("+\(m.claude.asks.count - 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(claudeOrange.opacity(0.25)))
                        .foregroundStyle(claudeOrange)
                }
                if ask.questions.count > 1 {
                    Text("\(page + 1)/\(ask.questions.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                Text("\(q.header.isEmpty ? "كلود بيسألك" : q.header) · \(ask.project)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(claudeOrange)
                    .lineLimit(1)
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(claudeOrange)
            }
            Text(q.text + (q.multi ? "  (اختار أكتر من واحدة)" : ""))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(spacing: 4) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in option(i, o) }
            }
            HStack(spacing: 8) {
                pill("التيرمنال", "arrow.up.forward.app", .white.opacity(0.12), .white) {
                    m.claude.answer(ask, .terminal)
                }
                Spacer(minLength: 0)
                if page > 0 {
                    pill("السابق", "chevron.right", .white.opacity(0.12), .white) { page -= 1 }
                }
                pill(isLast ? "ابعت" : "التالي", isLast ? "paperplane.fill" : "chevron.left",
                     answered ? Color.green : .white.opacity(0.1), answered ? .black : .white.opacity(0.4)) {
                    next()
                }
                .disabled(!answered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func option(_ i: Int, _ o: AskQuestion.Option) -> some View {
        let on = picked[page]?.contains(i) ?? false
        return Button {
            var set = picked[page] ?? []
            if q.multi {
                if on { set.remove(i) } else { set.insert(i) }
            } else {
                set = [i]
            }
            picked[page] = set
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(o.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if !o.detail.isEmpty {
                        Text(o.detail)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                Image(systemName: q.multi ? (on ? "checkmark.square.fill" : "square")
                                          : (on ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 13))
                    .foregroundStyle(on ? claudeOrange : .white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .frame(height: AskQuestion.rowHeight)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(on ? claudeOrange.opacity(0.22) : Color.white.opacity(0.07)))
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

    private func pill(_ title: String, _ icon: String, _ bg: Color, _ fg: Color,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: icon)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(bg))
        }
        .buttonStyle(.plain)
    }
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
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// MARK: - النوتش المفتوح

struct ExpandedContent: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            RobotFace(m: m, e: m.eyes, s: 84)
                .contentShape(Rectangle())
                .onTapGesture { m.poke() }
                .help("دوس عليا 🤖")

            VStack(alignment: .trailing, spacing: 8) {
                TabBar(m: m)
                Group {
                    switch m.tab {
                    case .home: HomeTab(m: m)
                    case .music: MusicTab(m: m)
                    case .claude: ClaudeTab(m: m)
                    case .clipboard: ClipboardTab(m: m)
                    case .shelf: ShelfTab(m: m)
                    case .timer: TimerTab(m: m)
                    case .settings: SettingsTab(m: m)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

struct TabBar: View {
    @ObservedObject var m: NotchModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { m.tab = t } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 22)
                        .foregroundStyle(m.tab == t ? Color.black : .white.opacity(0.55))
                        .background(Capsule().fill(m.tab == t ? glow : Color.white.opacity(0.07)))
                        .overlay(alignment: .topTrailing) {
                            if t == .claude, !m.claude.waiting.isEmpty {
                                Circle().fill(claudeOrange).frame(width: 7, height: 7)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct HomeTab: View {
    @ObservedObject var m: NotchModel

    private var greeting: String {
        switch Calendar.current.component(.hour, from: m.now) {
        case 5..<12: return "صباح الخير ☀️"
        case 12..<17: return "يومك سعيد 🌤"
        case 17..<22: return "مساء الخير 🌙"
        default: return "لسه صاحي؟ 🌌"
        }
    }

    private static let timeFmt = arabic("h:mm a")
    private static let dateFmt = arabic("EEEE، d MMMM")
    private static func arabic(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "ar_EG")
        d.dateFormat = f
        return d
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(m.speech ?? greeting)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(m.speech == nil ? Color.white.opacity(0.7) : glow)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let b = m.battery {
                    HStack(spacing: 4) {
                        Text("\(b)%").font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: m.charging ? "battery.100.bolt"
                              : b > 75 ? "battery.100" : b > 50 ? "battery.75"
                              : b > 25 ? "battery.50" : "battery.25")
                    }
                    .foregroundStyle(b <= 20 && !m.charging ? Color.red : Color.green)
                }
                Text(Self.timeFmt.string(from: m.now))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Text(Self.dateFmt.string(from: m.now))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 10) {
                if let s = m.claude.sessions.first {
                    Label(m.claude.sessions.count > 1 ? "\(m.claude.sessions.count) جلسات" : s.project,
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
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .lineLimit(1)
            .padding(.top, 2)
        }
        .animation(.easeOut(duration: 0.25), value: m.speech)
    }
}

struct MusicTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        if let i = m.media.info {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(i.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(i.artist).font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        if let app = m.media.appName {
                            HStack(spacing: 4) {
                                Text(app)
                                if let icon = m.media.appIcon {
                                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                                }
                            }
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .lineLimit(1)
                    Artwork(image: m.media.artwork, size: 56, radius: 10)
                }
                if i.duration > 0 {
                    let pos = i.position(at: m.now)
                    HStack(spacing: 6) {
                        Text(clock(i.duration))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15))
                                Capsule().fill(m.accent).frame(width: g.size.width * min(1, pos / i.duration))
                            }
                        }
                        .frame(height: 4)
                        Text(clock(pos))
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 22) {
                    control("backward.fill") { m.media.send(.previous) }
                    control(i.playing ? "pause.fill" : "play.fill", size: 18) { m.media.send(.toggle) }
                    control("forward.fill") { m.media.send(.next) }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                Text("مفيش حاجة شغالة 🎧").font(.system(size: 14, weight: .bold, design: .rounded))
                Text("شغّل أغنية من Spotify أو Music أو YouTube وهتظهر هنا")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.5))
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
        if m.claude.sessions.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text("مفيش جلسات كلود مفتوحة ✳️").font(.system(size: 14, weight: .bold, design: .rounded))
                Text(m.claude.hooksInstalled
                     ? "افتح claude في التيرمنال وهيظهر هنا"
                     : "الـ hooks مش متركّبة في ~/.claude/settings.json")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(.top, 14)
        } else {
            VStack(spacing: 6) {
                ForEach(m.claude.sessions.prefix(4)) { s in
                    SessionRow(s: s, now: m.now)
                        .contentShape(Rectangle())
                        .onTapGesture { m.claude.focus(s) }
                        .contextMenu { Button("شيلها من القايمة") { m.claude.remove(s) } }
                }
            }
        }
    }
}

struct SessionRow: View {
    let s: ClaudeSession
    let now: Date

    private var chip: (String, Color) {
        switch s.state {
        case .working: return ("شغال", claudeOrange)
        case .waiting: return ("مستنيك", .yellow)
        case .done: return ("خلص", .green)
        case .idle: return ("جاهز", .gray)
        case .failed: return ("error", .red)
        }
    }

    private var ago: String {
        let d = Int(now.timeIntervalSince(s.updated))
        if d < 60 { return "دلوقتي" }
        if d < 3600 { return "\(d / 60)د" }
        return "\(d / 3600)س"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(ago).font(.system(size: 9, design: .rounded)).foregroundStyle(.white.opacity(0.35))
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(s.project).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(s.detail).font(.system(size: 10, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            Text(chip.0)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(chip.1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(chip.1.opacity(0.18)))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .help("اضغط عشان تروح للتيرمنال")
    }
}

struct ClipboardTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        let c = m.clipboard
        if c.items.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text("الكليب بورد فاضي 📋").font(.system(size: 14, weight: .bold, design: .rounded))
                Text("أي حاجة تعملها copy هتتحفظ هنا (آخر 20)")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(.top, 14)
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(c.items.prefix(5)) { item in
                    HStack(spacing: 8) {
                        Text(c.lastCopied == item.id ? "اتنسخ ✓" : ago(item.date))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(c.lastCopied == item.id ? Color.green : .white.opacity(0.35))
                            .frame(width: 46, alignment: .leading)
                        Text(item.preview)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                    .contentShape(Rectangle())
                    .onTapGesture { c.copy(item) }
                    .contextMenu {
                        Button("انسخ") { c.copy(item) }
                        Button("امسح") { c.remove(item) }
                        Divider()
                        Button("امسح الكل") { c.clear() }
                    }
                    .help(String(item.text.prefix(500)))
                }
            }
        }
    }

    private func ago(_ d: Date) -> String {
        let s = Int(m.now.timeIntervalSince(d))
        if s < 60 { return "دلوقتي" }
        if s < 3600 { return "\(s / 60)د" }
        return "\(s / 3600)س"
    }
}

struct ShelfTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        let shelf = m.shelf
        if m.dragging {
            HStack(spacing: 10) {
                DropZone(icon: "dot.radiowaves.left.and.right", title: "ابعته AirDrop") { urls in
                    ShelfStore.airDrop(urls)
                }
                DropZone(icon: "tray.and.arrow.down.fill", title: "حطه على الرف") { urls in
                    shelf.add(urls)
                }
            }
            .padding(.top, 4)
        } else if shelf.items.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text("الرف فاضي 🗂").font(.system(size: 14, weight: .bold, design: .rounded))
                Text("اسحب أي ملف على النوتش وسيبه هنا، أو ابعته AirDrop على طول")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(.white)
            .padding(.top, 14)
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 12) {
                    Button { shelf.clear() } label: { Text("مسح") }
                        .foregroundStyle(.white.opacity(0.45))
                    Button { ShelfStore.airDrop(shelf.items) } label: {
                        Label("AirDrop الكل", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .foregroundStyle(glow)
                    Spacer()
                    Text("\(shelf.items.count) ملف").foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                HStack(spacing: 8) {
                    if shelf.items.count > 4 {
                        Text("+\(shelf.items.count - 4)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .help("الباقي في Finder: كليك يمين ← وريهولي")
                    }
                    ForEach(shelf.items.prefix(4).reversed(), id: \.self) { u in ShelfItem(url: u, shelf: shelf) }
                }
                Text("اسحب الملف من هنا لأي مكان، أو كليك يمين للاختيارات")
                    .font(.system(size: 9, design: .rounded)).foregroundStyle(.white.opacity(0.3))
            }
        }
    }
}

struct ShelfItem: View {
    let url: URL
    let shelf: ShelfStore

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: ShelfStore.icon(url)).resizable().frame(width: 40, height: 40)
            Text(url.lastPathComponent)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(width: 64, height: 70)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("افتح") { NSWorkspace.shared.open(url) }
            Button("وريهولي في Finder") { ShelfStore.reveal([url]) }
            Button("ابعته AirDrop") { ShelfStore.airDrop([url]) }
            Divider()
            Button("شيله من الرف") { shelf.remove(url) }
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
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(over ? Color.black : glow)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(over ? glow : glow.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(glow.opacity(over ? 0 : 0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
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
                    Button { m.resetTimer() } label: { Image(systemName: "arrow.counterclockwise") }
                    Button {
                        m.timerEnd == nil ? m.startTimer() : m.pauseTimer()
                    } label: {
                        Image(systemName: m.timerEnd == nil ? "play.fill" : "pause.fill")
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(glow))
                            .foregroundStyle(.black)
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .buttonStyle(.plain)

                Text(clock(m.timerLeft))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(m.timerEnd == nil ? .white.opacity(0.6) : .white)
            }
            HStack(spacing: 6) {
                ForEach([5.0, 15, 25, 50], id: \.self) { min in
                    Button { m.startTimer(minutes: min) } label: {
                        Text("\(Int(min)) د")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(m.timerTotal == min * 60 ? glow.opacity(0.25) : Color.white.opacity(0.08)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("بومودورو 🍅 ركّز وأنا هنبهك").font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

struct SettingsTab: View {
    @ObservedObject var m: NotchModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            row("الأصوات", isOn: $m.soundsOn)
            if m.soundsOn {
                ForEach(SoundEvent.allCases, id: \.self) { e in soundRow(e) }
            }
            row("يفتح مع تشغيل الماك", isOn: Binding(get: { m.launchAtLogin }, set: { m.launchAtLogin = $0 }))
            HStack(spacing: 6) {
                Text(m.claude.hooksInstalled ? "متوصل بكلود كود" : "مش متوصل بكلود كود")
                Circle().fill(m.claude.hooksInstalled ? Color.green : .red).frame(width: 7, height: 7)
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            Button { NSApp.terminate(nil) } label: {
                Label("قفل روبو", systemImage: "power")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
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
                    Text(cur.isEmpty ? "من غير" : cur)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(cur.isEmpty ? Color.white.opacity(0.4) : glow)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("دوس عشان تغيّر الصوت")
            Text(e.title).font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Capsule()
                .fill(isOn.wrappedValue ? glow : Color.white.opacity(0.18))
                .frame(width: 30, height: 17)
                .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 13, height: 13).padding(2)
                }
                .onTapGesture { withAnimation(.spring(response: 0.25)) { isOn.wrappedValue.toggle() } }
            Text(title).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white)
        }
    }
}

