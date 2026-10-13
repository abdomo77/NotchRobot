import AppKit
import SwiftUI

/// الربط مع sp2txt (الإملاء بالصوت): بيبعت حالته كـ distributed notification
/// باسم com.gendy.sp2txt، وروبو بيعمل نفسه بيسمعك وبيكتب.
final class VoiceStore: ObservableObject {
    enum State { case idle, listening, processing }

    @Published private(set) var state: State = .idle
    /// علوّ صوتك دلوقتي من 0 لـ 1
    @Published private(set) var level: Double = 0

    var onResult: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var lastMessage = Date()

    var active: Bool { state != .idle }

    func watch() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.gendy.sp2txt"), object: nil, queue: .main
        ) { [weak self] n in self?.handle(n.userInfo ?? [:]) }

        // لو sp2txt وقع في النص منفضلش عاملين نفسنا بنسمع على طول
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.active else { return }
            let limit: TimeInterval = self.state == .listening ? 3 : 25
            if Date().timeIntervalSince(self.lastMessage) > limit { self.reset() }
        }
    }

    private func handle(_ info: [AnyHashable: Any]) {
        lastMessage = Date()
        switch info["state"] as? String {
        case "listening":
            state = .listening
            level = 0
        case "level":
            guard state == .listening, let l = info["level"] as? Double else { return }
            // منحدّثش الواجهة على فروق صغيرة
            if abs(l - level) > 0.04 { level = l }
        case "processing":
            state = .processing
            level = 0
        case "done":
            reset()
            if let t = info["text"] as? String, !t.isEmpty { onResult?(t) }
        case "error":
            reset()
            onError?(info["text"] as? String ?? "")
        default:
            reset()
        }
    }

    private func reset() {
        state = .idle
        level = 0
    }
}

/// في النوتش المقفول: مايك وأعمدة بتتحرك مع صوتك، أو فقاعة وهو بيكتب
struct VoiceBadge: View {
    @ObservedObject var v: VoiceStore

    var body: some View {
        HStack(spacing: 3) {
            if v.state == .processing {
                AnimatedSymbol(name: "text.bubble.fill", color: glow, motion: .pulse)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.red)
                HStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(glow)
                            .frame(width: 2.5, height: 3 + 10 * v.level * [0.7, 1.0, 0.55][i])
                    }
                }
                .frame(height: 13)
                .animation(.easeOut(duration: 0.08), value: v.level)
            }
        }
        .frame(width: 30)
    }
}
