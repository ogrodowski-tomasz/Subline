import SwiftUI

struct SublineSidebarView: View {
    @ObservedObject var workspace: SublineWorkspace
    let importAction: () -> Void

    var body: some View {
        Form {
            statusBanner
            sourceSection
            statusSection
        }
        .formStyle(.grouped)
        .navigationTitle("Subline")
        .navigationSubtitle("TXT do SRT")
        .frame(minWidth: 280)
    }
}

private extension SublineSidebarView {
    var sourceSection: some View {
        Section("Źródło") {
            Button(action: importAction) {
                Label("Wybierz plik TXT", systemImage: "doc.text")
            }

            LabeledContent("Plik") {
                Text(workspace.sourceFileName)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Wiersze") {
                Text("\(workspace.sourceLineCount)")
                    .foregroundStyle(.secondary)
            }

            Picker("Kodowanie", selection: $workspace.selectedEncoding) {
                ForEach(SublineWorkspace.TextEncodingOption.allCases) { encoding in
                    Text(encoding.title).tag(encoding)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Format") {
                Text("MicroDVD")
                    .foregroundStyle(.secondary)
            }

            Text("Każda linia ma postać {start}{end}tekst.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

                VStack(alignment: .leading, spacing: 8) {
                    TextField("np. 23.976", text: $workspace.manualFrameRateInput)
                        .textFieldStyle(.roundedBorder)

                    Text("Podaj liczbę klatek na sekundę użytych przez napisy MicroDVD.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
    }

    var statusBanner: some View {
        Section {
            StatusBannerView(level: workspace.statusLevel, message: workspace.statusMessage)
        }
        .listRowBackground(Color.clear)
    }

    var statusSection: some View {
        Section("Stan") {
            LabeledContent("Wpisy SRT") {
                Text("\(workspace.generatedCueCount)")
            }

            LabeledContent("Status") {
                Text(workspace.statusMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct StatusBannerView: View {
    let level: SublineWorkspace.StatusLevel
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: level.systemImage)
                .foregroundStyle(accentColor)
                .font(.title3)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(level.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .textCase(.uppercase)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accentColor.opacity(0.2))
        }
    }

    private var accentColor: Color {
        switch level {
        case .info:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
