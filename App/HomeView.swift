import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: PlaybackEngine
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { chips }
                    VStack(alignment: .leading, spacing: 8) { chips }
                }
                if let last = store.last {
                    continueCard(last)
                } else {
                    startCard
                }
                quickStart
                TipCard()
                Text("هذه النسخة الأولى: المصحف والمشغّل. دروس التجويد والتسجيل تصل في النسخ القادمة بإذن الله.")
                    .font(AppFont.ui(13))
                    .foregroundStyle(p.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .screenBackground(p)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }

    @ViewBuilder
    private var chips: some View {
        InfoChip(systemImage: "calendar", text: "أيام متتالية: \(Arabic.n(store.streak))")
        InfoChip(systemImage: "checkmark.seal", text: "آيات اليوم: \(Arabic.n(store.todayCount))")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("السلام عليكم")
                    .font(AppFont.ui(17))
                    .foregroundStyle(p.ink2)
                Text("تلاوة اليوم")
                    .font(AppFont.ui(34, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(p.ink)
            }
            Spacer()
            CircleIconButton(systemName: "slider.horizontal.3", label: "الإعدادات") {
                router.homePath.append(.settings)
            }
        }
    }

    private func continueCard(_ last: Position) -> some View {
        let info = Quran.shared.surah(last.surah)
        let done = store.completedCount(surah: last.surah)
        return Card(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("تابع التلاوة")
                    .font(AppFont.ui(14, .semibold))
                    .foregroundStyle(p.accent)
                Text("\(info.title) · الآية \(Arabic.n(last.ayah))")
                    .font(AppFont.ui(21, .bold))
                    .foregroundStyle(p.ink)
                HStack {
                    Text("الجزء \(Arabic.n(Quran.shared.juz(last.surah, last.ayah)))")
                    Spacer()
                    Text("أنجزت \(Arabic.n(done)) من \(Arabic.n(info.ayahCount))")
                }
                .font(AppFont.ui(14))
                .foregroundStyle(p.ink2)
                ProgressLine(fraction: Double(done) / Double(max(info.ayahCount, 1)))
                // The teacher recording always plays the whole surah.
                PrimaryButton(title: store.settings.reciter.isAyahByAyah ? "تابع من الآية \(Arabic.n(last.ayah))" : "استمع إلى السورة كاملة",
                              systemImage: "play.fill") {
                    router.open(surah: last.surah, ayah: last.ayah)
                    engine.start(surah: last.surah, at: last.ayah)
                }
            }
        }
    }

    private var startCard: some View {
        Card(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ابدأ رحلتك")
                    .font(AppFont.ui(14, .semibold))
                    .foregroundStyle(p.accent)
                Text("استمع إلى الشيخ المنشاوي آيةً آية، وكرّر خلفه")
                    .font(AppFont.ui(20, .bold))
                    .foregroundStyle(p.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("يتوقف المشغّل بعد كل آية لتكرّرها، ثم يعيدها أو ينتقل إلى التي تليها.")
                    .font(AppFont.ui(15))
                    .foregroundStyle(p.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "ابدأ بسورة الفاتحة", systemImage: "play.fill") {
                    router.open(surah: 1, ayah: nil)
                    engine.start(surah: 1, at: 1)
                }
            }
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "من أين تبدأ")
            QuickRow(title: "سورة الفاتحة", subtitle: "٧ آيات · أول ما يُتعلَّم", systemImage: "sparkles") {
                router.open(surah: 1, ayah: nil)
            }
            QuickRow(title: "جزء عمّ", subtitle: "من سورة النبأ إلى سورة الناس", systemImage: "book") {
                router.open(surah: 78, ayah: nil)
            }
            QuickRow(title: "فهرس المصحف", subtitle: "كل السور والأجزاء", systemImage: "list.bullet") {
                router.tab = .mushaf
                router.mushafPath = []
            }
        }
    }
}

private struct QuickRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(p.accent)
                    .frame(width: 42, height: 42)
                    .background(p.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.ui(17, .semibold)).foregroundStyle(p.ink)
                    Text(subtitle).font(AppFont.ui(13)).foregroundStyle(p.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.ink2)
            }
            .padding(14)
            .background(p.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One etiquette of recitation each day, with its ayah from the bundled text.
struct TipCard: View {
    @Environment(\.palette) private var p

    private struct Tip {
        let text: String
        let surah: Int
        let ayah: Int
    }

    private static let tips = [
        Tip(text: "الاستعاذة قبل القراءة؛ قال تعالى:", surah: 16, ayah: 98),
        Tip(text: "ترتيل القراءة: التمهّل فيها وتبيين حروفها؛ قال تعالى:", surah: 73, ayah: 4),
        Tip(text: "تدبّر المعاني غاية التلاوة؛ قال تعالى:", surah: 38, ayah: 29),
        Tip(text: "الإنصات عند سماع القرآن؛ قال تعالى:", surah: 7, ayah: 204),
    ]

    private var tip: Tip {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return TipCard.tips[day % TipCard.tips.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("من آداب التلاوة")
                .font(AppFont.ui(14, .semibold))
                .foregroundStyle(p.gold)
            Text(tip.text)
                .font(AppFont.ui(16))
                .foregroundStyle(p.ink)
                .fixedSize(horizontal: false, vertical: true)
            AyahQuote(surah: tip.surah, ayah: tip.ayah, size: 24)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.goldSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
