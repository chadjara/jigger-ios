import Foundation
import JiggerEngine

/// The backup file format, shared with the website: `{ app: "jigger", version: 1, library, recipes }`.
struct BackupFile: Encodable {
    var app = "jigger"
    var version = 1
    var exportedAt: String?
    var library: [LibraryItem]
    var recipes: [Recipe]
}

/// Reading side of the backup: tolerant of odd entries (skipped), strict about the overall shape.
struct IncomingBackup: Decodable {
    var library: [LibraryItem]
    var recipes: [Recipe]

    enum CodingKeys: String, CodingKey { case library, recipes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        library = try c.decode([Skippable<LibraryItem>].self, forKey: .library).compactMap(\.value)
        recipes = try c.decode([Skippable<Recipe>].self, forKey: .recipes).compactMap(\.value)
    }
}

/// Decodes an array element, or nil instead of failing the whole array.
struct Skippable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public enum BackupError: Error, Equatable {
    case notABackup
}

public struct ImportSummary: Equatable, Sendable {
    public var recipes: Int
    public var ingredients: Int

    public var message: String {
        "Imported \(recipes) recipe\(recipes == 1 ? "" : "s") and \(ingredients) ingredient\(ingredients == 1 ? "" : "s")"
    }
}

extension AppStore {
    /// A suggested file name for a backup made today.
    public var backupFileName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return "jigger-backup-\(f.string(from: clock())).json"
    }

    /// All saved recipes and ingredients as a backup file.
    public func exportBackup() throws -> Data {
        let file = BackupFile(exportedAt: now(), library: state.library, recipes: state.recipes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Adds a backup's recipes and ingredients (same id replaces). Shows the result as a message.
    @discardableResult
    public func importBackup(_ data: Data) -> ImportSummary? {
        do {
            let summary = try importBackupThrowing(data)
            showToast(summary.message)
            return summary
        } catch {
            showToast("That file isn’t a Jigger backup")
            return nil
        }
    }

    func importBackupThrowing(_ data: Data) throws -> ImportSummary {
        guard let file = try? JSONDecoder().decode(IncomingBackup.self, from: data) else { throw BackupError.notABackup }
        let t = now()
        let lib: [LibraryItem] = file.library.filter { !$0.id.isEmpty && !$0.name.isEmpty }.map { i in
            var i = i
            if JiggerUnit(rawValue: i.sizeUnit) == nil { i.sizeUnit = "ml" }
            if i.createdAt.isEmpty { i.createdAt = t }
            if i.updatedAt.isEmpty { i.updatedAt = t }
            return i
        }
        let recs: [Recipe] = file.recipes.filter { !$0.id.isEmpty }.map { r in
            var r = r
            r.isExample = false
            if r.createdAt.isEmpty { r.createdAt = t }
            if r.updatedAt.isEmpty { r.updatedAt = t }
            r.lines = r.lines.prefix(Catalog.maxLines).map { l in
                var l = l
                if l.id.isEmpty { l.id = makeID() }
                if JiggerUnit(rawValue: l.sizeUnit) == nil { l.sizeUnit = "ml" }
                if JiggerUnit(rawValue: l.amountUnit) == nil { l.amountUnit = "floz" }
                return l
            }
            return r
        }
        mutateState { s in
            for i in lib {
                if let k = s.library.firstIndex(where: { $0.id == i.id }) { s.library[k] = i } else { s.library.append(i) }
            }
            for r in recs {
                if let k = s.recipes.firstIndex(where: { $0.id == r.id }) { s.recipes[k] = r } else { s.recipes.append(r) }
            }
        }
        flush()
        return ImportSummary(recipes: recs.count, ingredients: lib.count)
    }
}
