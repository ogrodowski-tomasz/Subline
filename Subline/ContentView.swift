import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var workspace = SublineWorkspace()
    @State private var exportDocument = SRTDocument()
    @State private var isImporting = false
    @State private var isExporting = false

    var body: some View {
        NavigationSplitView {
            SublineSidebarView(
                workspace: workspace,
                importAction: { isImporting = true }
            )
        } detail: {
            SublineDetailView(workspace: workspace)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Importuj TXT", systemImage: "doc.badge.plus") {
                    isImporting = true
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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText]
        ) { result in
            workspace.handleImport(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: workspace.defaultExportFilename
        ) { _ in
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
