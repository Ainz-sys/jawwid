import CoreText
import SwiftUI
import UIKit

/// One drawn piece of a mushaf line: a word (with any marks after it) or an ayah-end sign.
struct MushafItem: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case word
        /// Ayah-end sign with its number.
        case marker
        /// Pause mark (ۖ ۗ ۚ ۛ …): drawn on an invisible tatweel in the gap after its word.
        case pause
        /// Sajdah sign ۩ or rub el hizb ۞.
        case symbol
    }
    let kind: Kind
    /// 0 = the basmala line.
    let ayah: Int
    /// Index of the word in its ayah (−1 for the ayah-end sign).
    let word: Int
    let text: String
    /// Left edge inside the line, in left-to-right coordinates (the line is laid out from the right).
    let x: CGFloat
    let width: CGFloat
}

struct MushafLine: Identifiable, Equatable, Sendable {
    let id: Int
    let items: [MushafItem]
    let firstAyah: Int
    let lastAyah: Int

    func contains(ayah a: Int) -> Bool { a >= firstAyah && a <= lastAyah }
}

/// The whole surah broken into lines for a given width and font size, like a printed mushaf:
/// words flow from right to left, full lines are justified, and an ayah never ends a line without its number.
struct MushafLayout: Sendable {
    let surah: Int
    let width: CGFloat
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let basmala: [MushafLine]
    let lines: [MushafLine]
    private let firstLine: [Int: Int]

    /// Id of the first line that shows the ayah (0 = basmala).
    func lineID(forAyah a: Int) -> Int? {
        if a == 0 { return basmala.first?.id }
        guard let i = firstLine[a] else { return nil }
        return lines[i].id
    }

    /// Position of that line among all drawn lines, basmala lines first.
    func row(forAyah a: Int) -> Int? {
        if a == 0 { return basmala.isEmpty ? nil : 0 }
        guard let i = firstLine[a] else { return nil }
        return basmala.count + i
    }

    static func ayahSign(_ a: Int) -> String { "\u{06DD}" + Arabic.n(a) }

    /// Pause marks are combining marks; the rest (۩ ۞) are standalone symbols.
    static func isPauseMark(_ s: String) -> Bool {
        guard let v = s.unicodeScalars.first?.value else { return false }
        return v >= 0x06D6 && v <= 0x06DC
    }

    /// Tatweel that carries a pause mark; drawn transparent.
    static let markBase = "\u{0640}"

    private struct Part {
        let kind: MushafItem.Kind
        let ayah: Int
        let word: Int
        let text: String
        let width: CGFloat
    }

    private struct Unit {
        var parts: [Part] = []
        var width: CGFloat = 0
    }

    private enum Alignment { case justified, centered }

    static func measure(_ text: String, font: UIFont) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        return ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    static func build(surah s: Int, width: CGFloat, fontSize: CGFloat) -> MushafLayout {
        let font = AppFont.uiQuranFont(fontSize)
        let space = (fontSize * 0.32).rounded()
        let inner = (fontSize * 0.16).rounded()
        let quran = Quran.shared
        let info = quran.surah(s)

        var units: [Unit] = []
        for a in 1...info.ayahCount {
            let words = quran.words(s, a)
            for (i, w) in words.enumerated() {
                var unit = Unit()
                unit.parts.append(Part(kind: .word, ayah: a, word: i, text: w.text, width: measure(w.text, font: font)))
                for mark in (w.marks ?? "").split(separator: " ").map(String.init) {
                    if isPauseMark(mark) {
                        unit.parts.append(Part(kind: .pause, ayah: a, word: i, text: mark, width: measure(markBase + mark, font: font)))
                    } else {
                        unit.parts.append(Part(kind: .symbol, ayah: a, word: i, text: mark, width: measure(mark, font: font)))
                    }
                }
                if i == words.count - 1 {
                    let sign = ayahSign(a)
                    unit.parts.append(Part(kind: .marker, ayah: a, word: -1, text: sign, width: measure(sign, font: font)))
                }
                unit.width = unit.parts.reduce(0) { $0 + $1.width } + inner * CGFloat(unit.parts.count - 1)
                units.append(unit)
            }
        }
        let lines = layout(units, width: width, space: space, inner: inner, alignment: .justified, firstID: 0)

        var basmala: [MushafLine] = []
        if info.hasBasmalaHeader {
            var bunits: [Unit] = []
            for (i, w) in quran.basmalaWords(for: s).enumerated() {
                let shown = w.shown
                let width = measure(shown, font: font)
                bunits.append(Unit(parts: [Part(kind: .word, ayah: 0, word: i, text: shown, width: width)], width: width))
            }
            basmala = layout(bunits, width: width, space: space, inner: inner, alignment: .centered, firstID: -100)
        }

        var first: [Int: Int] = [:]
        for (i, line) in lines.enumerated() {
            for item in line.items where first[item.ayah] == nil { first[item.ayah] = i }
        }
        return MushafLayout(surah: s, width: width, fontSize: fontSize, lineHeight: (fontSize * 2.15).rounded(),
                            basmala: basmala, lines: lines, firstLine: first)
    }

    private static func layout(_ units: [Unit], width: CGFloat, space: CGFloat, inner: CGFloat,
                               alignment: Alignment, firstID: Int) -> [MushafLine] {
        var groups: [[Unit]] = []
        var current: [Unit] = []
        var used: CGFloat = 0
        for u in units {
            if current.isEmpty {
                current = [u]
                used = u.width
            } else if used + space + u.width <= width {
                current.append(u)
                used += space + u.width
            } else {
                groups.append(current)
                current = [u]
                used = u.width
            }
        }
        if !current.isEmpty { groups.append(current) }

        var lines: [MushafLine] = []
        for (gi, group) in groups.enumerated() {
            let natural = group.reduce(0) { $0 + $1.width } + space * CGFloat(max(group.count - 1, 0))
            var gap = space
            var right = width
            switch alignment {
            case .justified:
                // Spread full lines to both edges; the last line of the surah stays as it is.
                if gi < groups.count - 1, group.count > 1 {
                    let extra = (width - natural) / CGFloat(group.count - 1)
                    if extra <= space * 2.5 { gap = space + extra }
                }
            case .centered:
                right = width - max(0, (width - natural) / 2)
            }
            var items: [MushafItem] = []
            for unit in group {
                var r = right
                for part in unit.parts {
                    let x = r - part.width
                    items.append(MushafItem(kind: part.kind, ayah: part.ayah, word: part.word, text: part.text, x: x, width: part.width))
                    r = x - inner
                }
                right = r + inner - gap
            }
            let ayahs = items.map { $0.ayah }
            lines.append(MushafLine(id: firstID + gi, items: items, firstAyah: ayahs.min() ?? 0, lastAyah: ayahs.max() ?? 0))
        }
        return lines
    }
}

/// Draws one line: the current ayah's band, the word being recited, and taps on words.
struct MushafLineView: View {
    let line: MushafLine
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    /// The ayah to mark, when this line shows it.
    let activeAyah: Int?
    /// Words being recited in that ayah.
    let activeWords: Range<Int>?
    let palette: Palette
    let onTap: (Int) -> Void

    /// Moves the glyphs so their ink, not their tall font box, sits in the middle of the line.
    private var textOffset: CGFloat { -0.28 * fontSize }

    /// Amiri Quran draws pause marks 1.32–1.52 em above the baseline, high enough to clear any stack of
    /// harakat on a letter. In the gap between words there is nothing to clear, and at that height a mark
    /// sits nearer the line above than its own; lowered by a third of an em it sits just above its line's harakat.
    private var pauseDrop: CGFloat { 0.33 * fontSize }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let band = ayahBand {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.ayahHighlight)
                    .frame(width: band.width, height: band.height)
                    .position(x: band.midX, y: band.midY)
            }
            ForEach(Array(line.items.enumerated()), id: \.offset) { _, item in
                itemView(item)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var ayahBand: CGRect? {
        guard let a = activeAyah else { return nil }
        let parts = line.items.filter { $0.ayah == a }
        guard let minX = parts.map({ $0.x }).min(), let maxX = parts.map({ $0.x + $0.width }).max() else { return nil }
        // Tall enough to hold the pause marks above the words and the kasras below them.
        let h = min(fontSize * 1.9, height - 4)
        return CGRect(x: minX - 6, y: (height - h) / 2, width: maxX - minX + 12, height: h)
    }

    private func isLit(_ item: MushafItem) -> Bool {
        guard item.kind == .word, item.ayah == activeAyah, let r = activeWords else { return false }
        return r.contains(item.word)
    }

    private func content(_ item: MushafItem) -> Text {
        switch item.kind {
        case .word, .symbol:
            return Text(item.text).foregroundStyle(palette.ink)
        case .marker:
            return Text(item.text).foregroundStyle(palette.gold)
        case .pause:
            var base = AttributedString(MushafLayout.markBase)
            base.foregroundColor = .clear
            var mark = AttributedString(item.text)
            mark.foregroundColor = palette.ink
            return Text(base + mark)
        }
    }

    @ViewBuilder
    private func itemView(_ item: MushafItem) -> some View {
        let lit = isLit(item)
        content(item)
            .font(AppFont.quran(fontSize))
            .fixedSize()
            .offset(y: item.kind == .pause ? textOffset + pauseDrop : textOffset)
            .frame(width: item.width + 4, height: height)
            .background {
                if lit {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.wordHighlight)
                        .frame(width: item.width + 10, height: fontSize * 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap(item.ayah) }
            .position(x: item.x + item.width / 2, y: height / 2)
            .accessibilityHidden(true)
    }
}
