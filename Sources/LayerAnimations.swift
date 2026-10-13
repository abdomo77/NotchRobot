import AppKit
import SwiftUI

// الحركات المستمرة في النوتش المقفول معمولة بـ Core Animation:
// بتتحرك في الـ render server بتاع النظام، فالتطبيق مش بيرسم ولا فريم.

private func forever(_ keyPath: String, from: Any, to: Any, duration: Double,
                     autoreverses: Bool = true, offset: Double = 0) -> CABasicAnimation {
    let a = CABasicAnimation(keyPath: keyPath)
    a.fromValue = from
    a.toValue = to
    a.duration = duration
    a.autoreverses = autoreverses
    a.repeatCount = .infinity
    a.isRemovedOnCompletion = false
    a.timeOffset = offset
    a.timingFunction = CAMediaTimingFunction(name: autoreverses ? .easeInEaseOut : .linear)
    return a
}

struct EqualizerBars: NSViewRepresentable {
    var color: Color = glow

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 13))
        v.wantsLayer = true
        let durations = [0.45, 0.32, 0.52, 0.38]
        for i in 0..<4 {
            let bar = CALayer()
            bar.backgroundColor = NSColor(color).cgColor
            bar.cornerRadius = 1.25
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.frame = CGRect(x: 2 + CGFloat(i) * 4.5, y: 0, width: 2.5, height: 13)
            bar.add(forever("transform.scale.y", from: 0.3, to: 1.0, duration: durations[i], offset: Double(i) * 0.13),
                    forKey: "eq")
            v.layer?.addSublayer(bar)
        }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        v.layer?.sublayers?.forEach { $0.backgroundColor = NSColor(color).cgColor }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: 20, height: 13)
    }
}

/// SF Symbol بيلف أو بينبض
struct AnimatedSymbol: NSViewRepresentable {
    enum Motion { case spin, pulse, still }
    let name: String
    let color: Color
    let motion: Motion
    var size: CGFloat = 12

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: size + 4, height: size + 4))
        v.wantsLayer = true
        v.layer?.addSublayer(CALayer())
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let l = v.layer?.sublayers?.first else { return }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
            .applying(.init(paletteColors: [NSColor(color)]))
        var rect = CGRect(x: 0, y: 0, width: (size + 4) * 2, height: (size + 4) * 2)
        l.contents = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?
            .cgImage(forProposedRect: &rect, context: nil, hints: nil)
        l.contentsGravity = .resizeAspect
        l.frame = CGRect(x: 0, y: 0, width: size + 4, height: size + 4)
        l.removeAllAnimations()
        switch motion {
        case .spin: l.add(forever("transform.rotation.z", from: 0, to: -2 * Double.pi, duration: 2, autoreverses: false), forKey: "m")
        case .pulse: l.add(forever("opacity", from: 1.0, to: 0.35, duration: 0.5), forKey: "m")
        case .still: break
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: size + 4, height: size + 4)
    }
}

/// تلات نقط بتنور ورا بعض وكلود بيفكّر
struct ThinkingDots: NSViewRepresentable {
    let color: Color
    let size: CGFloat

    private var width: CGFloat { size * 3 + size * 0.6 * 2 }

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: width, height: size))
        v.wantsLayer = true
        for i in 0..<3 {
            let dot = CALayer()
            dot.frame = CGRect(x: CGFloat(i) * size * 1.6, y: 0, width: size, height: size)
            dot.cornerRadius = size / 2
            dot.add(forever("opacity", from: 0.35, to: 1.0, duration: 0.63, offset: 0.63 * 2 - Double(i) * 0.16),
                    forKey: "dot")
            v.layer?.addSublayer(dot)
        }
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        v.layer?.sublayers?.forEach { $0.backgroundColor = NSColor(color).cgColor }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: width, height: size)
    }
}
