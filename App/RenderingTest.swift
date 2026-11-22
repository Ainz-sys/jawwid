import SwiftUI

/// Screenshot-only page (`-jawwidDemo marks-test`): compares ways of drawing pause marks, and checks that
/// colouring letters inside a word keeps them joined (needed for the tajweed colours of phase 2).
/// Every word comes from the bundled Tanzil text.
struct RenderingTestView: View {
    private let p = Palette.light
    private let size: CGFloat = 26

    var body: some View {
        let q = Quran.shared
        let w22 = q.words(2, 2)
        let rayb = w22[3].text
        let mark = w22[3].marks ?? ""
        let fihi = w22[4].text
        let rahman = q.words(1, 1)[2].text
        let maa = q.words(78, 14)[3].text
        let inna = q.words(97, 1)[0].text
        let sajdah = q.words(7, 206).last ?? DisplayWord(text: "", marks: nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                row("A — مسافة ثم العلامة (كما في الملف)", Text(rayb + " " + mark + " " + fihi))
                row("B — مسافة غير فاصلة ثم العلامة", Text(rayb + "\u{00A0}" + mark + " " + fihi))
                row("C — العلامة ملتصقة بآخر الكلمة", Text(rayb + mark + " " + fihi))
                row("D — العلامة على تطويل شفاف", HStack(spacing: 6) {
                    Text(rayb)
                    Text(clearBase(mark))
                    Text(fihi)
                })
                row("D2 — مثل D مرفوعة", HStack(spacing: 6) {
                    Text(rayb)
                    Text(clearBase(mark)).offset(y: -0.32 * size)
                    Text(fihi)
                })
                row("E — التطويل ظاهراً (مرجع)", Text(MushafLayout.markBase + mark))
                row("F — بلا تلوين (مرجع)", Text(rahman))
                row("F — تلوين داخل الكلمة", colored(rahman, [(0..<2, Color(hex: 0x858880)), (9..<10, Color(hex: 0xA27200))]))
                row("G — بلا تلوين / ملوّن", HStack(spacing: 18) {
                    Text(maa)
                    colored(maa, [(2..<4, Color(hex: 0xCF3B2B))])
                })
                row("H — بلا تلوين / ملوّن", HStack(spacing: 18) {
                    Text(inna)
                    colored(inna, [(2..<5, Color(hex: 0x2B7A3D)), (5..<7, Color(hex: 0xCF3B2B))])
                })
                row("I — علامة السجدة", Text(sajdah.shown))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .background(p.paper)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func row<V: View>(_ label: String, _ view: V) -> some View {
        HStack(spacing: 12) {
            Text(label).font(AppFont.ui(11)).foregroundStyle(p.ink2).frame(width: 150, alignment: .leading)
            view
                .font(AppFont.quran(size))
                .foregroundStyle(p.ink)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(Color.white.opacity(0.6))
        }
    }

    private func clearBase(_ mark: String) -> AttributedString {
        var base = AttributedString(MushafLayout.markBase)
        base.foregroundColor = .clear
        var m = AttributedString(mark)
        m.foregroundColor = p.ink
        return base + m
    }

    /// Colours ranges of Unicode scalars, the way tajweed annotations are given.
    private func colored(_ word: String, _ spans: [(Range<Int>, Color)]) -> Text {
        let scalars = Array(word.unicodeScalars)
        func color(_ i: Int) -> Color { spans.first(where: { $0.0.contains(i) })?.1 ?? p.ink }
        var out = AttributedString()
        var i = 0
        while i < scalars.count {
            let c = color(i)
            var j = i + 1
            while j < scalars.count && color(j) == c { j += 1 }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[i..<j])
            var part = AttributedString(String(view))
            part.foregroundColor = c
            out += part
            i = j
        }
        return Text(out)
    }
}
