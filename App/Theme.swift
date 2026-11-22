import SwiftUI
import UIKit

/// Colours from the approved design (light paper, and a true night mode).
struct Palette: Equatable {
    let id: String
    let paper: Color
    let surface: Color
    let surface2: Color
    let line: Color
    let ink: Color
    let ink2: Color
    let accent: Color
    let accentInk: Color
    let accentSoft: Color
    let gold: Color
    let goldSoft: Color
    let ayahHighlight: Color
    let wordHighlight: Color
    let warn: Color
    let warnSoft: Color
    let ok: Color
    let okSoft: Color

    static let light = Palette(
        id: "light",
        paper: Color(hex: 0xF6F1E6), surface: Color(hex: 0xFFFCF6), surface2: Color(hex: 0xEFE8DA),
        line: Color(hex: 0xE3D9C6), ink: Color(hex: 0x1D2A24), ink2: Color(hex: 0x55615A),
        accent: Color(hex: 0x1F5E52), accentInk: Color(hex: 0xFFFFFF), accentSoft: Color(hex: 0xE2ECE6),
        gold: Color(hex: 0x8A651C), goldSoft: Color(hex: 0xF3E8CC),
        ayahHighlight: Color(hex: 0xE3EEE8), wordHighlight: Color(hex: 0xF2DC9E),
        warn: Color(hex: 0xA4441C), warnSoft: Color(hex: 0xF7E5D8), ok: Color(hex: 0x2B7A3D), okSoft: Color(hex: 0xE2EFE3))

    static let dark = Palette(
        id: "dark",
        paper: Color(hex: 0x111714), surface: Color(hex: 0x19211D), surface2: Color(hex: 0x222C27),
        line: Color(hex: 0x2E3A34), ink: Color(hex: 0xECE6D8), ink2: Color(hex: 0xAEB7B1),
        accent: Color(hex: 0x79C4B1), accentInk: Color(hex: 0x0F1B17), accentSoft: Color(hex: 0x1E302A),
        gold: Color(hex: 0xD4B46C), goldSoft: Color(hex: 0x3A3220),
        ayahHighlight: Color(hex: 0x1E2C26), wordHighlight: Color(hex: 0x5C4B1F),
        warn: Color(hex: 0xF0A27A), warnSoft: Color(hex: 0x3A261C), ok: Color(hex: 0x86C996), okSoft: Color(hex: 0x1F3326))

    static func == (a: Palette, b: Palette) -> Bool { a.id == b.id }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum AppFont {
    static let quranName = "AmiriQuran-Regular"

    enum Weight {
        case regular, medium, semibold, bold
        var name: String {
            switch self {
            case .regular: return "IBMPlexSansArabic-Regular"
            case .medium: return "IBMPlexSansArabic-Medium"
            case .semibold: return "IBMPlexSansArabic-SemiBold"
            case .bold: return "IBMPlexSansArabic-Bold"
            }
        }
    }

    /// Interface text; scales with the system text size.
    static func ui(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(weight.name, size: size, relativeTo: style)
    }

    /// Quran text at an exact size (the reader sets its own size).
    static func quran(_ size: CGFloat) -> Font {
        Font.custom(quranName, fixedSize: size)
    }

    static func uiQuranFont(_ size: CGFloat) -> UIFont {
        UIFont(name: quranName, size: size) ?? UIFont.systemFont(ofSize: size)
    }

    /// Sets the custom fonts on the UIKit bars too.
    @MainActor
    static func styleSystemBars() {
        let nav = UINavigationBar.appearance()
        if let f = UIFont(name: Weight.semibold.name, size: 17) {
            nav.titleTextAttributes = [.font: f]
        }
        if let f = UIFont(name: Weight.bold.name, size: 30) {
            nav.largeTitleTextAttributes = [.font: f]
        }
        if let f = UIFont(name: Weight.medium.name, size: 11) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: f], for: .normal)
        }
        if let f = UIFont(name: Weight.medium.name, size: 13) {
            UISegmentedControl.appearance().setTitleTextAttributes([.font: f], for: .normal)
        }
    }
}

// MARK: - Arabic numerals

enum Arabic {
    private static let digitMap: [Character: Character] = [
        "0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
        "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩", ".": "٫", ",": "٬",
    ]

    static func digits(_ s: String) -> String {
        String(s.map { digitMap[$0] ?? $0 })
    }

    static func n(_ v: Int) -> String { digits(String(v)) }

    /// 0.75 → "٠٫٧٥", 1.0 → "١"
    static func decimal(_ v: Double) -> String {
        if v == v.rounded() { return n(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return digits(s)
    }

    /// 75 → "١:١٥"
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return digits("0:00") }
        let t = Int(seconds.rounded(.down))
        return digits(String(format: "%d:%02d", t / 60, t % 60))
    }

    /// Whether a count written in digits takes the plural noun: 3–10 do, and above 100 the last two digits
    /// decide (١٠٩ آيات، ٢٠٦ آيات، ١١١ آية، ٢٠٠ آية). 1 and 2 have words of their own.
    private static func takesPlural(_ count: Int) -> Bool {
        (3...10).contains(count > 100 ? count % 100 : count)
    }

    /// Correct Arabic plural for ayat: آية واحدة، آيتان، ٣ آيات، ١١ آية، ١٠٩ آيات
    static func ayat(_ count: Int) -> String {
        switch count {
        case 1: return "آية واحدة"
        case 2: return "آيتان"
        default: return "\(n(count)) " + (takesPlural(count) ? "آيات" : "آية")
        }
    }

    static func suwar(_ count: Int) -> String {
        switch count {
        case 1: return "سورة واحدة"
        case 2: return "سورتان"
        default: return "\(n(count)) " + (takesPlural(count) ? "سور" : "سورة")
        }
    }

    static func times(_ count: Int) -> String {
        switch count {
        case 1: return "مرة واحدة"
        case 2: return "مرتان"
        default: return "\(n(count)) " + (takesPlural(count) ? "مرات" : "مرة")
        }
    }

    static func seconds(_ count: Int) -> String {
        switch count {
        case 1: return "ثانية واحدة"
        case 2: return "ثانيتان"
        default: return "\(n(count)) " + (takesPlural(count) ? "ثوانٍ" : "ثانية")
        }
    }
}
