import SwiftUI
import JiggerCore

@main
struct JiggerApp: App {
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let args = ProcessInfo.processInfo.arguments
        let url: URL
        if args.contains("-uitesting") {
            // UI tests get their own file; "-reset" starts them from a first launch.
            url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-state.json")
            if args.contains("-reset") { try? FileManager.default.removeItem(at: url) }
            UIView.setAnimationsEnabled(false)
        } else {
            url = JSONFileStore.defaultURL()
        }
        _store = State(initialValue: AppStore(storage: JSONFileStore(url: url)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(colorScheme)
                .tint(Theme.brass)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.theme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}
