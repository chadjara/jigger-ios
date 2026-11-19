import Foundation

/// Loads and saves the whole app state as one document. Everything goes through this interface,
/// so storage can change later without touching the store or the UI.
public protocol StateStoring: AnyObject {
    func load() -> AppState?
    func save(_ state: AppState) throws
}

/// Saves the state as JSON in a file, written atomically so a crash mid-write never corrupts it.
public final class JSONFileStore: StateStoring {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/Jigger/state.json` (included in the device's iCloud/computer backups).
    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Jigger", isDirectory: true).appendingPathComponent("state.json")
    }

    public func load() -> AppState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            // Never silently overwrite data we couldn't read: keep the unreadable file beside the new one.
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: [.atomic])
    }
}

/// Keeps state in memory only. Used by tests and previews.
public final class MemoryStore: StateStoring {
    public var saved: AppState?
    public var failSaves = false
    public private(set) var saveCount = 0

    public init(_ initial: AppState? = nil) {
        saved = initial
    }

    public func load() -> AppState? { saved }

    public func save(_ state: AppState) throws {
        if failSaves { throw CocoaError(.fileWriteNoPermission) }
        saved = state
        saveCount += 1
    }
}
