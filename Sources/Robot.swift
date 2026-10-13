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

struct RobotEye: View {
    let w: CGFloat
    let mood: Mood
    let blinking: Bool

    var body: some View {
        let c = eyeColor(mood)
        Group {
            switch mood {
            case .happy:
                HappyEye()
                    .stroke(c, style: StrokeStyle(lineWidth: w * 0.28, lineCap: .round))
                    .frame(width: w, height: w * 0.5)
            case .sleepy:
                Capsule().fill(c).frame(width: w, height: max(2, w * 0.18))
            case .surprised, .alert:
                Circle().fill(c).frame(width: w * 1.15, height: w * 1.15)
            case .idle, .thinking, .listening:
                Capsule()
                    .fill(c)
                    .overlay(Circle().fill(.white.opacity(0.85))
                        .frame(width: w * 0.3, height: w * 0.3)
                        .offset(x: w * 0.15, y: -w * 0.25))
                    .frame(width: w, height: w * 1.3)
                    .scaleEffect(x: 1, y: blinking && mood != .listening ? 0.08 : 1)
            }
        }
        .shadow(color: c.opacity(0.9), radius: w * 0.35)
        .frame(width: w * 1.2, height: w * 1.4)
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
                RobotEye(w: 9, mood: m.mood, blinking: e.blinking)
                RobotEye(w: 9, mood: m.mood, blinking: e.blinking)
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

    var body: some View {
        let mood = m.mood
        Dancing(on: m.media.isPlaying && (mood == .idle || mood == .happy), amount: 6) {
            VStack(spacing: 0) {
                Circle()
                    .fill(mood == .sleepy ? Color.orange : eyeColor(mood))
                    .frame(width: s * 0.1, height: s * 0.1)
                    .shadow(color: eyeColor(mood), radius: pulse ? 6 : 1)
                    .opacity(mood == .alert && pulse ? 0.4 : 1)
                Rectangle().fill(Color.gray).frame(width: 2, height: s * 0.1)

                ZStack {
                    RoundedRectangle(cornerRadius: s * 0.22)
                        .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: s * 0.16)
                        .fill(Color(white: 0.06))
                        .padding(s * 0.07)

                    VStack(spacing: s * 0.06) {
                        HStack(spacing: s * 0.14) {
                            RobotEye(w: s * 0.15, mood: mood, blinking: e.blinking)
                            RobotEye(w: s * 0.15, mood: mood, blinking: e.blinking)
                        }
                        mouth(mood)
                    }
                    .offset(x: e.look.x * s * 0.07, y: e.look.y * s * 0.04)
                    .animation(.easeOut(duration: 0.25), value: e.look)
                }
                .frame(width: s, height: s * 0.82)
                .overlay(alignment: .leading) { ear.offset(x: -s * 0.05) }
                .overlay(alignment: .trailing) { ear.offset(x: s * 0.05) }
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

    // ودانه بتنوّر وهو بيسمعك
    private var ear: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(m.mood == .listening ? listenRed : Color(white: 0.5))
            .shadow(color: m.mood == .listening ? listenRed : .clear, radius: 2 + 6 * m.voice.level)
            .frame(width: s * 0.08, height: s * 0.3)
    }

    @ViewBuilder private func mouth(_ mood: Mood) -> some View {
        switch mood {
        case .surprised, .alert:
            Circle().stroke(eyeColor(mood), lineWidth: 2).frame(width: s * 0.1, height: s * 0.1)
        case .sleepy:
            Capsule().fill(glow.opacity(0.6)).frame(width: s * 0.12, height: 2)
        case .thinking:
            ThinkingDots(color: glow, size: s * 0.045).frame(height: s * 0.1)
        case .listening:
            // بوقه بيتفتح مع صوتك كأنه بيردد وراك
            Capsule().stroke(glow, lineWidth: 2)
                .frame(width: s * 0.14, height: s * (0.03 + 0.1 * m.voice.level))
                .frame(height: s * 0.13)
                .animation(.easeOut(duration: 0.08), value: m.voice.level)
        default:
            Smile(depth: mood == .happy ? 1.4 : 0.6)
                .stroke(glow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: s * 0.26, height: s * 0.1)
                .shadow(color: glow, radius: 3)
        }
    }
}
