import SwiftUI
import UniformTypeIdentifiers
import JiggerCore
import JiggerEngine

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var targetText = ""
    @State private var targetInvalid = false
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Picker("Currency", selection: Binding(get: { store.settings.currency }, set: { store.setCurrency($0) })) {
                    ForEach(Catalog.currencies) { c in Text("\(c.name) (\(c.code))").tag(c.code) }
                }
                .accessibilityIdentifier("setCurrency")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Target beverage cost")
                        Spacer()
                        JField(label: nil, text: targetBinding, placeholder: "20", suffix: "%", invalid: targetInvalid,
                               identifier: "setTarget", spokenLabel: "Default target beverage cost")
                            .frame(width: 110)
                    }
                    if targetInvalid {
                        FieldMessage(text: checkTargetPct(targetText).error ?? "Enter a target between 1 and 99%",
                                     identifier: "setTargetError")
                    } else {
                        FieldMessage(text: checkTargetPct(targetText).note, kind: .warning, identifier: "setTargetNote")
                    }
                }
                Picker("Pour unit", selection: Binding(get: { store.settings.displayUnit }, set: { store.setDisplayUnit($0) })) {
                    Text("Fluid ounces (oz)").tag("floz")
                    Text("Milliliters (mL)").tag("ml")
                }
                Picker("Appearance", selection: Binding(get: { store.settings.theme }, set: { store.setTheme($0) })) {
                    Text("Dark").tag(AppTheme.dark)
                    Text("Light").tag(AppTheme.light)
                    Text("Match my device").tag(AppTheme.system)
                }
                .accessibilityIdentifier("setTheme")
            } header: {
                Text("Defaults").capsLabel()
            } footer: {
                Text("Used for new recipes and how prices are shown.").font(Theme.footnote)
            }

            Section {
                Text("Costs are always calculated from exactly what you typed, using exact unit factors. When you switch between oz and mL, pours are shown using the bar convention of 1 oz ≈ 30 mL (1.5 oz shows as 45 mL), and switching never changes what you entered. Fluid ounces measure volume; “oz wt” measures weight.")
                    .font(Theme.subhead)
                    .foregroundStyle(Theme.muted)
            } header: {
                Text("How conversions work").capsLabel()
            }

            Section {
                Button("Export backup (.json)") { export() }
                    .accessibilityIdentifier("exportData")
                Button("Import backup") { showImporter = true }
                    .accessibilityIdentifier("importData")
            } header: {
                Text("Back up your data").capsLabel()
            } footer: {
                Text("Recipes and ingredients are stored on this device only. Export a backup to keep them safe or move them to another device or the Jigger website. Importing adds to what’s already here.").font(Theme.footnote)
            }

            Section {
                Button("Delete all data", role: .destructive) { confirmReset = true }
                    .accessibilityIdentifier("resetData")
            } header: {
                Text("Start over").capsLabel()
            } footer: {
                Text("Deletes every saved recipe and ingredient from this device. Settings are kept.").font(Theme.footnote)
            }

            Section {
                LabeledContent("Version", value: appVersion)
                Text("Jigger works offline. It has no accounts, no ads and no tracking, and your data never leaves this device unless you export or share it.")
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.muted)
            } header: {
                Text("About").capsLabel()
            }
        }
        .font(Theme.body)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Settings")
        .onAppear { targetText = store.settings.targetPct; targetInvalid = false }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: store.backupFileName) { result in
            if case .failure = result { store.showToast("Couldn’t save the backup. Please try again.") }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .confirmationDialog("Delete every saved recipe and ingredient?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) { store.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone. Export a backup first if you might want them later.")
        }
    }

    private var targetBinding: Binding<String> {
        Binding(get: { targetText }, set: { value in
            targetText = store.normalizeTyped(value)
            targetInvalid = !store.setDefaultTarget(targetText)
        })
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try store.exportBackup())
            showExporter = true
        } catch {
            store.showToast("Couldn’t create the backup. Please try again.")
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            store.showToast("Couldn’t read that file. Choose a .json file exported from Jigger.")
            return
        }
        store.importBackup(data)
    }
}

/// A backup file for the system "Save to Files" exporter.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
