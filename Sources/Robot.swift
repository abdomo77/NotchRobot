import SwiftUI

struct HappyEye: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.6))
        return p
    }
}

struct Smile: Shape {
    var depth: CGFloat
    var animatableData: CGFloat { get { depth } set { depth = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.minY + r.height * depth))
        return p
    }
}

func eyeColor(_ mood: Mood) -> Color { mood == .alert ? claudeOrange : glow }
let listenRed = Color(red: 1.0, green: 0.3, blue: 0.35)
/// الشبح أبيض، فعينه وبوقه غامقين
let ghostInk = Color(white: 0.12)

struct RobotEye: View {
    let w: CGFloat
    let mood: Mood
    let blinking: Bool
    var buddy: Buddy = .robot
    /// لون ثابت بدل لون المزاج، ومن غير توهج
    var tint: Color? = nil

    var body: some View {
        let c = tint ?? eyeColor(mood)
        let pixel = buddy == .pixel
        Group {
            switch mood {
            case .happy:
                HappyEye()
                    .stroke(c, style: StrokeStyle(lineWidth: w * 0.28, lineCap: pixel ? .butt : .round))
                    .frame(width: w, height: w * 0.5)
            case .sleepy:
                if pixel { Rectangle().fill(c).frame(width: w, height: max(2, w * 0.2)) }
                else { Capsule().fill(c).frame(width: w, height: max(2, w * 0.18)) }
            case .surprised, .alert:
                if pixel { Rectangle().fill(c).frame(width: w * 1.1, height: w * 1.1) }
                else { Circle().fill(c).frame(width: w * 1.15, height: w * 1.15) }
            case .idle, .thinking, .listening:
                open(c)
                    .scaleEffect(x: 1, y: blinking && mood != .listening ? 0.08 : 1)
            }
        }
        .shadow(color: tint == nil ? c.opacity(0.9) : .clear, radius: w * 0.35)
        .frame(width: w * 1.2, height: w * 1.4)
    }

    /// العين وهي مفتوحة عادي: كل شخصية ليها شكل
    @ViewBuilder private func open(_ c: Color) -> some View {
        switch buddy {
        case .pixel:
            Rectangle().fill(c)
                .overlay(alignment: .topTrailing) { Rectangle().fill(.white.opacity(0.85)).frame(width: w * 0.3, height: w * 0.3) }
                .frame(width: w, height: w * 1.2)
        case .cat:
            // حدقة القطة الطولية
            Capsule().fill(c)
                .overlay(Capsule().fill(Color.black.opacity(0.75)).frame(width: w * 0.22, height: w * 1.0))
                .frame(width: w, height: w * 1.3)
        case .ghost:
            Ellipse().fill(c).frame(width: w * 0.9, height: w * 1.25)
        case .robot:
            Capsule()
                .fill(c)
                .overlay(Circle().fill(.white.opacity(0.85))
                    .frame(width: w * 0.3, height: w * 0.3)
                    .offset(x: w * 0.15, y: -w * 0.25))
                .frame(width: w, height: w * 1.3)
        }
    }
}

/// شبح: راس مدورة وديل متموج
struct GhostShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rad = r.width / 2
        let bottom = r.maxY
        p.move(to: CGPoint(x: r.minX, y: bottom))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + rad), radius: rad, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: bottom))
        // تلات موجات تحت
        let wave = r.width / 3
        for i in 0..<3 {
            let x0 = r.maxX - CGFloat(i) * wave
            p.addQuadCurve(to: CGPoint(x: x0 - wave, y: bottom),
                           control: CGPoint(x: x0 - wave / 2, y: bottom - r.height * 0.14))
        }
        p.closeSubpath()
        return p
    }
}

/// ودن القطة
struct CatEar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX - r.width * 0.15, y: r.minY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}

/// بيرقص على المزيكا
struct Dancing<Content: View>: View {
    let on: Bool
    let amount: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !on)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            content()
                .rotationEffect(.degrees(on ? sin(t * .pi * 2) * amount : 0))
                .offset(y: on ? -abs(sin(t * .pi * 2)) * amount * 0.4 : 0)
        }
    }
}

/// عيون الروبوت لما النوتش مقفول
struct PeekingEyes: View {
    @ObservedObject var m: NotchModel
    @ObservedObject var e: EyeState
    var body: some View {
        Group {
            HStack(spacing: 10) {
                // على الأسود عين الشبح بتبقى بيضا
                RobotEye(w: 9, mood: m.mood, blinking: e.blinking, buddy: m.buddy, tint: m.buddy == .ghost ? .white : nil)
                RobotEye(w: 9, mood: m.mood, blinking: e.blinking, buddy: m.buddy, tint: m.buddy == .ghost ? .white : nil)
            }
        }
        .offset(x: e.look.x * 5, y: e.look.y * 2)
        .animation(.easeOut(duration: 0.25), value: e.look)
        .overlay(alignment: .topTrailing) {
            if m.mood == .sleepy {
                Text("z").font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(glow).offset(x: 12, y: -4)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: m.mood)
    }
}

struct RobotFace: View {
    @ObservedObject var m: NotchModel
    @ObservedObject var e: EyeState
    let s: CGFloat
    @State private var pulse = false

    private var ghost: Bool { m.buddy == .ghost }
    /// لون البوق والنقط
    private var ink: Color { ghost ? ghostInk : glow }

    var body: some View {
        let mood = m.mood
        Dancing(on: m.media.isPlaying && (mood == .idle || mood == .happy), amount: 6) {
            VStack(spacing: 0) {
                top(mood).frame(width: s, height: s * 0.2)
                ZStack {
                    shell
                    VStack(spacing: s * 0.06) {
                        HStack(spacing: s * 0.14) {
                            RobotEye(w: s * 0.15, mood: mood, blinking: e.blinking, buddy: m.buddy, tint: ghost ? ghostInk : nil)
                            RobotEye(w: s * 0.15, mood: mood, blinking: e.blinking, buddy: m.buddy, tint: ghost ? ghostInk : nil)
                        }
                        mouth(mood)
                    }
                    .offset(x: e.look.x * s * 0.07, y: e.look.y * s * 0.04 + (ghost ? -s * 0.05 : 0))
                    .animation(.easeOut(duration: 0.25), value: e.look)
                }
                .frame(width: s, height: s * 0.82)
                .overlay(alignment: .leading) { if m.buddy == .robot || m.buddy == .pixel { ear.offset(x: -s * 0.05) } }
                .overlay(alignment: .trailing) { if m.buddy == .robot || m.buddy == .pixel { ear.offset(x: s * 0.05) } }
                .overlay { if m.buddy == .cat { whiskers } }
            }
            .rotationEffect(.degrees(mood == .sleepy ? -6 : Double(e.look.x) * 4))
        }
        .overlay(alignment: .topTrailing) {
            if m.media.isPlaying && mood != .sleepy {
                Image(systemName: "music.note")
                    .font(.system(size: s * 0.14, weight: .bold))
                    .foregroundStyle(glow)
                    .offset(x: s * 0.12, y: s * 0.05)
                    .opacity(pulse ? 1 : 0.3)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: mood)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever()) { pulse = true }
        }
    }

    private var listening: Bool { m.mood == .listening }

    /// اللي فوق الراس: إريال للروبوت، ودان للقطة، ولا حاجة للشبح (راسه نفسها أطول)
    @ViewBuilder private func top(_ mood: Mood) -> some View {
        switch m.buddy {
        case .robot, .pixel:
            let px = m.buddy == .pixel
            VStack(spacing: 0) {
                Group {
                    if px { Rectangle().fill(mood == .sleepy ? Color.orange : eyeColor(mood)) }
                    else { Circle().fill(mood == .sleepy ? Color.orange : eyeColor(mood)) }
                }
                .frame(width: s * 0.1, height: s * 0.1)
                .shadow(color: eyeColor(mood), radius: pulse ? 6 : 1)
                .opacity(mood == .alert && pulse ? 0.4 : 1)
                Rectangle().fill(Color.gray).frame(width: px ? 3 : 2, height: s * 0.1)
            }
        case .cat:
            // ودانها بتنوّر وهي بتسمعك
            HStack(spacing: s * 0.42) {
                ForEach(0..<2, id: \.self) { _ in
                    CatEar().fill(catFur)
                        .overlay(CatEar().fill(listening ? listenRed : Color(red: 1, green: 0.62, blue: 0.68)).scaleEffect(0.5, anchor: .bottom))
                        .shadow(color: listening ? listenRed : .clear, radius: 2 + 6 * m.voice.level)
                        .frame(width: s * 0.24, height: s * 0.24)
                }
            }
            .offset(y: s * 0.06)
        case .ghost:
            Color.clear
        }
    }

    private var catFur: LinearGradient {
        LinearGradient(colors: [Color(red: 0.98, green: 0.66, blue: 0.36), Color(red: 0.82, green: 0.45, blue: 0.22)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// جسم الشخصية والشاشة اللي عليها الوش
    @ViewBuilder private var shell: some View {
        switch m.buddy {
        case .robot:
            RoundedRectangle(cornerRadius: s * 0.22)
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: s * 0.16).fill(Color(white: 0.06)).padding(s * 0.07)
        case .pixel:
            Rectangle().fill(Color(white: 0.72))
                .overlay(Rectangle().strokeBorder(Color(white: 0.45), lineWidth: 3))
            Rectangle().fill(Color(red: 0.04, green: 0.08, blue: 0.05)).padding(s * 0.08)
        case .cat:
            RoundedRectangle(cornerRadius: s * 0.3, style: .continuous).fill(catFur)
            RoundedRectangle(cornerRadius: s * 0.22, style: .continuous).fill(Color(white: 0.07)).padding(s * 0.08)
        case .ghost:
            GhostShape()
                .fill(LinearGradient(colors: [.white, Color(white: 0.8)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.86, height: s * 1.02)
                .offset(y: -s * 0.1)
                .shadow(color: listening ? listenRed : glow.opacity(0.35), radius: listening ? 2 + 8 * m.voice.level : 6)
        }
    }

    /// شنب القطة على الجناب
    private var whiskers: some View {
        HStack {
            VStack(spacing: s * 0.05) { ForEach(0..<2, id: \.self) { _ in Capsule().fill(.white.opacity(0.7)).frame(width: s * 0.14, height: 1.5) } }
                .offset(x: -s * 0.1)
            Spacer()
            VStack(spacing: s * 0.05) { ForEach(0..<2, id: \.self) { _ in Capsule().fill(.white.opacity(0.7)).frame(width: s * 0.14, height: 1.5) } }
                .offset(x: s * 0.1)
        }
        .offset(y: s * 0.12)
    }

    // ودانه بتنوّر وهو بيسمعك
    private var ear: some View {
        RoundedRectangle(cornerRadius: m.buddy == .pixel ? 0 : 3)
            .fill(listening ? listenRed : Color(white: 0.5))
            .shadow(color: listening ? listenRed : .clear, radius: 2 + 6 * m.voice.level)
            .frame(width: s * 0.08, height: s * 0.3)
    }

    @ViewBuilder private func mouth(_ mood: Mood) -> some View {
        switch mood {
        case .surprised, .alert:
            Circle().stroke(ghost ? ghostInk : eyeColor(mood), lineWidth: 2).frame(width: s * 0.1, height: s * 0.1)
        case .sleepy:
            Capsule().fill(ink.opacity(0.6)).frame(width: s * 0.12, height: 2)
        case .thinking:
            ThinkingDots(color: ink, size: s * 0.045).frame(height: s * 0.1)
        case .listening:
            // بوقه بيتفتح مع صوتك كأنه بيردد وراك
            Capsule().stroke(ink, lineWidth: 2)
                .frame(width: s * 0.14, height: s * (0.03 + 0.1 * m.voice.level))
                .frame(height: s * 0.13)
                .animation(.easeOut(duration: 0.08), value: m.voice.level)
        default:
            Smile(depth: mood == .happy ? 1.4 : 0.6)
                .stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineCap: m.buddy == .pixel ? .butt : .round))
                .frame(width: s * 0.26, height: s * 0.1)
                .shadow(color: ghost ? .clear : glow, radius: 3)
        }
    }
}
