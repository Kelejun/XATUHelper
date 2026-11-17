import SwiftUI
import UIKit

struct DiagnosticExportButton: View {
    var filenamePrefix = "App-diagnostics"
    let content: () -> String

    @State private var sharedFile: DiagnosticSharedFile?
    @State private var temporaryDirectory: URL?
    @State private var exportError: String?

    var body: some View {
        Button {
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DiagnosticExport-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                temporaryDirectory = directory
                let timestamp = Date().ISO8601Format().replacingOccurrences(of: ":", with: "-")
                let url = directory.appendingPathComponent("\(filenamePrefix)-\(timestamp).txt")
                try content().write(to: url, atomically: true, encoding: .utf8)
                sharedFile = DiagnosticSharedFile(url: url)
            } catch {
                removeTemporaryFile()
                exportError = error.localizedDescription
            }
        } label: {
            Label("导出诊断文件", systemImage: "square.and.arrow.up")
        }
        .sheet(item: $sharedFile, onDismiss: removeTemporaryFile) { file in
            DiagnosticShareSheet(url: file.url) { error in
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

    private func removeTemporaryFile() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }
}

private struct DiagnosticSharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            guard let error else { return }
            let ns = error as NSError
            guard !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) else { return }
            DispatchQueue.main.async {
                onError(error)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
