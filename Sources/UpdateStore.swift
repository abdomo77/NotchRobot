import Foundation

/// بيشوف آخر إصدار على GitHub، ولو أجدد من اللي عندك بيقولك (من غير ما يغيّر حاجة لوحده)
final class UpdateStore: ObservableObject {
    static let repo = "abdomo77/NotchRobot"
    static let page = URL(string: "https://github.com/\(repo)/releases/latest")!
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// أحدث إصدار لو أجدد من اللي عندك
    @Published private(set) var latest: String?
    var onNew: ((String) -> Void)?
    private var timer: Timer?

    /// الـ API من غير توكن مسموحله 60 طلب في الساعة، فمرة كل 12 ساعة كفاية
    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String else { return }
            let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                guard let self else { return }
                let new = Self.newer(v, than: Self.current) ? v : nil
                if new != nil, new != self.latest { self.onNew?(v) }
                self.latest = new
            }
        }.resume()
    }

    /// مقارنة رقم رقم: 2.10 أجدد من 2.9
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
