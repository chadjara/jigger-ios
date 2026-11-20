import SwiftUI
import JiggerCore

/// Drag the ingredients into order: the standard iOS reorder list, always in edit mode.
struct ReorderSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let totals = store.draftTotals
            List {
                Section {
                    ForEach(Array(store.draft.lines.enumerated()), id: \.element.id) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(Theme.futura(13, .bold, relativeTo: .footnote))
                                .monospacedDigit()
                                .foregroundStyle(Theme.brass)
                                .frame(width: 24, alignment: .leading)
                            Text(displayName(line)).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(store.lineCostText(totals.line(line.id)))
                                .font(Theme.subhead)
                                .monospacedDigit()
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Theme.surface)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("reorder.\(index)")
                    }
                    .onMove { store.moveLines(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag the handles to set the order the drink is built in.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").font(Theme.emphasis) }
                        .accessibilityIdentifier("reorderDone")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func displayName(_ line: Line) -> String {
        let name = store.resolve(line).name
        return name.isEmpty ? "Unnamed ingredient" : name
    }
}
