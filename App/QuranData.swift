import Foundation

struct SurahInfo: Identifiable, Hashable {
    let number: Int
    let name: String
    let ayahCount: Int
    let meccan: Bool
    /// 0-based index of the surah's first ayah among all 6236 ayat.
    let firstIndex: Int

    var id: Int { number }
    /// Every surah opens with the basmala except al-Fatiha (where it is ayah 1) and at-Tawbah.
    var hasBasmalaHeader: Bool { number != 1 && number != 9 }
    var title: String { "سورة \(name)" }
    var typeName: String { meccan ? "مكية" : "مدنية" }
}

struct AyahRef: Hashable, Codable {
    let surah: Int
    let ayah: Int
}

/// One word as shown in the mushaf, with any pause/sajdah marks that follow it in the text.
struct DisplayWord: Hashable {
    let text: String
    let marks: String?

    /// What is drawn: the word, then its marks exactly as they follow it in the source text.
    var shown: String { marks.map { text + " " + $0 } ?? text }
}

/// The bundled Tanzil text and its structure. Immutable after loading, so it is safe to read from any thread.
final class Quran: @unchecked Sendable {
    static let shared = Quran()

    let surahs: [SurahInfo]
    /// 0-based global index of the first ayah of each juz (30 entries).
    let juzStarts: [Int]
    let source: String
    let notice: [String]
    let metaSource: String
    private let texts: [String]
    private let basmalaDefault: String
    private let basmalaVariants: [Int: String]

    private struct File: Decodable {
        struct Surah: Decodable {
            let name: String
            let ayahs: Int
            let meccan: Bool
        }
        let source: String
        let notice: [String]
        let meta: String
        let surahs: [Surah]
        let juz: [Int]
        let bismillah: [String: String]
        let text: [String]
    }

    private init() {
        guard let url = Bundle.main.url(forResource: "quran", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            fatalError("quran.json is missing from the app bundle")
        }
        var list: [SurahInfo] = []
        var start = 0
        for (i, s) in file.surahs.enumerated() {
            list.append(SurahInfo(number: i + 1, name: s.name, ayahCount: s.ayahs, meccan: s.meccan, firstIndex: start))
            start += s.ayahs
        }
        surahs = list
        juzStarts = file.juz
        texts = file.text
        source = file.source
        notice = file.notice
        metaSource = file.meta
        basmalaDefault = file.bismillah["default"] ?? file.text.first ?? ""
        var variants: [Int: String] = [:]
        for (k, v) in file.bismillah {
            if let n = Int(k) { variants[n] = v }
        }
        basmalaVariants = variants
    }

    var ayahTotal: Int { texts.count }

    func surah(_ n: Int) -> SurahInfo { surahs[max(1, min(114, n)) - 1] }

    func globalIndex(_ s: Int, _ a: Int) -> Int { surah(s).firstIndex + a - 1 }

    func ref(forGlobal g: Int) -> AyahRef {
        var lo = 0, hi = surahs.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if surahs[mid].firstIndex <= g { lo = mid } else { hi = mid - 1 }
        }
        return AyahRef(surah: lo + 1, ayah: g - surahs[lo].firstIndex + 1)
    }

    func text(_ s: Int, _ a: Int) -> String {
        let g = globalIndex(s, a)
        guard g >= 0, g < texts.count else { return "" }
        return texts[g]
    }

    func basmala(for surah: Int) -> String { basmalaVariants[surah] ?? basmalaDefault }

    /// Juz number (1…30) that contains the ayah.
    func juz(_ s: Int, _ a: Int) -> Int {
        let g = globalIndex(s, a)
        var j = 1
        for (i, start) in juzStarts.enumerated() where start <= g { j = i + 1 }
        return j
    }

    /// Global index range [start, end) of a juz.
    func juzRange(_ j: Int) -> Range<Int> {
        let start = juzStarts[j - 1]
        let end = j < juzStarts.count ? juzStarts[j] : texts.count
        return start..<end
    }

    // MARK: - Words

    private static let markScalars: Set<UInt32> = [0x06D6, 0x06D7, 0x06D8, 0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DE, 0x06E9]

    static func isMarkToken<S: StringProtocol>(_ token: S) -> Bool {
        !token.isEmpty && token.unicodeScalars.allSatisfy { markScalars.contains($0.value) }
    }

    /// Splits at each space character. Splitting the String itself would go by grapheme, and a space followed by
    /// a combining pause mark (رَيْبَ ۛ) is one grapheme, so the mark would stay glued to the word before it.
    static func spaceSeparated(_ text: String) -> [String] {
        text.unicodeScalars.split(separator: " ").map { String(String.UnicodeScalarView($0)) }
    }

    /// Splits an ayah by spaces, like the word timings do; marks join the word before them.
    static func words(in text: String) -> [DisplayWord] {
        var out: [DisplayWord] = []
        for token in spaceSeparated(text) {
            if isMarkToken(token), let last = out.last {
                let marks: String = last.marks.map { $0 + " " + token } ?? token
                out[out.count - 1] = DisplayWord(text: last.text, marks: marks)
            } else {
                out.append(DisplayWord(text: token, marks: nil))
            }
        }
        return out
    }

    func words(_ s: Int, _ a: Int) -> [DisplayWord] { Quran.words(in: text(s, a)) }

    func basmalaWords(for surah: Int) -> [DisplayWord] { Quran.words(in: basmala(for: surah)) }
}

// MARK: - Word timings

/// One timed span of an ayah recording: words [firstWord, endWord) between start and end (seconds).
struct TimedSegment: Equatable {
    let firstWord: Int
    let endWord: Int
    let start: Double
    let end: Double
}

/// Word timings (quran-align) for one recitation, loaded on first use.
actor TimingStore {
    static let shared = TimingStore()

    private struct File: Decodable {
        let reciter: String
        let ayat: [[Int]]
    }

    private var cache: [String: [[Int]]] = [:]

    func timings(for resource: String) -> [[Int]]? {
        if let t = cache[resource] { return t }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.ayat.count == Quran.shared.ayahTotal else { return nil }
        cache[resource] = file.ayat
        return file.ayat
    }
}

enum Timings {
    static func segments(_ flat: [Int]) -> [TimedSegment] {
        var out: [TimedSegment] = []
        var i = 0
        while i + 3 < flat.count {
            out.append(TimedSegment(firstWord: flat[i], endWord: flat[i + 1],
                                    start: Double(flat[i + 2]) / 1000, end: Double(flat[i + 3]) / 1000))
            i += 4
        }
        return out
    }

    /// Words being recited at `time`: the last segment that has started (kept through short pauses).
    static func words(at time: Double, in segments: [TimedSegment]) -> Range<Int>? {
        guard let first = segments.first, time >= first.start - 0.05 else { return nil }
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segments[mid].start <= time + 0.05 { lo = mid } else { hi = mid - 1 }
        }
        let s = segments[lo]
        return s.firstWord..<s.endWord
    }

    /// Length of the recited part of the ayah (end of its last word), in seconds.
    static func recitedLength(_ flat: [Int]) -> Double? {
        guard flat.count >= 4 else { return nil }
        return Double(flat[flat.count - 1]) / 1000
    }
}
