import SwiftUI

struct ConversionHeaderCard: View {
    @ObservedObject var workspace: SublineWorkspace
    let regenerateAction: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Przebieg konwersji")
                            .font(.title2.weight(.semibold))
                        Text(workspace.summaryText)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button("Generuj ponownie", systemImage: "arrow.clockwise") {
                        regenerateAction()
                    }
                    .disabled(!workspace.canGenerate)
                }

                Divider()

                HStack(spacing: 12) {
                    Label("Ręcznie", systemImage: "clock")
                    Spacer()
                    Label(workspace.effectiveFrameRateDescription, systemImage: "film")
                    Spacer()
                    Label("\(workspace.generatedCueCount) wpisów", systemImage: "text.alignleft")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EditablePreviewCard: View {
    let title: String
    let subtitle: String
    @Binding var text: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                header

                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ReadOnlyPreviewCard: View {
    let title: String
    let subtitle: String
    let text: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                header

                TextEditor(text: .constant(text))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
