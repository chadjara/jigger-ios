import XCTest
import PDFKit
import JiggerCore
@testable import Jigger

/// App-target tests: things that need UIKit (PDF rendering, colours). Formula and state tests live in JiggerKit.
final class AppTests: XCTestCase {
    private func store() -> AppStore {
        AppStore(storage: MemoryStore(), locale: Locale(identifier: "en_US"), autosaveDelay: nil)
    }

    @MainActor
    func testCostSheetRendersAsAPaginatedPDF() throws {
        let s = store()
        s.setRecipe(.servings, "25")
        let data = CostSheetPDF.render(s.costSheet(for: s.draft))
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        // Section headings are set in capitals by the sheet's CSS, so match case-insensitively.
        for expected in ["Classic Margarita", "$3.69", "Price ladder", "overhead"] {
            XCTAssertTrue(text.localizedCaseInsensitiveContains(expected), "PDF text is missing \(expected)")
        }
    }

    @MainActor
    func testLongRecipesFlowOntoMorePages() throws {
        let s = store()
        for _ in 0..<24 { s.addLine() }
        for line in s.draft.lines { s.setLine(line.id, .name, "Ingredient with a fairly long descriptive name"); s.setLine(line.id, .wastePct, "5") }
        let doc = try XCTUnwrap(PDFDocument(data: CostSheetPDF.render(s.costSheet(for: s.draft))))
        XCTAssertGreaterThan(doc.pageCount, 1)
    }

    @MainActor
    func testCostSheetFileIsWrittenWithTheDrinkName() throws {
        let s = store()
        let url = try CostSheetPDF.writeTemporaryFile(s.costSheet(for: s.draft))
        XCTAssertEqual(url.lastPathComponent, "classic-margarita-cost-sheet.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testThemeHasDistinctLightAndDarkPalettes() {
        let dark = UIColor(Theme.bg).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let light = UIColor(Theme.bg).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertNotEqual(dark, light)
    }

    func testBackupDocumentKeepsItsBytes() throws {
        let s = store()
        let data = try s.exportBackup()
        XCTAssertEqual(BackupDocument(data: data).data, data)
    }
}
