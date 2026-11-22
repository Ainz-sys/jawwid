import SwiftUI
import XCTest
@testable import Jawwid

/// Runs on an iPhone simulator in CI (the "test" job). The playback and download tests use the network.
@MainActor
final class JawwidTests: XCTestCase {

    // MARK: - Bundled data

    func testBundledTextAndStructure() {
        let q = Quran.shared
        XCTAssertEqual(q.surahs.count, 114)
        XCTAssertEqual(q.ayahTotal, 6236)
        XCTAssertEqual(q.surahs.reduce(0) { $0 + $1.ayahCount }, 6236)
        XCTAssertEqual(q.juzStarts.count, 30)
        XCTAssertEqual(q.juz(1, 1), 1)
        XCTAssertEqual(q.juz(2, 142), 2)
        XCTAssertEqual(q.juz(78, 1), 30)
        XCTAssertEqual(q.juz(114, 6), 30)
        XCTAssertEqual(q.globalIndex(114, 6), 6235)
        XCTAssertFalse(q.notice.isEmpty, "the Tanzil notice must be kept")
        for s in q.surahs {
            XCTAssertEqual(s.hasBasmalaHeader, s.number != 1 && s.number != 9)
            for a in 1...s.ayahCount {
                XCTAssertFalse(q.words(s.number, a).isEmpty, "\(s.number):\(a) has no words")
            }
        }
    }

    /// A pause mark is its own token after a space, though a space and a combining mark make one grapheme.
    func testPauseMarksAreSplitFromTheirWords() {
        let words = Quran.shared.words(2, 2)
        XCTAssertEqual(words.count, 7)
        XCTAssertEqual(words[3].text, "\u{0631}\u{064E}\u{064A}\u{0652}\u{0628}\u{064E}") // رَيْبَ
        XCTAssertEqual(words[3].marks, "\u{06DB}")
        XCTAssertEqual(words[4].text, "\u{0641}\u{0650}\u{064A}\u{0647}\u{0650}") // فِيهِ
        XCTAssertEqual(words[4].marks, "\u{06DB}")
        var marked = 0
        for s in Quran.shared.surahs {
            for a in 1...s.ayahCount {
                for w in Quran.shared.words(s.number, a) {
                    XCTAssertFalse(w.text.unicodeScalars.contains { (0x06D6...0x06DC).contains($0.value) },
                                   "\(s.number):\(a) “\(w.text)” still carries a pause mark")
                    marked += Quran.spaceSeparated(w.marks ?? "").count
                }
            }
        }
        XCTAssertEqual(marked, 4379, "pause and sajdah marks in the text")
    }

    /// Every timed segment must point at words that exist in the text, or the highlight lands on the wrong word.
    func testWordTimingsMatchTheText() async {
        let q = Quran.shared
        for resource in ["timings-murattal", "timings-mujawwad"] {
            guard let t = await TimingStore.shared.timings(for: resource) else {
                XCTFail("\(resource) did not load")
                continue
            }
            XCTAssertEqual(t.count, q.ayahTotal)
            var bad: [String] = []
            var timed = 0
            for s in q.surahs {
                for a in 1...s.ayahCount {
                    let words = q.words(s.number, a).count
                    let segments = Timings.segments(t[q.globalIndex(s.number, a)])
                    if !segments.isEmpty { timed += 1 }
                    var last = -1.0
                    for seg in segments {
                        if seg.firstWord < 0 || seg.firstWord >= seg.endWord || seg.endWord > words || seg.start < last {
                            bad.append("\(s.number):\(a) \(seg.firstWord)..<\(seg.endWord) of \(words)")
                        }
                        last = seg.start
                    }
                }
            }
            XCTAssertTrue(bad.isEmpty, "\(resource): \(bad.count) bad segments, e.g. \(bad.prefix(8))")
            XCTAssertGreaterThan(timed, 6200, "\(resource): only \(timed) ayat have timings")
        }
    }

    // MARK: - Mushaf layout

    func testEveryAyahIsLaidOutWithinTheLine() {
        let width: CGFloat = 347 // iPhone SE width without the page margins
        var problems: [String] = []
        for size in [22.0, 30.0, 44.0] {
            for s in 1...114 {
                let layout = MushafLayout.build(surah: s, width: width, fontSize: size)
                for a in 1...Quran.shared.surah(s).ayahCount where layout.lineID(forAyah: a) == nil {
                    problems.append("\(s):\(a) has no line at \(size)")
                }
                for line in layout.lines {
                    if line.items.isEmpty { problems.append("empty line in \(s) at \(size)") }
                    for item in line.items where item.x < -0.5 || item.x + item.width > width + 0.5 {
                        problems.append("\(s):\(item.ayah) “\(item.text)” outside the line at \(size)")
                    }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "\(problems.count) problems, e.g. \(problems.prefix(10))")
    }

    func testPauseMarkOutlines() {
        for v in 0x06D6...0x06DC {
            let mark = String(UnicodeScalar(v)!)
            let box = MushafLayout.glyphBox(mark, fontSize: 30)
            XCTAssertNotNil(box, "no glyph for U+\(String(v, radix: 16))")
            XCTAssertGreaterThan(box?.width ?? 0, 1)
            XCTAssertNotNil(PauseMarkShapes.shape(mark, fontSize: 30), "no outline for U+\(String(v, radix: 16))")
        }
    }

    /// Renders the first line of al-Baqarah (with ۛ after رَيْبَ and فِيهِ) and finds where each pause mark's ink lands.
    func testPauseMarksAreDrawnAboveTheirOwnLine() throws {
        let fontSize: CGFloat = 30
        let width: CGFloat = 374
        let layout = MushafLayout.build(surah: 2, width: width, fontSize: fontSize)
        guard let line = layout.lines.first(where: { $0.items.contains { $0.kind == .pause } }) else {
            return XCTFail("no line with a pause mark in al-Baqarah")
        }
        print("LINE ITEMS: " + line.items.map { "\($0.kind) \($0.text) x=\(Int($0.x)) w=\(Int($0.width))" }.joined(separator: " | "))
        XCTAssertNotNil(PauseMarkShapes.shape("\u{06DB}", fontSize: fontSize), "no outline for ۛ")

        // Room above and below, so ink outside the line's frame shows up too.
        let pad: CGFloat = 40
        let view = MushafLineView(line: line, width: width, height: layout.lineHeight, fontSize: fontSize,
                                  activeAyah: nil, activeWords: nil, palette: .light, onTap: { _ in })
            .padding(.vertical, pad)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return XCTFail("nothing rendered") }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(drawn)
        func ink(_ x: Int, _ y: Int) -> Bool { pixels[(y * w + x) * 4 + 3] > 100 } // rows run top to bottom

        let font = AppFont.uiQuranFont(fontSize)
        let baseline = pad + layout.lineHeight / 2 - 0.28 * fontSize - font.lineHeight / 2 + font.ascender
        var report: [String] = []
        for item in line.items where item.kind == .pause {
            let x0 = max(0, Int(item.x) + 1), x1 = min(w - 1, max(Int(item.x) + 1, Int(item.x + item.width) - 1))
            let rows = (0..<h).filter { y in (x0...x1).contains { ink($0, y) } }
            guard let top = rows.first, let bottom = rows.last else {
                report.append("\(item.text) at x \(Int(item.x)): no ink")
                continue
            }
            report.append("\(item.text) at x \(Int(item.x)): ink rows \(top)...\(bottom), baseline \(Int(baseline))")
            // The mark's centre should be about one em above the words' baseline, inside the line.
            let centre = CGFloat(top + bottom) / 2
            XCTAssertEqual(centre, baseline - fontSize, accuracy: 0.2 * fontSize, report.last ?? "")
            XCTAssertGreaterThanOrEqual(CGFloat(top), pad, "the mark pokes above its line: \(report.last ?? "")")
        }
        print("PAUSE MARKS: " + report.joined(separator: " | "))
    }

    // MARK: - Words and numbers

    func testArabicPlurals() {
        XCTAssertEqual(Arabic.ayat(1), "آية واحدة")
        XCTAssertEqual(Arabic.ayat(2), "آيتان")
        XCTAssertEqual(Arabic.ayat(7), "٧ آيات")
        XCTAssertEqual(Arabic.ayat(11), "١١ آية")
        XCTAssertEqual(Arabic.ayat(109), "١٠٩ آيات")
        XCTAssertEqual(Arabic.ayat(110), "١١٠ آيات")
        XCTAssertEqual(Arabic.ayat(111), "١١١ آية")
        XCTAssertEqual(Arabic.ayat(200), "٢٠٠ آية")
        XCTAssertEqual(Arabic.ayat(286), "٢٨٦ آية")
        XCTAssertEqual(Arabic.times(3), "٣ مرات")
        XCTAssertEqual(Arabic.seconds(30), "٣٠ ثانية")
        XCTAssertEqual(Arabic.suwar(2), "سورتان")
        XCTAssertEqual(Arabic.suwar(5), "٥ سور")
        XCTAssertEqual(Arabic.time(75), "١:١٥")
        XCTAssertEqual(Arabic.decimal(0.75), "٠٫٧٥")
    }

    func testWholePercent() {
        XCTAssertEqual(wholePercent(0), 0)
        XCTAssertEqual(wholePercent(.nan), 0)
        XCTAssertEqual(wholePercent(0.0001), 1)
        XCTAssertEqual(wholePercent(0.5), 50)
        XCTAssertEqual(wholePercent(0.999), 99)
        XCTAssertEqual(wholePercent(1), 100)
    }

    func testDayKeysAreGregorian() {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 22; c.hour = 12
        let date = AppStore.dayCalendar.date(from: c)!
        XCTAssertEqual(AppStore.dayKey(date), "2026-11-22")
    }

    // MARK: - Playback (network)

    /// Basmala and two ayat of an-Nas, each heard twice with the learner's pause after every recitation.
    func testAyahByAyahWithRepeatsAndPauses() async throws {
        let store = AppStore.shared
        store.settings.reciter = .murattal
        store.settings.repeatCount = 2
        store.settings.pauseMode = .fixed
        store.settings.fixedPause = 2
        store.settings.autoAdvance = true
        store.settings.speed = 1.25
        store.settings.playBasmala = true
        let engine = PlaybackEngine.shared
        engine.start(surah: 114, at: 1, rangeStart: 1, rangeEnd: 2)

        var log: [String] = []
        var litWords = Set<Int>()
        let end = Date().addingTimeInterval(180)
        while Date() < end {
            let entry = "\(engine.phase) \(engine.ayah) \(engine.repetition)/\(engine.repetitions)"
            if log.last != entry { log.append(entry) }
            if engine.phase == .reciting, engine.ayah == 1, let w = engine.wordRange { litWords.formUnion(w) }
            if engine.phase == .finished { break }
            if case .failed = engine.phase { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        print("PLAYBACK LOG: " + log.joined(separator: " | "))
        XCTAssertEqual(engine.phase, .finished, log.joined(separator: " | "))

        var expected: [String] = []
        for a in 0...2 {
            for r in 1...2 { expected += ["reciting \(a) \(r)/2", "gap \(a) \(r)/2"] }
        }
        var core: [String] = []
        for entry in log where expected.contains(entry) && core.last != entry { core.append(entry) }
        XCTAssertEqual(core, expected)
        XCTAssertFalse(litWords.isEmpty, "no word was highlighted in ayah 1")
        XCTAssertTrue(store.completed.contains(Quran.shared.globalIndex(114, 1)))
        XCTAssertTrue(store.completed.contains(Quran.shared.globalIndex(114, 2)))
        engine.stop()
        store.settings.speed = 1
    }

    /// Manual mode stops after the ayah and goes on with "next".
    func testManualAdvanceWaitsForNext() async throws {
        let store = AppStore.shared
        store.settings.reciter = .murattal
        store.settings.repeatCount = 1
        store.settings.pauseMode = .none
        store.settings.autoAdvance = false
        store.settings.speed = 1.25
        let engine = PlaybackEngine.shared
        engine.start(surah: 112, at: 2, rangeStart: 2, rangeEnd: 3)
        let waited = try await waitUntil(90) { engine.phase == .waiting || self.failed(engine) }
        XCTAssertTrue(waited && engine.phase == .waiting && engine.ayah == 2, "phase \(engine.phase) ayah \(engine.ayah)")
        engine.next()
        let next = try await waitUntil(60) { (engine.phase == .reciting && engine.ayah == 3) || self.failed(engine) }
        XCTAssertTrue(next, "phase \(engine.phase) ayah \(engine.ayah)")
        engine.stop()
        store.settings.autoAdvance = true
        store.settings.pauseMode = .ayahLength
        store.settings.speed = 1
    }

    func testTeacherRecordingPlaysTheWholeSurah() async throws {
        let store = AppStore.shared
        store.settings.reciter = .teacher
        let engine = PlaybackEngine.shared
        engine.start(surah: 1, at: 1)
        let playing = try await waitUntil(90) { (engine.phase == .listening && engine.clock.elapsed > 2) || self.failed(engine) }
        XCTAssertTrue(playing, "phase \(engine.phase) elapsed \(engine.clock.elapsed)")
        // A tap on an ayah cannot seek in this recording and must not stop it.
        engine.play(surah: 1, from: 4)
        XCTAssertEqual(engine.phase, .listening)
        XCTAssertTrue(engine.isActive)
        engine.stop()
        store.settings.reciter = .murattal
    }

    // MARK: - Downloads (network)

    func testDownloadPlaysFromTheDeviceThenDelete() async throws {
        let downloads = Downloads.shared
        downloads.delete(.murattal, 112)
        XCTAssertFalse(downloads.isDone(.murattal, 112))
        downloads.start(.murattal, 112)
        _ = try await waitUntil(180) { downloads.isDone(.murattal, 112) || downloads.lastError != nil }
        XCTAssertTrue(downloads.isDone(.murattal, 112), downloads.lastError ?? "timed out")
        for a in 1...4 {
            XCTAssertTrue(AudioFiles.ayahURL(.murattal, 112, a)?.isFileURL ?? false, "112:\(a) not on the device")
        }
        XCTAssertTrue(AudioFiles.exists(AudioFiles.ayahFile(.murattal, 1, 1)), "the basmala is downloaded with the surah")
        downloads.delete(.murattal, 112)
        XCTAssertFalse(downloads.isDone(.murattal, 112))
        XCTAssertFalse(AudioFiles.ayahURL(.murattal, 112, 1)?.isFileURL ?? true)
    }

    // MARK: - Helpers

    private func failed(_ engine: PlaybackEngine) -> Bool {
        if case .failed = engine.phase { return true }
        return false
    }

    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }
}
