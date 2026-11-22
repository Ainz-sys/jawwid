import SwiftUI

// MARK: - Progress

struct ProgressScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var p

    var body: some View {
        let total = Quran.shared.ayahTotal
        let done = store.completed.count
        let juzDone = (1...30).map { ($0, store.completedCount(juz: $0)) }.filter { $0.1 > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(value: done, label: "الآيات المنجزة", systemImage: "checkmark.seal")
                    StatTile(value: store.todayCount, label: "آيات اليوم", systemImage: "sun.max")
                    StatTile(value: store.streak, label: "الأيام المتتالية", systemImage: "calendar")
                    StatTile(value: store.practiceDays, label: "أيام التدريب", systemImage: "clock")
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("القرآن كاملاً").font(AppFont.ui(17, .bold)).foregroundStyle(p.ink)
                            Spacer()
                            Text("\(Arabic.n(done)) من \(Arabic.n(total))").font(AppFont.ui(14)).foregroundStyle(p.ink2)
                        }
                        ProgressLine(fraction: Double(done) / Double(total))
                        Text("تُحتسب الآية منجزة حين تُكمل تكرارها خلف الشيخ بالعدد الذي اخترته.")
                            .font(AppFont.ui(13))
                            .foregroundStyle(p.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !juzDone.isEmpty {
                    SectionTitle(title: "الأجزاء")
                    VStack(spacing: 10) {
                        ForEach(juzDone, id: \.0) { item in
                            let count = Quran.shared.juzRange(item.0).count
                            ProgressRow(title: "الجزء \(Arabic.n(item.0))", done: item.1, total: count)
                        }
                    }
                }

                SectionTitle(title: "السور")
                let started = store.startedSurahs
                if started.isEmpty {
                    Text("لم تُنجز آيات بعد. ابدأ من «الرئيسية» أو اختر سورة من المصحف.")
                        .font(AppFont.ui(15))
                        .foregroundStyle(p.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ForEach(started) { s in
                            ProgressRow(title: s.title, done: store.completedCount(surah: s.number), total: s.ayahCount)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .screenBackground(p)
        .navigationTitle("تقدّمي")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(p.accent)
            Text(Arabic.n(value))
                .font(AppFont.ui(28, .bold))
                .foregroundStyle(p.ink)
            Text(label)
                .font(AppFont.ui(13))
                .foregroundStyle(p.ink2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressRow: View {
    let title: String
    let done: Int
    let total: Int
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(AppFont.ui(16, .semibold)).foregroundStyle(p.ink)
                Spacer()
                Text("\(Arabic.n(done)) من \(Arabic.n(total))").font(AppFont.ui(13)).foregroundStyle(p.ink2)
            }
            ProgressLine(fraction: Double(done) / Double(max(total, 1)))
        }
        .padding(14)
        .background(p.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.line, lineWidth: 1))
    }
}

// MARK: - Coming next

struct ComingSoonView: View {
    enum Kind { case tajweed, voice }
    let kind: Kind
    @Environment(\.palette) private var p

    private var title: String { kind == .tajweed ? "التجويد" : "صوتي" }
    private var icon: String { kind == .tajweed ? "graduationcap" : "mic" }
    private var summary: String {
        kind == .tajweed
            ? "دروس أحكام التجويد خطوة خطوة، بأمثلة من تلاوة الشيخ المنشاوي."
            : "سجّل تلاوتك وقارنها بتلاوة الشيخ، وحسّن صوتك وأداءك بتمارين قصيرة."
    }
    private var items: [String] {
        kind == .tajweed
            ? ["وحدة تأسيسية اختيارية، ثم ١٣ وحدة متدرّجة",
               "المصحف ملوّناً بأحكام التجويد، مع شرح الحكم عند لمس الكلمة",
               "أمثلة صوتية من التلاوة واختبارات قصيرة"]
            : ["التسجيل والاستماع بجانب تلاوة الشيخ",
               "تمارين النَّفَس وإطالة المد بعدّاد للحركات",
               "تمارين مخارج الحروف"]
    }
    private var phase: String { kind == .tajweed ? "الثانية" : "الثالثة" }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(p.accent)
                    .frame(width: 96, height: 96)
                    .background(p.accentSoft, in: Circle())
                    .padding(.top, 20)
                Text(summary)
                    .font(AppFont.ui(17))
                    .foregroundStyle(p.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle").foregroundStyle(p.accent)
                                Text(item).font(AppFont.ui(15)).foregroundStyle(p.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Text("يصل هذا القسم في المرحلة \(phase) من البناء.")
                    .font(AppFont.ui(14))
                    .foregroundStyle(p.ink2)
            }
            .padding(24)
        }
        .screenBackground(p)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var downloads: Downloads
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var p
    @State private var sizes: [Reciter: Int64] = [:]
    @State private var confirmDelete: Reciter?

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Arabic.digits("\(v) (\(b))")
    }

    var body: some View {
        Form {
            Section {
                ForEach(Reciter.allCases) { r in
                    Button {
                        store.settings.reciter = r
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(AppFont.ui(16, .semibold)).foregroundStyle(p.ink)
                                Text(r.subtitle).font(AppFont.ui(13)).foregroundStyle(p.ink2)
                            }
                            Spacer()
                            if store.settings.reciter == r {
                                Image(systemName: "checkmark").foregroundStyle(p.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Toggle(isOn: $store.settings.playBasmala) {
                    Text("البسملة قبل أول السورة").font(AppFont.ui(16))
                }
                .tint(p.accent)
            } header: {
                Text("التلاوة")
            }
            .listRowBackground(p.surface)

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Quran.shared.text(1, 2))
                        .font(AppFont.quran(CGFloat(store.settings.quranFontSize)))
                        .foregroundStyle(p.ink)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Text("أ").font(AppFont.ui(14)).foregroundStyle(p.ink2)
                        Slider(value: $store.settings.quranFontSize, in: AppSettings.fontRange, step: 2)
                            .tint(p.accent)
                        Text("أ").font(AppFont.ui(24)).foregroundStyle(p.ink2)
                    }
                }
                .padding(.vertical, 6)
                Picker(selection: $store.settings.theme) {
                    ForEach(ThemeMode.allCases) { t in
                        Text(t.title).tag(t)
                    }
                } label: {
                    Text("المظهر").font(AppFont.ui(16))
                }
                .pickerStyle(.segmented)
            } header: {
                Text("عرض المصحف")
            }
            .listRowBackground(p.surface)

            Section {
                ForEach(Reciter.allCases) { r in
                    let count = downloads.done.filter { $0.reciter == r }.count
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(AppFont.ui(15, .semibold)).foregroundStyle(p.ink)
                            Text(count == 0 ? "لا شيء محفوظ" : "\(Arabic.n(count)) سورة · \(sizeText(sizes[r] ?? 0))")
                                .font(AppFont.ui(13))
                                .foregroundStyle(p.ink2)
                        }
                        Spacer()
                        if (sizes[r] ?? 0) > 0 {
                            Button("حذف") { confirmDelete = r }
                                .font(AppFont.ui(15, .semibold))
                                .foregroundStyle(p.warn)
                                .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("التنزيلات")
            } footer: {
                Text("نزّل أي سورة من فهرس المصحف بزر السهم، فتعمل دون إنترنت. البسملة تُحفظ مرة واحدة مع سورة الفاتحة.")
            }
            .listRowBackground(p.surface)

            Section {
                Button {
                    router.homePath.append(.credits)
                } label: {
                    HStack {
                        Text("المصادر والتراخيص").font(AppFont.ui(16)).foregroundStyle(p.ink)
                        Spacer()
                        Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack {
                    Text("الإصدار").font(AppFont.ui(16)).foregroundStyle(p.ink)
                    Spacer()
                    Text(version).font(AppFont.ui(15)).foregroundStyle(p.ink2)
                }
            } header: {
                Text("حول التطبيق")
            }
            .listRowBackground(p.surface)
        }
        .scrollContentBackground(.hidden)
        .screenBackground(p)
        .navigationTitle("الإعدادات")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshSizes() }
        .onChange(of: downloads.done) { _, _ in refreshSizes() }
        .confirmationDialog("حذف التنزيلات", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { r in
            Button("حذف تنزيلات \(r.title)", role: .destructive) {
                downloads.deleteAll(r)
                refreshSizes()
            }
            Button("إلغاء", role: .cancel) {}
        } message: { _ in
            Text("تُحذف ملفات هذه التلاوة من جهازك، ويمكنك تنزيلها مرة أخرى متى شئت.")
        }
    }

    private func refreshSizes() {
        var s: [Reciter: Int64] = [:]
        for r in Reciter.allCases { s[r] = AudioFiles.size(of: r) }
        sizes = s
    }

    private func sizeText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1 { return "أقل من ١ ميغابايت" }
        return Arabic.n(Int(mb.rounded())) + " ميغابايت"
    }
}

// MARK: - Credits

struct CreditsView: View {
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                credit("نص القرآن الكريم",
                       "نص تنزيل العثماني، الإصدار ١٫١، منقول حرفياً دون أي تغيير. والبسملة في أول كل سورة من ملف تنزيل نفسه.",
                       link: "https://tanzil.net", linkTitle: "tanzil.net")
                Text(Quran.shared.notice.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(p.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(p.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .environment(\.layoutDirection, .leftToRight)
                credit("تلاوة المنشاوي آيةً آية (المرتّل والمجوّد)",
                       "من موقع EveryAyah. حقوق التسجيلات محفوظة لأصحابها.",
                       link: "https://everyayah.com", linkTitle: "everyayah.com")
                credit("المصحف المعلّم (ترديد الأطفال)",
                       "من موقع mp3quran.net. حقوق التسجيلات محفوظة لأصحابها.",
                       link: "https://mp3quran.net", linkTitle: "mp3quran.net")
                credit("توقيت كلمات التلاوة",
                       "مشروع quran-align، برخصة المشاع الإبداعي CC BY 4.0.",
                       link: "https://github.com/cpfair/quran-align", linkTitle: "github.com/cpfair/quran-align")
                credit("أسماء السور وحدود الأجزاء",
                       "مكتبة quran-meta برخصة MIT، ومطابقة لبيانات تنزيل.",
                       link: "https://github.com/quran-center/quran-meta", linkTitle: "github.com/quran-center/quran-meta")
                credit("الخطوط",
                       "خط Amiri Quran لنص المصحف، وخط IBM Plex Sans Arabic للواجهة، كلاهما برخصة SIL Open Font License 1.1.",
                       link: "https://openfontlicense.org", linkTitle: "openfontlicense.org")
            }
            .padding(20)
        }
        .screenBackground(p)
        .navigationTitle("المصادر والتراخيص")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(_ title: String, _ body: String, link: String, linkTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.ui(16, .bold)).foregroundStyle(p.ink)
            Text(body).font(AppFont.ui(14)).foregroundStyle(p.ink2).fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: link) {
                Link(linkTitle, destination: url)
                    .font(AppFont.ui(14, .semibold))
                    .foregroundStyle(p.accent)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(p.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.line, lineWidth: 1))
    }
}
