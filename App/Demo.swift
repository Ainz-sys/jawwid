import Foundation

/// Screenshot mode for the simulator: `-jawwidDemo <screen> [-jawwidTheme dark|light] [-jawwidFont 30]`.
/// Uses sample progress in memory, plays no audio and never touches the saved data.
enum Demo {
    static let args = ProcessInfo.processInfo.arguments

    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var screen: String? { value("-jawwidDemo") }
    static var active: Bool { screen != nil }

    /// Sample state: al-Fatiha done, an-Naba 1–13 done, twelve days of practice, last stop at an-Naba 14.
    @MainActor
    static func userData() -> UserData? {
        guard let s = screen else { return nil }
        var d = UserData()
        d.settings.theme = value("-jawwidTheme") == "dark" ? .dark : .light
        if let f = value("-jawwidFont"), let v = Double(f) { d.settings.quranFontSize = v }
        if s == "home-new" { return d }
        let q = Quran.shared
        var completed: [Int] = []
        for a in 1...7 { completed.append(q.globalIndex(1, a)) }
        for a in 1...13 { completed.append(q.globalIndex(78, a)) }
        d.completed = completed
        let cal = Calendar.current
        for i in 0..<12 {
            if let day = cal.date(byAdding: .day, value: -i, to: Date()) {
                d.days[AppStore.dayKey(day)] = i == 0 ? 6 : 3 + (i % 4)
            }
        }
        d.last = Position(surah: 78, ayah: 14, date: Date())
        return d
    }

    /// Opens the screen to photograph.
    @MainActor
    static func prepare() {
        guard let s = screen else { return }
        let engine = PlaybackEngine.shared
        let router = Router.shared
        switch s {
        case "index", "juz":
            router.tab = .mushaf
        case "reader", "reader-settings", "reader-font", "reader-compact":
            router.open(surah: 78, ayah: nil)
            engine.showDemo(surah: 78, ayah: 14, words: 3..<4, phase: .reciting, repetition: 1, repetitions: 2,
                            elapsed: 4.3, duration: 10.0, playing: true)
        case "reader-gap":
            router.open(surah: 78, ayah: nil)
            engine.showDemo(surah: 78, ayah: 14, words: nil, phase: .gap, repetition: 1, repetitions: 2,
                            elapsed: 3.1, duration: 9.6, playing: true)
        case "reader-fatiha":
            router.open(surah: 1, ayah: nil)
            engine.showDemo(surah: 1, ayah: 2, words: 1..<2, phase: .reciting, repetition: 2, repetitions: 2,
                            elapsed: 1.4, duration: 5.2, playing: true)
        case "reader-baqarah":
            router.open(surah: 2, ayah: nil)
            engine.showDemo(surah: 2, ayah: 2, words: 4..<5, phase: .reciting, repetition: 1, repetitions: 2,
                            elapsed: 3.0, duration: 9.0, playing: true)
        case "reader-basmala":
            router.open(surah: 97, ayah: nil)
            engine.showDemo(surah: 97, ayah: 0, words: 0..<1, phase: .reciting, repetition: 1, repetitions: 1,
                            elapsed: 0.8, duration: 4.0, playing: true)
        case "reader-idle":
            router.open(surah: 78, ayah: nil)
        case "progress":
            router.tab = .progress
        case "settings":
            router.homePath = [.settings]
        case "credits":
            router.homePath = [.credits]
        case "tajweed":
            router.tab = .tajweed
        case "voice":
            router.tab = .voice
        case "mini":
            router.tab = .home
            engine.showDemo(surah: 78, ayah: 14, words: nil, phase: .gap, repetition: 1, repetitions: 2,
                            elapsed: 3.1, duration: 9.6, playing: true)
        default:
            router.tab = .home
        }
    }

    /// The reader opens this sheet by itself in screenshot mode.
    static var readerSheet: String? {
        switch screen {
        case "reader-settings": return "settings"
        case "reader-font": return "font"
        default: return nil
        }
    }
}
