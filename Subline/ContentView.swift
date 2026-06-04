import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var workspace = SublineWorkspace()
    @State private var exportDocument = SRTDocument()
    @State private var isExporting = false

    var body: some View {
        NavigationSplitView {
            SublineSidebarView(
                workspace: workspace,
                importAction: openSubtitleFile,
                videoImportAction: openVideoFile
            )
        } detail: {
            SublineDetailView(workspace: workspace)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Importuj TXT", systemImage: "doc.badge.plus") {
                    openSubtitleFile()
                }

                Button("Generuj SRT", systemImage: "sparkles") {
                    workspace.generatePreview()
                }
                .disabled(!workspace.canGenerate)

                Button("Eksportuj", systemImage: "square.and.arrow.down") {
                    exportDocument.text = workspace.outputText
                    isExporting = true
                }
                .disabled(!workspace.canExport)
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: workspace.defaultExportFilename
        ) { _ in
        }
    }

    private func openSubtitleFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.message = "Wybierz plik TXT z napisami MicroDVD"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        workspace.handleImport(.success(url))
    }

    private func openVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.message = "Wybierz plik wideo, z którego odczytamy fps"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task { @MainActor in
            await workspace.handleVideoImport(.success(url))
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
