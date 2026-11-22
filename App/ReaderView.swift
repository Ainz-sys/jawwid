import SwiftUI
import UIKit

// MARK: - Reader

struct SurahReaderView: View {
    let route: MushafRoute
    @EnvironmentObject private var engine: PlaybackEngine
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p
    @State private var layout: MushafLayout?
    @State private var layoutVersion = 0
    @State private var showRepeatSettings = false
    @State private var showFont = false
    @State private var expanded = true

    private struct LayoutKey: Hashable {
        let width: CGFloat
        let font: Double
    }

    private var surah: Int { route.surah }
    private var info: SurahInfo { Quran.shared.surah(surah) }
    private var isCurrent: Bool { engine.surah == surah && engine.isActive }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - 28, 120)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        SurahHeaderView(info: info)
                            .padding(.top, 6)
                            .padding(.bottom, 10)
                            .id(Self.headerID)
                        if let layout {
                            ForEach(layout.basmala) { line in
                                lineView(line, layout)
                            }
                            ForEach(layout.lines) { line in
                                lineView(line, layout)
                            }
                        } else {
                            ProgressView()
                                .padding(.top, 80)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
                .onChange(of: layoutVersion) { _, _ in
                    scrollToStart(proxy, viewport: geo.size.height)
                }
                .onChange(of: engine.ayah) { _, a in
                    follow(a, proxy, viewport: geo.size.height)
                }
            }
            .task(id: LayoutKey(width: width, font: store.settings.quranFontSize)) {
                let s = surah
                let f = CGFloat(store.settings.quranFontSize)
                let built = await Task.detached(priority: .userInitiated) {
                    MushafLayout.build(surah: s, width: width, fontSize: f)
                }.value
                layout = built
                layoutVersion += 1
            }
        }
        .screenBackground(p)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ReaderPlayerPanel(surah: surah, expanded: $expanded, showSettings: $showRepeatSettings)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(info.title)
                        .font(AppFont.ui(17, .bold))
                        .foregroundStyle(p.ink)
                    Text(subtitle)
                        .font(AppFont.ui(12))
                        .foregroundStyle(p.ink2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFont = true
                } label: {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(p.ink)
                }
                .accessibilityLabel("حجم خط المصحف")
            }
        }
        .sheet(isPresented: $showRepeatSettings) {
            RepeatSettingsSheet(surah: surah)
                .appEnvironment(p, store: store, engine: engine)
        }
        .sheet(isPresented: $showFont) {
            FontSizeSheet()
                .appEnvironment(p, store: store, engine: engine)
        }
        .onChange(of: engine.isPlaying) { _, playing in
            // Keep the screen on while the learner follows the highlighting.
            UIApplication.shared.isIdleTimerDisabled = playing && isCurrent
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onAppear {
            if Demo.screen == "reader-compact" { expanded = false }
            switch Demo.readerSheet {
            case "settings": showRepeatSettings = true
            case "font": showFont = true
            default: break
            }
        }
    }

    private var subtitle: String {
        if isCurrent, engine.ayah >= 1 {
            return "الجزء \(Arabic.n(Quran.shared.juz(surah, engine.ayah))) · الآية \(Arabic.n(engine.ayah)) من \(Arabic.n(info.ayahCount))"
        }
        return "\(info.typeName) · \(Arabic.ayat(info.ayahCount)) · الجزء \(Arabic.n(Quran.shared.juz(surah, 1)))"
    }

    private func lineView(_ line: MushafLine, _ layout: MushafLayout) -> some View {
        let active: Int? = (isCurrent && line.contains(ayah: engine.ayah)) ? engine.ayah : nil
        return MushafLineView(line: line, width: layout.width, height: layout.lineHeight, fontSize: layout.fontSize,
                              activeAyah: active, activeWords: active == nil ? nil : engine.wordRange,
                              palette: p, onTap: { a in tapped(a) })
            .id(line.id)
    }

    private func tapped(_ a: Int) {
        engine.play(surah: surah, from: max(a, 1))
    }

    private static let headerID = -1000
    /// Height of the surah header with its padding, enough to tell which lines show before any scrolling.
    private static let headerHeight: CGFloat = 92

    /// True when the ayah's first line is in view while the surah is scrolled to its top.
    private func shownAtTop(_ a: Int, _ layout: MushafLayout, viewport: CGFloat) -> Bool {
        guard let row = layout.row(forAyah: a) else { return false }
        return Self.headerHeight + CGFloat(row + 1) * layout.lineHeight <= viewport - 8
    }

    private func scrollToStart(_ proxy: ScrollViewProxy, viewport: CGFloat) {
        guard let layout else { return }
        var target: Int?
        if isCurrent {
            target = engine.ayah
        } else if let a = route.ayah {
            target = a
        } else if let last = store.last, last.surah == surah {
            target = last.ayah
        }
        // An ayah that already shows under the surah header needs no scrolling; the header stays in view.
        guard let a = target, !shownAtTop(a, layout, viewport: viewport), let id = layout.lineID(forAyah: a) else { return }
        proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.15))
    }

    private func follow(_ a: Int, _ proxy: ScrollViewProxy, viewport: CGFloat) {
        guard isCurrent, let layout else { return }
        if shownAtTop(a, layout, viewport: viewport) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(Self.headerID, anchor: .top)
            }
        } else if let id = layout.lineID(forAyah: a) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.2))
            }
        }
    }
}

struct SurahHeaderView: View {
    let info: SurahInfo
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 4) {
            Text(info.title)
                .font(AppFont.ui(22, .bold))
                .foregroundStyle(p.ink)
            Text("\(info.typeName) · \(Arabic.ayat(info.ayahCount))")
                .font(AppFont.ui(13))
                .foregroundStyle(p.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(p.goldSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.gold.opacity(0.45), lineWidth: 1))
    }
}

// MARK: - Status text

extension PlaybackEngine {
    /// What the player is doing, in one short sentence.
    var statusLine: String {
        let n = Arabic.n(ayah)
        let paused = !isPlaying
        switch phase {
        case .idle: return ""
        case .loading: return "جارٍ تحميل التلاوة…"
        case .reciting:
            if paused { return ayah == 0 ? "متوقف مؤقتاً عند البسملة" : "متوقف مؤقتاً عند الآية \(n)" }
            if isBuffering { return "جارٍ التحميل…" }
            return ayah == 0 ? "الشيخ يقرأ البسملة" : "الشيخ يقرأ الآية \(n)"
        case .gap:
            if paused { return ayah == 0 ? "متوقف مؤقتاً عند البسملة" : "متوقف مؤقتاً عند الآية \(n)" }
            return ayah == 0 ? "دورك: كرّر البسملة" : "دورك: كرّر الآية \(n)"
        case .waiting: return "أحسنت! اضغط «التالي» للمتابعة"
        case .listening: return paused ? "متوقف مؤقتاً" : "المصحف المعلّم · ترديد الأطفال"
        case .finished: return "انتهى المقطع، بارك الله فيك"
        case .failed(let message): return message
        }
    }

    var showsRepetition: Bool {
        reciter.isAyahByAyah && repetitions > 1 && (phase == .reciting || phase == .gap)
    }
}

private func feminineOrdinal(_ n: Int) -> String {
    let words = ["", "أولى", "ثانية", "ثالثة", "رابعة", "خامسة", "سادسة", "سابعة", "ثامنة", "تاسعة", "عاشرة"]
    return n >= 1 && n < words.count ? words[n] : Arabic.n(n)
}

// MARK: - Player panel in the reader

struct ReaderPlayerPanel: View {
    let surah: Int
    @Binding var expanded: Bool
    @Binding var showSettings: Bool
    @EnvironmentObject private var engine: PlaybackEngine
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p

    private var isCurrent: Bool { engine.surah == surah && engine.isActive }

    private var startAyah: Int {
        if let last = store.last, last.surah == surah { return last.ayah }
        return 1
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCurrent {
                if expanded { full } else { compact }
            } else {
                idle
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(p.surface)
                .shadow(color: .black.opacity(0.08), radius: 14, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var idle: some View {
        HStack(spacing: 12) {
            Button {
                engine.start(surah: surah, at: startAyah)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text(startAyah > 1 ? "استمع من الآية \(Arabic.n(startAyah))" : "ابدأ الاستماع")
                        .font(AppFont.ui(17, .semibold))
                }
                .foregroundStyle(p.accentInk)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(p.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            CircleIconButton(systemName: "slider.horizontal.3", size: 52, label: "إعدادات التكرار") {
                showSettings = true
            }
        }
    }

    private var dotColor: Color {
        switch engine.phase {
        case .reciting, .listening: return engine.isPlaying ? p.accent : p.ink2
        case .gap: return engine.isPlaying ? p.gold : p.ink2
        case .failed: return p.warn
        default: return p.ink2
        }
    }

    private var statusColor: Color {
        if case .failed = engine.phase { return p.warn }
        return p.ink
    }

    /// Small iPhones keep the panel short, leaving room for the mushaf.
    private var isShortScreen: Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return (scene?.screen.bounds.height ?? 800) < 700
    }

    private var hint: String? {
        guard !isShortScreen, engine.reciter.isAyahByAyah, engine.phase == .reciting || engine.phase == .gap else { return nil }
        let s = store.settings
        let first: String
        switch s.pauseMode {
        case .ayahLength: first = "بعد انتهاء الآية يأتي دورك: يتوقف المشغّل بقدر طولها لتكرّرها"
        case .oneAndHalf: first = "بعد انتهاء الآية يأتي دورك: يتوقف المشغّل بقدر طولها مرة ونصفاً لتكرّرها"
        case .fixed: first = "بعد انتهاء الآية يأتي دورك: يتوقف المشغّل \(Arabic.seconds(s.fixedPause)) لتكرّرها"
        case .none: return "تُتلى الآيات متتابعة دون توقف بينها."
        }
        let then: String
        if engine.repetition < engine.repetitions {
            then = "، ثم يعيدها مرة \(feminineOrdinal(engine.repetition + 1))."
        } else if engine.ayah >= engine.rangeEnd {
            then = "، ثم ينتهي المقطع."
        } else if s.autoAdvance {
            then = "، ثم ينتقل إلى الآية التالية."
        } else {
            then = "، ثم ينتظر حتى تضغط «التالي»."
        }
        return first + then
    }

    private var full: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 9, height: 9)
                Text(engine.statusLine)
                    .font(AppFont.ui(17, .bold))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if engine.showsRepetition {
                    Text("المرة \(Arabic.n(engine.repetition)) من \(Arabic.n(engine.repetitions))")
                        .font(AppFont.ui(14))
                        .foregroundStyle(p.ink2)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.ink2)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("تصغير المشغّل")
            }
            PlaybackProgressBar(clock: engine.clock)
            if let hint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 15))
                    Text(hint)
                        .font(AppFont.ui(14))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(p.ink2)
            }
            controls
            if engine.reciter.isAyahByAyah {
                SecondaryButton(title: "إعدادات التكرار", systemImage: "slider.horizontal.3") {
                    showSettings = true
                }
            } else {
                SecondaryButton(title: "اختيار التلاوة", systemImage: "slider.horizontal.3") {
                    showSettings = true
                }
            }
        }
    }

    private var compact: some View {
        HStack(spacing: 12) {
            Button {
                engine.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(p.accentInk)
                    .frame(width: 46, height: 46)
                    .background(p.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "إيقاف مؤقت" : "تشغيل")
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.statusLine)
                    .font(AppFont.ui(15, .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                if engine.showsRepetition {
                    Text("المرة \(Arabic.n(engine.repetition)) من \(Arabic.n(engine.repetitions))")
                        .font(AppFont.ui(12))
                        .foregroundStyle(p.ink2)
                }
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { expanded = true }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(p.ink2)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("توسيع المشغّل")
        }
    }

    /// Media controls keep the usual left-to-right order (previous on the left), as in the design.
    private var controls: some View {
        HStack {
            if engine.reciter.isAyahByAyah {
                repeatMenu
            } else {
                Color.clear.frame(width: 64, height: 48)
            }
            Spacer()
            Button {
                engine.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(p.ink)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(engine.reciter.isAyahByAyah ? "الآية السابقة" : "من أول السورة")
            Spacer()
            Button {
                engine.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(p.accentInk)
                    .frame(width: 72, height: 72)
                    .background(p.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "إيقاف مؤقت" : "تشغيل")
            Spacer()
            Button {
                engine.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(p.ink)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(engine.reciter.isAyahByAyah ? "الآية التالية" : "السورة التالية")
            Spacer()
            speedMenu
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var repeatMenu: some View {
        Menu {
            Section("تكرار كل آية") {
                ForEach([1, 2, 3, 4, 5, 7, 10], id: \.self) { n in
                    Button {
                        store.settings.repeatCount = n
                        engine.settingsChanged()
                    } label: {
                        if n == store.settings.repeatCount {
                            Label(Arabic.times(n), systemImage: "checkmark")
                        } else {
                            Text(Arabic.times(n))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "repeat").font(.system(size: 15, weight: .medium))
                Text(Arabic.n(store.settings.repeatCount)).font(AppFont.ui(16, .semibold))
            }
            .foregroundStyle(p.ink)
            .frame(width: 64, height: 48)
            .background(p.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.line, lineWidth: 1))
        }
        .accessibilityLabel("تكرار كل آية: \(Arabic.times(store.settings.repeatCount))")
    }

    private var speedMenu: some View {
        Menu {
            Section("السرعة") {
                ForEach(AppSettings.speeds, id: \.self) { v in
                    Button {
                        engine.setSpeed(v)
                    } label: {
                        if v == store.settings.speed {
                            Label("×" + Arabic.decimal(v), systemImage: "checkmark")
                        } else {
                            Text("×" + Arabic.decimal(v))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.50percent").font(.system(size: 14, weight: .medium))
                Text("×" + Arabic.decimal(store.settings.speed)).font(AppFont.ui(15, .semibold))
            }
            .foregroundStyle(p.ink)
            .frame(width: 78, height: 48)
            .background(p.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.line, lineWidth: 1))
        }
        .accessibilityLabel("السرعة: \(Arabic.decimal(store.settings.speed))")
    }
}

struct PlaybackProgressBar: View {
    @ObservedObject var clock: PlaybackClock
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 6) {
            ProgressLine(fraction: clock.duration > 0 ? clock.elapsed / clock.duration : 0)
            HStack {
                Text(Arabic.time(clock.elapsed))
                Spacer()
                Text(Arabic.time(clock.duration))
            }
            .font(AppFont.ui(12))
            .foregroundStyle(p.ink2)
        }
    }
}

// MARK: - Mini player (other screens)

struct MiniPlayerBar: View {
    @EnvironmentObject private var engine: PlaybackEngine
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p

    var body: some View {
        if engine.isActive, let s = engine.surah {
            HStack(spacing: 10) {
                Button {
                    router.open(surah: s, ayah: engine.ayah >= 1 ? engine.ayah : nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(p.accent)
                            .frame(width: 36, height: 36)
                            .background(p.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Quran.shared.surah(s).title)
                                .font(AppFont.ui(15, .semibold))
                                .foregroundStyle(p.ink)
                            Text(engine.statusLine)
                                .font(AppFont.ui(12))
                                .foregroundStyle(p.ink2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("يفتح السورة")
                Button {
                    engine.togglePlay()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(p.accentInk)
                        .frame(width: 42, height: 42)
                        .background(p.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.isPlaying ? "إيقاف مؤقت" : "تشغيل")
                Button {
                    engine.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(p.ink2)
                        .frame(width: 34, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إيقاف التلاوة")
            }
            .padding(.horizontal, 12)
            .frame(height: 64)
            .background(p.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Repeat settings

struct RepeatSettingsSheet: View {
    let surah: Int
    @EnvironmentObject private var engine: PlaybackEngine
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var from = 1
    @State private var to = 1
    @State private var original = AppSettings()

    private var count: Int { Quran.shared.surah(surah).ayahCount }

    private var speedBinding: Binding<Double> {
        Binding(get: { store.settings.speed }, set: { engine.setSpeed($0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "التلاوة")
                        ForEach(Reciter.allCases) { r in
                            ReciterOption(reciter: r, selected: store.settings.reciter == r) {
                                store.settings.reciter = r
                            }
                        }
                    }

                    let ayahMode = store.settings.reciter.isAyahByAyah
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 12) {
                            SectionTitle(title: "تكرار كل آية")
                            StepButton(systemName: "plus", label: "زيادة") {
                                if store.settings.repeatCount < 10 { store.settings.repeatCount += 1 }
                            }
                            Text(Arabic.times(store.settings.repeatCount))
                                .font(AppFont.ui(18, .bold))
                                .foregroundStyle(p.ink)
                                .frame(minWidth: 84)
                            StepButton(systemName: "minus", label: "إنقاص") {
                                if store.settings.repeatCount > 1 { store.settings.repeatCount -= 1 }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "مدة التوقف لتكرارك", caption: "تبدأ بعد انتهاء الشيخ")
                            PillPicker(selection: $store.settings.pauseMode,
                                       options: PauseMode.allCases.map { (value: $0, title: $0.title) })
                            if store.settings.pauseMode == .fixed {
                                HStack(spacing: 12) {
                                    Text("المدة").font(AppFont.ui(15)).foregroundStyle(p.ink2)
                                    Spacer()
                                    StepButton(systemName: "plus", label: "زيادة") {
                                        if store.settings.fixedPause < 30 { store.settings.fixedPause += 1 }
                                    }
                                    Text(Arabic.seconds(store.settings.fixedPause))
                                        .font(AppFont.ui(16, .semibold))
                                        .foregroundStyle(p.ink)
                                        .frame(minWidth: 84)
                                    StepButton(systemName: "minus", label: "إنقاص") {
                                        if store.settings.fixedPause > 2 { store.settings.fixedPause -= 1 }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "الانتقال إلى الآية التالية")
                            PillPicker(selection: $store.settings.autoAdvance, options: [(value: true, title: "تلقائي"), (value: false, title: "يدوي")])
                        }
                    }
                    .disabled(!ayahMode)
                    .opacity(ayahMode ? 1 : 0.45)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "السرعة", caption: "دون تغيير طبقة الصوت")
                        PillPicker(selection: speedBinding, options: AppSettings.speeds.map { (value: $0, title: "×" + Arabic.decimal($0)) })
                    }

                    if ayahMode {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SectionTitle(title: "المقطع")
                                Button("السورة كاملة") {
                                    from = 1
                                    to = count
                                }
                                .font(AppFont.ui(14, .semibold))
                                .foregroundStyle(p.accent)
                            }
                            HStack(spacing: 12) {
                                ayahField(title: "من الآية", value: $from)
                                ayahField(title: "إلى الآية", value: $to)
                            }
                        }
                    }

                    PrimaryButton(title: "تم") {
                        apply()
                        dismiss()
                    }
                }
                .padding(20)
            }
            .background(p.surface.ignoresSafeArea())
            .navigationTitle("إعدادات التكرار")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        apply()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(p.ink)
                    }
                    .accessibilityLabel("إغلاق")
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: from) { _, v in if to < v { to = v } }
        .onChange(of: to) { _, v in if from > v { from = v } }
    }

    private func ayahField(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.ui(14)).foregroundStyle(p.ink2)
            Menu {
                Picker(title, selection: value) {
                    ForEach(1...count, id: \.self) { n in
                        Text(Arabic.n(n)).tag(n)
                    }
                }
            } label: {
                Text(Arabic.n(value.wrappedValue))
                    .font(AppFont.ui(18, .semibold))
                    .foregroundStyle(p.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(p.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.line, lineWidth: 1))
            }
        }
    }

    private func load() {
        original = store.settings
        if engine.surah == surah, engine.isActive {
            from = engine.rangeStart
            to = engine.rangeEnd
        } else if let r = engine.preparedRange, r.surah == surah {
            from = r.start
            to = r.end
        } else {
            from = 1
            to = count
        }
    }

    private func apply() {
        let a = min(from, to), b = max(from, to)
        engine.setRange(surah: surah, start: a, end: b)
        let s = store.settings
        let changed = s.reciter != original.reciter || s.repeatCount != original.repeatCount ||
            s.pauseMode != original.pauseMode || s.fixedPause != original.fixedPause || s.autoAdvance != original.autoAdvance
        if changed && engine.surah == surah { engine.settingsChanged() }
        original = s
    }
}

struct StepButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(p.ink)
                .frame(width: 52, height: 52)
                .background(p.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ReciterOption: View {
    let reciter: Reciter
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().strokeBorder(selected ? p.accent : p.line, lineWidth: 1.5).frame(width: 28, height: 28)
                    if selected {
                        Circle().fill(p.accent).frame(width: 28, height: 28)
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(p.accentInk)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(reciter.title).font(AppFont.ui(17, .semibold)).foregroundStyle(p.ink)
                    Text(reciter.subtitle).font(AppFont.ui(14)).foregroundStyle(p.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(p.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? p.accent : p.line, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Font size

struct FontSizeSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("حجم خط المصحف").font(AppFont.ui(19, .bold)).foregroundStyle(p.ink)
                Spacer()
                Button("تم") { dismiss() }
                    .font(AppFont.ui(16, .semibold))
                    .foregroundStyle(p.accent)
            }
            Text(Quran.shared.text(1, 2) + " " + MushafLayout.ayahSign(2))
                .font(AppFont.quran(CGFloat(store.settings.quranFontSize)))
                .foregroundStyle(p.ink)
                .frame(maxWidth: .infinity, minHeight: 110)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Text("أ").font(AppFont.ui(15)).foregroundStyle(p.ink2)
                Slider(value: $store.settings.quranFontSize, in: AppSettings.fontRange, step: 2)
                    .tint(p.accent)
                Text("أ").font(AppFont.ui(26)).foregroundStyle(p.ink2)
            }
        }
        .padding(22)
        .presentationDetents([.height(330)])
        .presentationBackground(p.surface)
    }
}
