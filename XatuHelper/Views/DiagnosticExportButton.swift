import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticExportButton: View {
    var filenamePrefix = "XATune-diagnostics"
    let content: () -> String

    @State private var document = DiagnosticTextDocument(text: "")
    @State private var showsExporter = false
    @State private var filename = ""
    @State private var exportError: String?

    var body: some View {
        Button {
            document = DiagnosticTextDocument(text: content())
            let timestamp = Date().ISO8601Format().replacingOccurrences(of: ":", with: "-")
            filename = "\(filenamePrefix)-\(timestamp).txt"
            showsExporter = true
        } label: {
            Label("导出诊断文件", systemImage: "square.and.arrow.up")
        }
        .fileExporter(isPresented: $showsExporter, document: document,
                      contentType: .plainText, defaultFilename: filename) { result in
            if case let .failure(error) = result {
                let ns = error as NSError
                guard !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) else { return }
                exportError = error.localizedDescription
            }
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }
}

private struct DiagnosticTextDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
