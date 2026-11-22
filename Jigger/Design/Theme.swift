import SwiftUI
import UIKit

/// Design tokens: every colour, typeface and measurement the app uses lives here.
///
/// The look is a bar's spec sheet rather than a dashboard: charcoal paper, brass ink, Futura set
/// in a few deliberate sizes, hairline rules instead of boxes, and numbers that read from across the bar.
enum Theme {
    // MARK: Colour (light, dark). Values match the Jigger website.
    static let bg = dynamic(0xF3F2EF, 0x1A1918)
    static let surface = dynamic(0xFFFFFF, 0x232120)
    static let raised = dynamic(0xF8F7F4, 0x2B2927)
    static let sunken = dynamic(0xECEAE5, 0x161514)
    static let line = dynamic(0xDCD8D0, 0x3A3734)
    static let lineStrong = dynamic(0xC4BEB3, 0x4D4945)
    static let text = dynamic(0x1E1C1A, 0xEFE9DF)
    static let muted = dynamic(0x6B655C, 0xABA397)
    static let faint = dynamic(0x8F887D, 0x847D72)
    static let brass = dynamic(0x8A6A2B, 0xCDA65E)
    static let brassStrong = dynamic(0x6E5320, 0xE3C383)
    static let onBrass = dynamic(0xFFFFFF, 0x1A1918)
    static let danger = dynamic(0xB0412E, 0xE8907E)
    static let good = dynamic(0x3E7A3B, 0x9CC79A)
    static let warn = dynamic(0x9A6A12, 0xE2B866)

    // MARK: Measurements
    /// Corners stay nearly square: printed menus and bar tickets, not app-store bubbles.
    static let corner: CGFloat = 3
    static let gutter: CGFloat = 20
    static let rowSpacing: CGFloat = 18
    static let hairline: CGFloat = 1
    static let summaryWidth: CGFloat = 380
    /// Letter spacing for the small capitals used as labels.
    static let capsTracking: CGFloat = 1.6

    // MARK: Type (Futura throughout; it ships with iOS, so nothing is bundled)

    /// Futura in one of its installed cuts, scaled with Dynamic Type relative to `style`.
    static func futura(_ size: CGFloat, _ cut: FuturaCut = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        if UIFont(name: cut.postScriptName, size: size) != nil {
            return .custom(cut.postScriptName, size: size, relativeTo: style)
        }
        return .system(style).weight(cut == .bold || cut == .condensedBold ? .bold : .regular)
    }

    static let body = futura(16, relativeTo: .body)
    static let callout = futura(15, relativeTo: .callout)
    static let subhead = futura(14, relativeTo: .subheadline)
    static let footnote = futura(13, relativeTo: .footnote)
    static let caption = futura(12, relativeTo: .caption)
    static let caps = futura(11, relativeTo: .caption2)
    static let emphasis = futura(16, .bold, relativeTo: .body)
    static let note = futura(13, .italic, relativeTo: .footnote)

    /// What people type is set in the system font (San Francisco), like every Apple app, so numbers and
    /// names read and edit naturally with Dynamic Type. Futura stays for labels, titles and figures.
    static let input = Font.body
    static let inputSmall = Font.subheadline

    /// Prices and totals: heavy, condensed, unmistakable.
    static func figure(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        futura(size, .condensedBold, relativeTo: style)
    }

    /// Drink names and page titles.
    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        futura(size, .bold, relativeTo: style)
    }

    /// UIKit equivalents, for navigation bars, tab bars and segmented controls.
    static func uiFutura(_ size: CGFloat, _ cut: FuturaCut = .medium, style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont(name: cut.postScriptName, size: size) ?? .systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum FuturaCut {
    case medium, bold, italic, condensed, condensedBold

    var postScriptName: String {
        switch self {
        case .medium: return "Futura-Medium"
        case .bold: return "Futura-Bold"
        case .italic: return "Futura-MediumItalic"
        case .condensed: return "Futura-CondensedMedium"
        case .condensedBold: return "Futura-CondensedExtraBold"
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// Small tracked capitals for labels ("PRICE PAID"). Use only on fixed captions, never on values.
    func capsLabel(_ color: Color = Theme.muted) -> some View {
        font(Theme.caps).tracking(Theme.capsTracking).textCase(.uppercase).foregroundStyle(color)
    }
}

/// Puts Futura into the UIKit-drawn chrome SwiftUI can't style directly.
enum ChromeAppearance {
    static func apply() {
        let title = Theme.uiFutura(17, .bold, style: .headline)
        let largeTitle = Theme.uiFutura(32, .bold, style: .largeTitle)
        UINavigationBar.appearance().titleTextAttributes = [.font: title]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitle]

        let barButton = Theme.uiFutura(16, .medium, style: .body)
        for state: UIControl.State in [.normal, .highlighted, .disabled] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: barButton], for: state)
        }

        let tab = Theme.uiFutura(11, .medium, style: .caption2)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .selected)

        let segment = Theme.uiFutura(14, .medium, style: .subheadline)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segment], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: Theme.uiFutura(14, .bold, style: .subheadline)], for: .selected)

    }
}
