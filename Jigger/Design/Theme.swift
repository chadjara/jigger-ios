import SwiftUI
import UIKit

/// Design tokens. One place for every colour, font and spacing value, taken from the web app's CSS
/// so both versions look alike: dark charcoal with warm brass accents (plus a light palette).
enum Theme {
    // MARK: Colours (light, dark)
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
    static var brassSoft: Color { brass.opacity(0.13) }
    static var dangerSoft: Color { danger.opacity(0.12) }

    // MARK: Shape and spacing
    static let radiusSmall: CGFloat = 6
    static let radius: CGFloat = 10
    static let gutter: CGFloat = 16
    static let summaryWidth: CGFloat = 380

    // MARK: Type
    /// Large serif figures (prices), like the web app's Bodoni. Uses the system's Bodoni 72; no bundled fonts.
    static func figure(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        serif(size, bold: true, relativeTo: style)
    }

    /// Serif headings (drink names, page titles).
    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        serif(size, bold: true, relativeTo: style)
    }

    private static func serif(_ size: CGFloat, bold: Bool, relativeTo style: Font.TextStyle) -> Font {
        let name = bold ? "BodoniSvtyTwoITCTT-Bold" : "BodoniSvtyTwoITCTT-Book"
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size, relativeTo: style) }
        return .system(style, design: .serif).weight(bold ? .semibold : .regular)
    }

    static let label = Font.footnote
    static let body = Font.body
    static let small = Font.caption

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
