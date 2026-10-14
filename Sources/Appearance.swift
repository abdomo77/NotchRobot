import SwiftUI

/// شكل النوتش نفسه. الشريط اللي فوق النوتش الحقيقي بيفضل أسود في كل الأشكال عشان الكاميرا متبانش
enum Skin: String, CaseIterable {
    case dark, glass, neon, minimal
    var title: String {
        switch self {
        case .dark: return tr("غامق", "Dark")
        case .glass: return tr("زجاج", "Glass")
        case .neon: return tr("نيون", "Neon")
        case .minimal: return tr("هادي", "Minimal")
        }
    }
}

/// الشخصية اللي ساكنة في النوتش
enum Buddy: String, CaseIterable {
    case robot, cat, ghost, pixel
    var title: String {
        switch self {
        case .robot: return tr("روبوت", "Robot")
        case .cat: return tr("قطة", "Cat")
        case .ghost: return tr("شبح", "Ghost")
        case .pixel: return tr("بكسل", "Pixel")
        }
    }
}

/// لون العيون والتوهج
enum Accent: String, CaseIterable {
    case cyan, purple, pink, green, yellow, orange
    var color: Color {
        switch self {
        case .cyan: return Color(red: 0.31, green: 0.96, blue: 1.0)
        case .purple: return Color(red: 0.70, green: 0.55, blue: 1.0)
        case .pink: return Color(red: 1.0, green: 0.45, blue: 0.75)
        case .green: return Color(red: 0.40, green: 1.0, blue: 0.55)
        case .yellow: return Color(red: 1.0, green: 0.85, blue: 0.30)
        case .orange: return Color(red: 1.0, green: 0.58, blue: 0.30)
        }
    }
}

/// الاختيارات الحالية. الموديل هو اللي بيغيّرها (وبيعيد رسم النوتش)، والـ views بتقراها من هنا
enum Appearance {
    static var skin = load("skin", Skin.dark)
    static var buddy = load("buddy", Buddy.robot)
    static var accent = load("accent", Accent.cyan)

    private static func load<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}

/// لون روبو الأساسي (كان ثابت سماوي، دلوقتي على حسب اختيارك)
var glow: Color { Appearance.accent.color }

/// خلفية زجاج حقيقية (بتاخد من اللي ورا النوتش)
struct GlassBackground: NSViewRepresentable {
    /// نص قطر الحواف، زي شكل الجزيرة
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    /// الـ blur بيترسم من الـ window server، فالـ clipShape بتاع SwiftUI ممكن ميقصّهوش؛ القناع بيقصه أكيد
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        let r = radius
        let img = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        v.maskImage = img
    }
}
