import Foundation

/// لغة الواجهة: اللي كان مسطّب قبل كده يفضل عربي، والجديد على لغة الماك
enum Lang: String {
    case ar, en

    static var current: Lang = {
        let d = UserDefaults.standard
        if let s = d.string(forKey: "lang"), let l = Lang(rawValue: s) { return l }
        let existing = d.object(forKey: "soundsOn") != nil
            || FileManager.default.fileExists(atPath: ClaudeStore.base.appendingPathComponent("sessions.json").path)
        let l: Lang = existing || Locale.preferredLanguages.first?.hasPrefix("ar") == true ? .ar : .en
        d.set(l.rawValue, forKey: "lang")
        return l
    }()
}

/// النص بالعربي أو بالإنجليزي حسب لغة الواجهة
func tr(_ ar: String, _ en: String) -> String { Lang.current == .ar ? ar : en }
