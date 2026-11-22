import SwiftUI
import UIKit

@main
struct JawwidApp: App {
    @StateObject private var store = AppStore.shared
    @StateObject private var engine = PlaybackEngine.shared
    @StateObject private var downloads = Downloads.shared
    @StateObject private var router = Router.shared

    init() {
        // The app is Arabic only: lay out UIKit parts (bars, sheets) right to left too.
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
        AppFont.styleSystemBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(downloads)
                .environmentObject(router)
                .onAppear { Demo.prepare() }
        }
    }
}

enum AppTab: Hashable {
    case home, mushaf, tajweed, voice, progress
}

struct MushafRoute: Hashable {
    let surah: Int
    let ayah: Int?
}

@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published var tab: AppTab = .home
    @Published var mushafPath: [MushafRoute] = []
    @Published var homePath: [HomeRoute] = []

    enum HomeRoute: Hashable {
        case settings
        case credits
    }

    /// Opens a surah in the mushaf tab (from the home screen, the mini player or a juz).
    func open(surah: Int, ayah: Int?) {
        tab = .mushaf
        mushafPath = [MushafRoute(surah: surah, ayah: ayah)]
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.colorScheme) private var systemScheme

    private var palette: Palette {
        let scheme = store.settings.theme.colorScheme ?? systemScheme
        return scheme == .dark ? .dark : .light
    }

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .navigationDestination(for: Router.HomeRoute.self) { route in
                        switch route {
                        case .settings: SettingsView()
                        case .credits: CreditsView()
                        }
                    }
            }
            .tabItem { Label("الرئيسية", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack(path: $router.mushafPath) {
                MushafIndexView()
                    .navigationDestination(for: MushafRoute.self) { route in
                        SurahReaderView(route: route)
                    }
            }
            .tabItem { Label("المصحف", systemImage: "book") }
            .tag(AppTab.mushaf)

            NavigationStack {
                ComingSoonView(kind: .tajweed)
            }
            .tabItem { Label("التجويد", systemImage: "graduationcap") }
            .tag(AppTab.tajweed)

            NavigationStack {
                ComingSoonView(kind: .voice)
            }
            .tabItem { Label("صوتي", systemImage: "mic") }
            .tag(AppTab.voice)

            NavigationStack {
                ProgressScreen()
            }
            .tabItem { Label("تقدّمي", systemImage: "chart.bar") }
            .tag(AppTab.progress)
        }
        .tint(palette.accent)
        .environment(\.palette, palette)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .font(AppFont.ui(17))
        .preferredColorScheme(store.settings.theme.colorScheme)
    }
}
