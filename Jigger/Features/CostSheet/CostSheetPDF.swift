import SwiftUI
import UIKit
import JiggerCore

/// Turns a cost sheet into a paginated PDF (US Letter) using the system's HTML print layout.
enum CostSheetPDF {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margins = UIEdgeInsets(top: 48, left: 44, bottom: 48, right: 44)

    static func render(_ sheet: CostSheet) -> Data {
        let renderer = PageRenderer(page: CGRect(origin: .zero, size: pageSize), margins: margins)
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: sheet.html), startingAtPageAt: 0)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, renderer.paperRect, [
            kCGPDFContextTitle as String: "\(sheet.title) cost analysis",
            kCGPDFContextCreator as String: "Jigger",
        ])
        let pages = max(renderer.numberOfPages, 1)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for i in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// Writes the PDF to a temporary file named after the drink, for sharing or saving to Files.
    static func writeTemporaryFile(_ sheet: CostSheet) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CostSheets", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(sheet.fileName)
        try render(sheet).write(to: url, options: .atomic)
        return url
    }

    private final class PageRenderer: UIPrintPageRenderer {
        private let page: CGRect
        private let printable: CGRect

        init(page: CGRect, margins: UIEdgeInsets) {
            self.page = page
            self.printable = page.inset(by: margins)
            super.init()
        }

        override var paperRect: CGRect { page }
        override var printableRect: CGRect { printable }
    }
}

/// AirPrint for the cost sheet.
enum CostSheetPrinter {
    /// Shows the print dialog. Returns false when printing isn't available.
    @discardableResult
    static func print(_ sheet: CostSheet) -> Bool {
        guard UIPrintInteractionController.isPrintingAvailable else { return false }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "\(sheet.title) cost analysis"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = CostSheetPDF.render(sheet)
        controller.present(animated: true)
        return true
    }
}

struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet (Share, Save to Files, Print, AirDrop, Mail…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
