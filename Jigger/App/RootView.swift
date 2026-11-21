import SwiftUI
import JiggerCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case calculator, recipes, ingredients, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calculator: return "Mix"
        case .recipes: return "Saved Recipes"
        case .ingredients: return "My Ingredients"
        case .settings: return "Settings"
        }
    }

    var tabTitle: String {
        switch self {
        case .calculator: return "Mix"
        case .recipes: return "Recipes"
        case .ingredients: return "Ingredients"
        case .settings: return "Settings"
        }
    }

    /// Mix uses the app's own martini glass (SF Symbols has no martini); the rest are system symbols.
    var icon: Image {
        switch self {
        case .calculator: return Image("Martini")
        case .recipes: return Image(systemName: "book.closed")
        case .ingredients: return Image(systemName: "bookmark")
        case .settings: return Image(systemName: "gearshape")
        }
    }
}

/// iPad (regular width): sidebar navigation. iPhone (compact width): tabs.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: AppSection = .calculator

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(AppSection.allCases, selection: sectionSelection) { s in
                        Label { Text(s.title).font(Theme.body) } icon: { s.icon }
                            .tag(s)
                            .accessibilityIdentifier("sidebar.\(s.rawValue)")
                    }
                    .navigationTitle("Jigger")
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface)
                } detail: {
                    NavigationStack { content(for: section) }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                TabView(selection: $section) {
                    ForEach(AppSection.allCases) { s in
                        NavigationStack { content(for: s) }
                            .tabItem { Label { Text(s.tabTitle) } icon: { s.icon } }
                            .tag(s)
                    }
                }
            }
        }
        .font(Theme.body)
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastOverlay }
        // A light tap when something is saved, removed or undone, like Apple's own apps.
        .sensoryFeedback(.impact(weight: .light), trigger: store.toast?.id)
    }

    private var sectionSelection: Binding<AppSection?> {
        Binding(get: { section }, set: { if let s = $0 { section = s } })
    }

    /// Every screen gets the same keyboard Done bar and drag-to-dismiss.
    private func content(for s: AppSection) -> some View {
        screen(for: s).keyboardDoneBar()
    }

    @ViewBuilder
    private func screen(for s: AppSection) -> some View {
        switch s {
        case .calculator: CalculatorView()
        case .recipes: RecipesView(openCalculator: { section = .calculator })
        case .ingredients: LibraryView()
        case .settings: SettingsView()
        }
    }

    /// Sits just above the Mix cost bar on iPhone, above the tab bar elsewhere, and low on iPad.
    private var toastBottomPadding: CGFloat {
        if sizeClass == .regular { return 24 }
        return section == .calculator ? 118 : 60
    }

    @ViewBuilder
    private var toastOverlay: some View {
        ZStack {
            if let toast = store.toast {
                ToastView(message: toast.message, canUndo: toast.undo != nil,
                          undo: { store.undoToast() }, dismiss: { store.toast = nil })
                    .padding(.bottom, toastBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
                    .task(id: toast.id) {
                        // Long enough to read; longer when there's an Undo to reach for (also kinder to VoiceOver users).
                        try? await Task.sleep(for: .seconds(toast.undo == nil ? 2.5 : 8))
                        if store.toast?.id == toast.id { store.toast = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.22), value: store.toast?.id)
    }
}
