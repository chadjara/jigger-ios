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

/// Sidebar navigation where there's room for it (iPad); tabs everywhere else (iPhone, iPhone Duo, and
/// narrow iPad split screen). The iPhone Duo reports a regular size class on screens too narrow for a
/// sidebar, so the choice also needs real width.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: AppSection = .calculator
    /// The window's width, measured once per change. Nil until the first layout.
    @State private var width: CGFloat?

    /// Narrowest width that shows the sidebar beside the content.
    private static let sidebarMinWidth: CGFloat = 700

    /// Regular size class with room for a sidebar. Before the first measurement, guess from the device:
    /// iPads start with the sidebar, iPhones (iPhone Duo included) with tabs, so neither builds one layout
    /// and then rebuilds the other at launch.
    private var wide: Bool {
        sizeClass == .regular
            && (width.map { $0 >= Self.sidebarMinWidth } ?? (UIDevice.current.userInterfaceIdiom == .pad))
    }

    var body: some View {
        layout(wide: wide)
            .overlay(alignment: .bottom) { toastOverlay(wide: wide) }
            // Measured in the background, so only a change in the answer (not every resize, rotation or
            // keyboard) re-renders the root.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { measure(geo.size.width) }
                        .onChange(of: geo.size.width) { _, new in measure(new) }
                }
            }
        .font(Theme.body)
        .background(Theme.bg.ignoresSafeArea())
        // A light tap when something is saved, removed or undone, like Apple's own apps.
        .sensoryFeedback(.impact(weight: .light), trigger: store.toast?.id)
    }

    /// Stores the width only when it changes which side of the sidebar threshold we're on.
    private func measure(_ new: CGFloat) {
        guard new > 0 else { return }
        if width == nil || (new >= Self.sidebarMinWidth) != (width! >= Self.sidebarMinWidth) { width = new }
    }

    @ViewBuilder
    private func layout(wide: Bool) -> some View {
        Group {
            if wide {
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
    private func toastBottomPadding(wide: Bool) -> CGFloat {
        if wide { return 24 }
        return section == .calculator ? 118 : 60
    }

    @ViewBuilder
    private func toastOverlay(wide: Bool) -> some View {
        ZStack {
            if let toast = store.toast {
                ToastView(message: toast.message, canUndo: toast.undo != nil,
                          undo: { store.undoToast() }, dismiss: { store.toast = nil })
                    .padding(.bottom, toastBottomPadding(wide: wide))
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
