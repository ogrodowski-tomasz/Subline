import SwiftUI

struct SublineDetailView: View {
    @ObservedObject var workspace: SublineWorkspace
    let exportAction: () -> Void

    var body: some View {
        if workspace.sourceText.isEmpty {
            SublineEmptyStateView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ConversionHeaderCard(
                        workspace: workspace,
                        regenerateAction: { workspace.generatePreview() },
                        exportAction: exportAction
                    )
                    EditablePreviewCard(
                        title: "Podgląd źródła",
                        subtitle: "Oryginalny tekst z TXT",
                        text: $workspace.sourceText
                    )
                    ReadOnlyPreviewCard(
                        title: "Wynik SRT",
                        subtitle: "Tekst gotowy do eksportu",
                        text: workspace.outputText
                    )
                }
                .padding(24)
            }
        }
    }
}

private struct SublineEmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "Brak pliku wejściowego",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Zaimportuj plik MicroDVD TXT i podaj fps ręcznie, aby zobaczyć podgląd i wygenerować plik SRT.")
        )
    }
}
