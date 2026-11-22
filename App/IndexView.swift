import SwiftUI

struct MushafIndexView: View {
    enum Mode: Hashable { case surahs, juz }

    @State private var mode: Mode = Demo.screen == "juz" ? .juz : .surahs
    @State private var query = ""
    @EnvironmentObject private var downloads: Downloads
    @Environment(\.palette) private var p

    private var surahs: [SurahInfo] {
        let q = Search.normalize(query)
        guard !q.isEmpty else { return Quran.shared.surahs }
        let number = Int(Arabic.latinDigits(q))
        return Quran.shared.surahs.filter { s in
            if let number { return s.number == number }
            return Search.normalize(s.name).contains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if query.isEmpty {
                    PillPicker(selection: $mode, options: [(value: Mode.surahs, title: "السور"), (value: Mode.juz, title: "الأجزاء")])
                        .padding(.bottom, 4)
                }
                if let error = downloads.lastError {
                    Text(error)
                        .font(AppFont.ui(14))
                        .foregroundStyle(p.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(p.warnSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if mode == .surahs || !query.isEmpty {
                    ForEach(surahs) { s in
                        SurahRow(info: s)
                    }
                    if surahs.isEmpty {
                        Text("لا توجد سورة بهذا الاسم")
                            .font(AppFont.ui(15))
                            .foregroundStyle(p.ink2)
                            .padding(.top, 30)
                    }
                } else {
                    ForEach(1...30, id: \.self) { j in
                        JuzRow(juz: j)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .screenBackground(p)
        .navigationTitle("المصحف")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "ابحث باسم السورة أو رقمها")
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }
}

enum Search {
    /// Lets "الاسراء" find "الإسراء", "يس" find "يس" and so on.
    static func normalize(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch.value {
            case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640: continue // marks, tatweel
            case 0x0622, 0x0623, 0x0625, 0x0671: out.unicodeScalars.append("ا")
            case 0x0629: out.unicodeScalars.append("ه")
            case 0x0649: out.unicodeScalars.append("ي")
            case 0x0624: out.unicodeScalars.append("و")
            case 0x0626: out.unicodeScalars.append("ي")
            default: out.unicodeScalars.append(ch)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

extension Arabic {
    /// "٧٨" → "78"
    static func latinDigits(_ s: String) -> String {
        let map: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
                                           "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9"]
        return String(s.map { map[$0] ?? $0 })
    }
}

struct SurahRow: View {
    let info: SurahInfo
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p

    var body: some View {
        let done = store.completedCount(surah: info.number)
        HStack(spacing: 4) {
            NavigationLink(value: MushafRoute(surah: info.number, ayah: nil)) {
                HStack(spacing: 10) {
                    NumberBadge(number: info.number)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(AppFont.ui(18, .semibold))
                            .foregroundStyle(p.ink)
                        Text("\(info.typeName) · \(Arabic.ayat(info.ayahCount))")
                            .font(AppFont.ui(13))
                            .foregroundStyle(p.ink2)
                    }
                    Spacer(minLength: 4)
                    if done > 0 {
                        ProgressRing(fraction: Double(done) / Double(info.ayahCount))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(info.title)، \(info.typeName)، \(Arabic.ayat(info.ayahCount))")
            DownloadButton(surah: info.number)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(p.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.line, lineWidth: 1))
    }
}

struct JuzRow: View {
    let juz: Int
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p

    var body: some View {
        let q = Quran.shared
        let range = q.juzRange(juz)
        let start = q.ref(forGlobal: range.lowerBound)
        let end = q.ref(forGlobal: range.upperBound - 1)
        let done = store.completedCount(juz: juz)
        NavigationLink(value: MushafRoute(surah: start.surah, ayah: start.ayah)) {
            HStack(spacing: 10) {
                NumberBadge(number: juz)
                VStack(alignment: .leading, spacing: 2) {
                    Text("الجزء \(Arabic.n(juz))")
                        .font(AppFont.ui(18, .semibold))
                        .foregroundStyle(p.ink)
                    Text("من \(q.surah(start.surah).name) \(Arabic.n(start.ayah)) إلى \(q.surah(end.surah).name) \(Arabic.n(end.ayah))")
                        .font(AppFont.ui(13))
                        .foregroundStyle(p.ink2)
                }
                Spacer(minLength: 4)
                if done > 0 {
                    ProgressRing(fraction: Double(done) / Double(range.count))
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.ink2)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(p.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Downloads a surah of the chosen recitation, for listening without internet.
struct DownloadButton: View {
    let surah: Int
    @EnvironmentObject private var downloads: Downloads
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p

    var body: some View {
        let r = store.settings.reciter
        Group {
            if downloads.isDone(r, surah) {
                // A quiet filled arrow, as in Music and Podcasts; a check here would read as "finished reading".
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(p.ink2.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("محفوظة على الجهاز")
            } else if let fraction = downloads.fraction(r, surah) {
                Button {
                    downloads.cancel(r, surah)
                } label: {
                    ZStack {
                        Circle().stroke(p.surface2, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: max(0.04, fraction))
                            .stroke(p.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(p.accent)
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إيقاف التنزيل")
            } else {
                Button {
                    downloads.start(r, surah)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 21))
                        .foregroundStyle(p.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("نزّل السورة للاستماع دون إنترنت")
            }
        }
        .frame(width: 40, height: 44)
    }
}
