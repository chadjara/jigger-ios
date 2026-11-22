import SwiftUI

// Shared building blocks. Screens compose these; none of them restyle controls on their own.

// MARK: - Rules and panels

/// A one-point rule. Rules, not boxes, organise every screen.
struct Hairline: View {
    var color: Color = Theme.line
    var dashed = false

    var body: some View {
        if dashed {
            HLine().stroke(color, style: StrokeStyle(lineWidth: Theme.hairline, dash: [3, 3]))
                .frame(height: Theme.hairline)
        } else {
            Rectangle().fill(color).frame(height: Theme.hairline)
        }
    }
}

/// A horizontal line through the middle of its frame.
struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Menu-style dot leader that runs along the text baseline between a label and its value.
struct DotLeader: View {
    var body: some View {
        HLine()
            .stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.01, 4.5]))
            .frame(minWidth: 14, maxWidth: .infinity)
            .frame(height: 2)
            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            .accessibilityHidden(true)
    }
}

/// Section heading: tracked capitals, then a rule to the edge, then an optional count.
struct RuleHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).capsLabel(Theme.text).fixedSize()
                .accessibilityAddTraits(.isHeader)
            Hairline(color: Theme.lineStrong)
            if let trailing { Text(trailing).capsLabel(Theme.brass).fixedSize() }
        }
    }
}

struct PanelModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.line, lineWidth: Theme.hairline))
    }
}

extension View {
    /// A flat, nearly square surface with a hairline edge.
    func panel(padding: CGFloat = 16) -> some View {
        modifier(PanelModifier(padding: padding))
    }

    /// Binds keyboard focus when a focus state is supplied.
    @ViewBuilder
    func focusIf(_ focus: FocusState<FieldFocus?>.Binding?, _ value: FieldFocus?) -> some View {
        if let focus, let value { self.focused(focus, equals: value) } else { self }
    }
}

// MARK: - Inputs

/// A text input set on a rule, like a line on an order pad: small caps label above, entry on the line.
/// The rule thickens and turns red when the entry is invalid, and is dashed when the field is read-only.
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
    /// Smaller type for secondary fields such as a line's waste %.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label { Text(label).capsLabel() }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let prefix { Text(prefix).font(entryFont).foregroundStyle(Theme.faint) }
                TextField(placeholder, text: $text)
                    .font(entryFont)
                    .keyboardType(keyboard)
                    .submitLabel(.done)
                    .autocorrectionDisabled(keyboard != .default)
                    .textInputAutocapitalization(keyboard == .default ? .words : .never)
                    .disabled(disabled)
                    .foregroundStyle(disabled ? Theme.muted : Theme.text)
                    .accessibilityLabel(spokenLabel ?? label ?? placeholder)
                    .accessibilityIdentifier(identifier ?? "")
                    .focusIf(focus, focusValue)
                if let suffix { Text(suffix).font(entryFont).foregroundStyle(Theme.faint) }
            }
            .frame(minHeight: compact ? 30 : 36)
            if disabled {
                Hairline(color: Theme.lineStrong, dashed: true)
            } else {
                Rectangle().fill(invalid ? Theme.danger : Theme.lineStrong).frame(height: invalid ? 2 : Theme.hairline)
            }
        }
    }

    private var entryFont: Font { compact ? Theme.inputSmall : Theme.input }
}

/// The underlined label a menu picker shows, matching `JField`.
struct MenuFieldLabel: View {
    let text: String
    var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(text).font(Theme.body).lineLimit(1).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.brass)
            }
            .frame(minHeight: 36)
            Rectangle().fill(invalid ? Theme.danger : Theme.lineStrong).frame(height: invalid ? 2 : Theme.hairline)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Messages and keyboard

/// A message under an input: an error (red) when the entry can't be used, a warning (amber) when it's
/// valid but unusual. VoiceOver reads it with the field.
struct FieldMessage: View {
    enum Kind { case error, warning }
    let text: String?
    var kind: Kind = .error
    var identifier: String?

    var body: some View {
        if let text {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: kind == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
            }
            .font(Theme.footnote)
            .foregroundStyle(kind == .error ? Theme.danger : Theme.warn)
            .accessibilityLabel((kind == .error ? "Error: " : "Check: ") + text)
            .accessibilityIdentifier(identifier ?? "")
        }
    }
}

/// Closes the on-screen keyboard from anywhere.
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// Every screen and sheet gets the same ways to put the keyboard away: a Done button above it,
    /// dragging the content, and tapping empty space.
    func keyboardDoneBar() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { hideKeyboard() } label: { Text("Done").font(Theme.emphasis) }
                        .accessibilityIdentifier("keyboardDone")
                }
            }
    }

    /// Tapping blank space behind the content closes the keyboard (controls on top still get their taps).
    func tapBackgroundToDismissKeyboard() -> some View {
        background(Color.clear.contentShape(Rectangle()).onTapGesture { hideKeyboard() })
    }
}

// MARK: - Sheet actions

/// One action in a sheet's bottom bar.
struct SheetAction: Identifiable {
    let id: String
    let title: String
    var prominent = true
    var enabled = true
    let action: () -> Void
}

extension View {
    /// On regular-width screens (iPad, iPhone Duo) a sheet also gets its main actions as full-width buttons
    /// along the bottom. There, iOS can present the sheet without drawing its navigation-bar buttons, and a
    /// sheet must never be left without a visible way to finish. iPhone keeps the navigation-bar buttons.
    @ViewBuilder
    func sheetActionBar(_ show: Bool, _ actions: [SheetAction]) -> some View {
        if show {
            safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    ForEach(actions) { a in
                        Button(action: a.action) { Text(a.title).frame(maxWidth: .infinity) }
                            .buttonStyle(JButtonStyle(prominent: a.prominent))
                            .disabled(!a.enabled)
                            .accessibilityIdentifier(a.id)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
                .background(Theme.surface)
                .overlay(alignment: .top) { Hairline(color: Theme.lineStrong) }
            }
        } else {
            self
        }
    }
}

// MARK: - Buttons

/// Square measure button for pours and servings. Selected reads as a filled brass jigger mark.
struct Chip: View {
    let title: String
    var selected = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.futura(13, selected ? .bold : .medium, relativeTo: .footnote))
                .monospacedDigit()
                .padding(.horizontal, 9)
                .frame(minWidth: 40, minHeight: 32)
                .foregroundStyle(selected ? Theme.onBrass : Theme.text)
                .background(selected ? Theme.brass : Color.clear, in: RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(selected ? Theme.brass : Theme.lineStrong, lineWidth: Theme.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "chip.\(title)")
    }
}

/// Buttons are set in tracked Futura capitals: solid brass for the main action, a brass outline otherwise.
struct JButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.futura(compact ? 12 : 13, .bold, relativeTo: .subheadline))
            .tracking(1.3)
            .textCase(.uppercase)
            .padding(.horizontal, compact ? 12 : 18)
            .frame(minHeight: compact ? 34 : 46)
            .foregroundStyle(prominent ? Theme.onBrass : Theme.brass)
            .background(fill(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner)
                .strokeBorder(prominent ? Color.clear : Theme.brass, lineWidth: Theme.hairline))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }

    private func fill(pressed: Bool) -> Color {
        if prominent { return pressed ? Theme.brassStrong : Theme.brass }
        return pressed ? Theme.brass.opacity(0.12) : Color.clear
    }
}

extension ButtonStyle where Self == JButtonStyle {
    static var jPrimary: JButtonStyle { JButtonStyle(prominent: true) }
    static var jSecondary: JButtonStyle { JButtonStyle() }
    static func jSmall(prominent: Bool = false) -> JButtonStyle { JButtonStyle(prominent: prominent, compact: true) }
}

/// Icon-only button with a full 44-point target.
struct IconButton: View {
    let systemImage: String
    let label: String
    var danger = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(danger ? Theme.danger : Theme.faint)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}

// MARK: - Figures

/// "Label ........ value", the way a menu prints a price.
struct KeyValueRow: View {
    let label: String
    let value: String
    var tone: DisplayTone = .plain
    var identifier: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(Theme.subhead).foregroundStyle(Theme.muted).lineLimit(2)
            DotLeader()
            Text(value)
                .font(Theme.futura(15, .bold, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(tone.color)
                .fixedSize()
                .accessibilityIdentifier(identifier ?? "")
        }
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

/// Empty lists get a short, left-aligned note, not a centred billboard.
struct EmptyStateView: View {
    let title: String?
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(Theme.heading(20, relativeTo: .title3)).foregroundStyle(Theme.text) }
            Text(message).font(Theme.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.jPrimary).padding(.top, 6)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small notice that slides up above the bottom bar: a charcoal slip with a hairline brass edge,
/// sized to its words. Tap or swipe it down to dismiss; Undo when the action can be reversed.
struct ToastView: View {
    let message: String
    let canUndo: Bool
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(Theme.footnote)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if canUndo {
                Rectangle().fill(Theme.lineStrong).frame(width: Theme.hairline, height: 16)
                    .accessibilityHidden(true)
                Button(action: undo) {
                    Text("Undo")
                        .font(Theme.futura(12, .bold, relativeTo: .footnote))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.brass)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo")
                .accessibilityIdentifier("toastUndo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.brass.opacity(0.35), lineWidth: Theme.hairline))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .frame(maxWidth: 360)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .gesture(DragGesture(minimumDistance: 8).onEnded { if $0.translation.height > 10 { dismiss() } })
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}
