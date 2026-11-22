import SwiftUI

/// Rounded segmented control from the design (the first option sits on the right).
struct PillPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, title: String)]
    var disabled = false
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(AppFont.ui(15, selected ? .semibold : .medium))
                        .foregroundStyle(selected ? p.ink : p.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(p.id == "dark" ? p.line : p.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(p.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(disabled ? 0.45 : 1)
        .allowsHitTesting(!disabled)
    }
}

struct Card<Content: View>: View {
    var highlighted = false
    @ViewBuilder let content: Content
    @Environment(\.palette) private var p

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(highlighted ? p.accent : p.line, lineWidth: highlighted ? 1.5 : 1)
            }
    }
}

/// Round outlined icon button (back, settings, close).
struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    let label: String
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(p.ink)
                .frame(width: size, height: size)
                .background(p.surface, in: Circle())
                .overlay(Circle().strokeBorder(p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                }
                Text(title).font(AppFont.ui(18, .semibold))
            }
            .foregroundStyle(p.accentInk)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(p.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .medium)).foregroundStyle(p.accent)
                }
                Text(title).font(AppFont.ui(16, .semibold)).foregroundStyle(p.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(p.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Small rounded label with an icon (streak, minutes…).
struct InfoChip: View {
    let systemImage: String
    let text: String
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .medium)).foregroundStyle(p.accent)
            Text(text).font(AppFont.ui(15, .medium)).foregroundStyle(p.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .background(p.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(p.line, lineWidth: 1))
    }
}

struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 6
    @Environment(\.palette) private var p

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(p.surface2)
                Capsule().fill(p.accent).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Arabic.n(wholePercent(fraction))) بالمئة")
    }
}

/// Circular progress for a surah or juz row.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 34
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            Circle().stroke(p.surface2, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(p.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(p.accent)
            } else {
                Text(Arabic.n(wholePercent(fraction)))
                    .font(AppFont.ui(10, .semibold))
                    .foregroundStyle(p.ink2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("أُنجز \(Arabic.n(wholePercent(fraction))) بالمئة")
    }
}

/// Whole percent for display: never 100 before the end, never 0 once something is done.
func wholePercent(_ fraction: Double) -> Int {
    guard fraction > 0 else { return 0 } // also catches NaN
    if fraction >= 1 { return 100 }
    return min(99, max(1, Int((fraction * 100).rounded())))
}

/// Section title used in sheets and settings.
struct SectionTitle: View {
    let title: String
    var caption: String?
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(AppFont.ui(17, .bold)).foregroundStyle(p.ink)
            Spacer(minLength: 8)
            if let caption {
                Text(caption).font(AppFont.ui(13)).foregroundStyle(p.ink2)
            }
        }
    }
}

/// Number of a surah inside a small ornament.
struct NumberBadge: View {
    let number: Int
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(p.gold.opacity(0.7), lineWidth: 1.2)
                .rotationEffect(.degrees(45))
                .frame(width: 30, height: 30)
            Text(Arabic.n(number))
                .font(AppFont.ui(14, .semibold))
                .foregroundStyle(p.ink)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// Quran text in a quote, rendered from the bundled Tanzil text (never typed by hand).
struct AyahQuote: View {
    let surah: Int
    let ayah: Int
    var size: CGFloat = 24
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("﴿" + Quran.shared.text(surah, ayah) + "﴾")
                .font(AppFont.quran(size))
                .foregroundStyle(p.ink)
                .lineSpacing(size * 0.35)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "[\(Quran.shared.surah(surah).name): \(Arabic.n(ayah))]")
                .font(AppFont.ui(13))
                .foregroundStyle(p.ink2)
        }
    }
}

extension View {
    /// Sheets get the app's colours, direction and shared objects explicitly.
    func appEnvironment(_ p: Palette, store: AppStore, engine: PlaybackEngine) -> some View {
        self
            .environment(\.palette, p)
            .environment(\.layoutDirection, .rightToLeft)
            .environmentObject(store)
            .environmentObject(engine)
            .font(AppFont.ui(17))
            .preferredColorScheme(p.id == "dark" ? .dark : .light)
    }

    /// Paper background for a whole screen.
    func screenBackground(_ p: Palette) -> some View {
        background(p.paper.ignoresSafeArea())
    }
}
