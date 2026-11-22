import Foundation
import SwiftUI

// MARK: - Recitations

enum Reciter: String, Codable, CaseIterable, Identifiable {
    case murattal, mujawwad, teacher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .murattal: return "المنشاوي · مرتّل"
        case .mujawwad: return "المنشاوي · مجوّد"
        case .teacher: return "المصحف المعلّم · ترديد الأطفال"
        }
    }

    var subtitle: String {
        switch self {
        case .murattal: return "آيةً آية، مع تظليل الكلمة الحالية"
        case .mujawwad: return "آيةً آية بأداء مجوّد، مع تظليل الكلمة"
        case .teacher: return "استماع للسورة كاملة، دون توقف بين الآيات"
        }
    }

    /// Ayah-by-ayah recordings support pauses, repetition and word highlighting.
    var isAyahByAyah: Bool { self != .teacher }

    /// EveryAyah folder (one MP3 per ayah).
    var everyAyahFolder: String? {
        switch self {
        case .murattal: return "Minshawy_Murattal_128kbps"
        case .mujawwad: return "Minshawy_Mujawwad_192kbps"
        case .teacher: return nil
        }
    }

    /// Bundled word-timing file (quran-align).
    var timingResource: String? {
        switch self {
        case .murattal: return "timings-murattal"
        case .mujawwad: return "timings-mujawwad"
        case .teacher: return nil
        }
    }

    static let reciterName = "محمد صديق المنشاوي"

    func remoteURL(surah: Int, ayah: Int) -> URL? {
        guard let folder = everyAyahFolder else { return nil }
        return URL(string: "https://everyayah.com/data/\(folder)/\(String(format: "%03d%03d", surah, ayah)).mp3")
    }

    /// Whole-surah file of the teacher recording (mp3quran.net).
    func remoteSurahURL(surah: Int) -> URL? {
        guard self == .teacher else { return nil }
        return URL(string: "https://cdn.mp3quran.net/audio/muhammad-minshawi/r3/\(String(format: "%03d", surah)).mp3")
    }
}

enum PauseMode: String, Codable, CaseIterable, Identifiable {
    case ayahLength, oneAndHalf, fixed, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ayahLength: return "بطول الآية"
        case .oneAndHalf: return "مرة ونصف"
        case .fixed: return "ثابتة"
        case .none: return "بلا توقف"
        }
    }
}

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "تلقائي"
        case .light: return "فاتح"
        case .dark: return "ليلي"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppSettings: Codable, Equatable {
    var reciter: Reciter = .murattal
    var repeatCount: Int = 2
    var pauseMode: PauseMode = .ayahLength
    var fixedPause: Int = 5
    var autoAdvance: Bool = true
    var speed: Double = 1.0
    var quranFontSize: Double = 30
    var theme: ThemeMode = .system
    var playBasmala: Bool = true

    static let speeds: [Double] = [0.75, 1.0, 1.25]
    static let fontRange: ClosedRange<Double> = 22...44

    init() {}

    // Tolerates missing keys, so older saved files keep working after new settings are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        reciter = (try? c.decode(Reciter.self, forKey: .reciter)) ?? d.reciter
        repeatCount = (try? c.decode(Int.self, forKey: .repeatCount)) ?? d.repeatCount
        pauseMode = (try? c.decode(PauseMode.self, forKey: .pauseMode)) ?? d.pauseMode
        fixedPause = (try? c.decode(Int.self, forKey: .fixedPause)) ?? d.fixedPause
        autoAdvance = (try? c.decode(Bool.self, forKey: .autoAdvance)) ?? d.autoAdvance
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
        quranFontSize = (try? c.decode(Double.self, forKey: .quranFontSize)) ?? d.quranFontSize
        theme = (try? c.decode(ThemeMode.self, forKey: .theme)) ?? d.theme
        playBasmala = (try? c.decode(Bool.self, forKey: .playBasmala)) ?? d.playBasmala
    }
}

struct Position: Codable, Equatable {
    var surah: Int
    var ayah: Int
    var date: Date
}

/// Everything the app remembers. Stored on the device only.
struct UserData: Codable {
    var settings = AppSettings()
    /// Global indices (0…6235) of ayat completed with their full repetitions.
    var completed: [Int] = []
    /// "yyyy-MM-dd" → ayat completed that day.
    var days: [String: Int] = [:]
    var last: Position?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decode(AppSettings.self, forKey: .settings)) ?? AppSettings()
        completed = (try? c.decode([Int].self, forKey: .completed)) ?? []
        days = (try? c.decode([String: Int].self, forKey: .days)) ?? [:]
        last = try? c.decode(Position.self, forKey: .last)
    }
}

// MARK: - Store

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var settings: AppSettings {
        didSet { if settings != oldValue { save() } }
    }
    @Published private(set) var completed: Set<Int>
    @Published private(set) var days: [String: Int]
    @Published private(set) var last: Position?

    private let fileURL: URL
    private let persist: Bool

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("user.json")
        var data: UserData
        if let demo = Demo.userData() {
            data = demo
            persist = false
        } else {
            let raw = try? Data(contentsOf: fileURL)
            if let raw, let decoded = try? JSONDecoder().decode(UserData.self, from: raw) {
                data = decoded
            } else {
                if raw != nil {
                    // An unreadable file is set aside, not overwritten, so the progress in it is not lost.
                    let aside = dir.appendingPathComponent("user-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                    try? FileManager.default.moveItem(at: fileURL, to: aside)
                }
                data = UserData()
            }
            persist = true
        }
        data.settings.repeatCount = min(max(data.settings.repeatCount, 1), 10)
        data.settings.fixedPause = min(max(data.settings.fixedPause, 2), 30)
        if !AppSettings.speeds.contains(data.settings.speed) { data.settings.speed = 1 }
        data.settings.quranFontSize = min(max(data.settings.quranFontSize, AppSettings.fontRange.lowerBound), AppSettings.fontRange.upperBound)
        settings = data.settings
        completed = Set(data.completed)
        days = data.days
        last = data.last
    }

    private func save() {
        guard persist else { return }
        var d = UserData()
        d.settings = settings
        d.completed = completed.sorted()
        d.days = days
        d.last = last
        guard let data = try? JSONEncoder().encode(d) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Progress

    /// Gregorian days in the local time zone, whatever calendar the phone shows (many users pick the Hijri one),
    /// so the keys stay the same if that setting changes.
    nonisolated static var dayCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        let c = dayCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func markCompleted(surah: Int, ayah: Int) {
        guard ayah >= 1 else { return }
        completed.insert(Quran.shared.globalIndex(surah, ayah))
        days[AppStore.dayKey(Date()), default: 0] += 1
        save()
    }

    func setPosition(surah: Int, ayah: Int) {
        guard ayah >= 1 else { return }
        if last?.surah == surah && last?.ayah == ayah { return }
        last = Position(surah: surah, ayah: ayah, date: Date())
        save()
    }

    func completedCount(surah s: Int) -> Int {
        let info = Quran.shared.surah(s)
        return (info.firstIndex..<(info.firstIndex + info.ayahCount)).reduce(0) { $0 + (completed.contains($1) ? 1 : 0) }
    }

    func completedCount(juz j: Int) -> Int {
        Quran.shared.juzRange(j).reduce(0) { $0 + (completed.contains($1) ? 1 : 0) }
    }

    func isCompleted(surah s: Int, ayah a: Int) -> Bool {
        completed.contains(Quran.shared.globalIndex(s, a))
    }

    var todayCount: Int { days[AppStore.dayKey(Date())] ?? 0 }

    var practiceDays: Int { days.values.filter { $0 > 0 }.count }

    /// Consecutive days with practice, ending today (or yesterday, so the streak holds until today ends).
    var streak: Int {
        let cal = AppStore.dayCalendar
        var day = cal.startOfDay(for: Date())
        if (days[AppStore.dayKey(day)] ?? 0) == 0 {
            guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var count = 0
        while (days[AppStore.dayKey(day)] ?? 0) > 0 {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    /// Surahs with at least one completed ayah, in mushaf order.
    var startedSurahs: [SurahInfo] {
        Quran.shared.surahs.filter { completedCount(surah: $0.number) > 0 }
    }
}
