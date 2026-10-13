// بيرسم أيقونة التطبيق: swift icon/make_icon.swift → icon/AppIcon.icns
import AppKit
import SwiftUI

let glow = Color(red: 0.31, green: 0.96, blue: 1.0)

struct Icon: View {
    var body: some View {
        ZStack {
            // مربع ماك بحواف ناعمة على مقاس 1024 (824 + هوامش)
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.03)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 4))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)

            // النوتش فوق
            UnevenRoundedRectangle(bottomLeadingRadius: 46, bottomTrailingRadius: 46)
                .fill(.black)
                .frame(width: 400, height: 92)
                .offset(y: -366)

            // راس الروبوت
            VStack(spacing: 0) {
                Capsule().fill(Color(white: 0.55)).frame(width: 14, height: 60)
                Circle().fill(glow).frame(width: 40, height: 40).shadow(color: glow, radius: 18)
                    .offset(y: -82)
                    .frame(height: 0)
                RoundedRectangle(cornerRadius: 130, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.11)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 130, style: .continuous)
                        .stroke(glow.opacity(0.35), lineWidth: 6))
                    .frame(width: 540, height: 400)
                    .overlay {
                        VStack(spacing: 46) {
                            HStack(spacing: 120) { eye; eye }
                            Smile().stroke(glow, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                                .frame(width: 130, height: 34)
                                .shadow(color: glow.opacity(0.9), radius: 16)
                        }
                        .offset(y: 16)
                    }
            }
            .offset(y: 50)
        }
        .frame(width: 1024, height: 1024)
    }

    var eye: some View {
        Capsule().fill(glow)
            .overlay(Circle().fill(.white.opacity(0.85)).frame(width: 30, height: 30).offset(x: 16, y: -30))
            .frame(width: 92, height: 124)
            .shadow(color: glow.opacity(0.9), radius: 30)
    }
}

struct Smile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.6))
        return p
    }
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon")
let set = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                         (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"),
                         (1024, "512x512@2x")] {
        let r = ImageRenderer(content: Icon())
        r.scale = CGFloat(size) / 1024
        guard let cg = r.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: set.appendingPathComponent("icon_\(name).png"))
    }
}
