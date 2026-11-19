import SwiftUI

// Small shared building blocks. Views compose these instead of restyling controls one by one.

/// Card surface used for ingredient rows, panels and lists.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 12
    var invalid = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(invalid ? Theme.danger.opacity(0.6) : Theme.line, lineWidth: 1))
    }
}

extension View {
    /// Binds keyboard focus when a focus state is supplied.
    @ViewBuilder
    func focusIf(_ focus: FocusState<FieldFocus?>.Binding?, _ value: FieldFocus?) -> some View {
        if let focus, let value { self.focused(focus, equals: value) } else { self }
    }

    func card(padding: CGFloat = 12, invalid: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, invalid: invalid))
    }
}

/// A labelled text input with an optional prefix ($) or suffix (%), outlined in red when invalid.
struct JField: View {
    var label: String?
    @Binding var text: String
    var placeholder = ""
    var prefix: String?
    var suffix: String?
    var keyboard: UIKeyboardType = .decimalPad
    var invalid = false
    var disabled = false
    var identifier: String?
    var focus: FocusState<FieldFocus?>.Binding?
    var focusValue: FieldFocus?
    /// VoiceOver label when the field has no visible label.
    var spokenLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label).font(Theme.label).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 4) {
                if let prefix { Text(prefix).foregroundStyle(Theme.faint) }
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(keyboard != .default)
                    .textInputAutocapitalization(keyboard == .default ? .words : .never)
                    .disabled(disabled)
                    .foregroundStyle(disabled ? Theme.muted : Theme.text)
                    .accessibilityLabel(spokenLabel ?? label ?? placeholder)
                    .accessibilityIdentifier(identifier ?? "")
                    .focusIf(focus, focusValue)
                if let suffix { Text(suffix).foregroundStyle(Theme.faint) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(disabled ? Color.clear : Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(invalid ? Theme.danger : Theme.line, style: StrokeStyle(lineWidth: 1, dash: disabled ? [4, 3] : [])))
        }
    }
}

/// Pill-shaped toggle chip (pours, servings).
struct Chip: View {
    let title: String
    var selected = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Theme.text : Theme.muted)
                .background(selected ? Theme.brassSoft : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.brass : Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "chip.\(title)")
    }
}

/// Brass primary button, or an outlined secondary one.
struct JButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.subheadline : Font.body).weight(.medium))
            .padding(.horizontal, compact ? 12 : 16)
            .frame(minHeight: compact ? 34 : 44)
            .foregroundStyle(prominent ? Theme.onBrass : Theme.text)
            .background(prominent ? (configuration.isPressed ? Theme.brassStrong : Theme.brass) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(prominent ? Color.clear : (configuration.isPressed ? Theme.brass : Theme.lineStrong)))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension ButtonStyle where Self == JButtonStyle {
    static var jPrimary: JButtonStyle { JButtonStyle(prominent: true) }
    static var jSecondary: JButtonStyle { JButtonStyle() }
    static func jSmall(prominent: Bool = false) -> JButtonStyle { JButtonStyle(prominent: prominent, compact: true) }
}

/// Square icon button (remove, save to library).
struct IconButton: View {
    let systemImage: String
    let label: String
    var danger = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(danger ? Theme.danger.opacity(0.85) : Theme.faint)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A label and value on one line, value right-aligned.
struct KeyValueRow: View {
    let label: String
    let value: String
    var tone: DisplayTone = .plain
    var identifier: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(tone.color)
                .accessibilityIdentifier(identifier ?? "")
        }
        .font(.subheadline)
    }
}

enum DisplayTone {
    case plain, good, bad

    var color: Color {
        switch self {
        case .plain: return Theme.text
        case .good: return Theme.good
        case .bad: return Theme.danger
        }
    }
}

/// Centred message for empty lists.
struct EmptyStateView: View {
    let title: String?
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if let title { Text(title).font(Theme.heading(22)).foregroundStyle(Theme.text) }
            Text(message).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.jPrimary).padding(.top, 8)
            }
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

/// Bottom toast with optional Undo, shown above everything.
struct ToastView: View {
    let message: String
    let canUndo: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if canUndo {
                Button("Undo", action: undo)
                    .font(.subheadline.weight(.semibold))
                    .underline()
                    .accessibilityIdentifier("toastUndo")
            }
        }
        .foregroundStyle(Theme.bg)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Theme.text, in: RoundedRectangle(cornerRadius: Theme.radius))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

/// Heading used above calculator sections.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
    }
}
