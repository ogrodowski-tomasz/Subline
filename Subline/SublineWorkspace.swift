import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SublineWorkspace: ObservableObject {
    enum StatusLevel {
        case info
        case success
        case warning
        case error

        var title: String {
            switch self {
            case .info:
                return "Informacja"
            case .success:
                return "Sukces"
            case .warning:
                return "Ostrzeżenie"
            case .error:
                return "Błąd"
            }
        }

        var systemImage: String {
            switch self {
            case .info:
                return "info.circle"
            case .success:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }
    }

    enum TextEncodingOption: String, CaseIterable, Identifiable {
        case windowsCP1250
        case utf8
        case utf16
        case utf16LittleEndian
        case utf16BigEndian
        case isoLatin1

        var id: String { rawValue }

        var title: String {
            switch self {
            case .windowsCP1250:
                return "Windows-1250"
            case .utf8:
                return "UTF-8"
            case .utf16:
                return "UTF-16"
            case .utf16LittleEndian:
                return "UTF-16 LE"
            case .utf16BigEndian:
                return "UTF-16 BE"
            case .isoLatin1:
                return "ISO Latin 1"
            }
        }

        var stringEncoding: String.Encoding {
            switch self {
            case .windowsCP1250:
                return .windowsCP1250
            case .utf8:
                return .utf8
            case .utf16:
                return .utf16
            case .utf16LittleEndian:
                return .utf16LittleEndian
            case .utf16BigEndian:
                return .utf16BigEndian
            case .isoLatin1:
                return .isoLatin1
            }
        }
    }

    @Published var sourceFileURL: URL?
    @Published var selectedEncoding: TextEncodingOption = .windowsCP1250
    @Published var sourceText: String = "" {
        didSet { generatePreview() }
    }

    @Published var outputText: String = ""
    @Published var statusMessage: String = "Gotowe"
    @Published var statusLevel: StatusLevel = .info
    @Published var sourceLineCount: Int = 0
    @Published var generatedCueCount: Int = 0

    var canGenerate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canExport: Bool {
        !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sourceFileName: String {
        sourceFileURL?.lastPathComponent ?? "Nie wybrano pliku"
    }

    var defaultExportFilename: String {
        let baseName = sourceFileURL?.deletingPathExtension().lastPathComponent ?? "subline"
        return baseName + ".srt"
    }

    var summaryText: String {
        "Parsowanie bloków z czasami i eksport do standardowego formatu SRT."
    }

    init() {
        generatePreview()
    }

    func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            loadSource(from: url)
        case .failure(let error):
            statusMessage = error.localizedDescription
            statusLevel = .error
        }
    }

    func loadSource(from url: URL) {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            sourceText = try readText(from: url)
            sourceFileURL = url
            sourceLineCount = sourceText.components(separatedBy: .newlines).count
            statusMessage = "Zaimportowano plik."
            statusLevel = .success
            generatePreview()
        } catch {
            statusMessage = "Nie udało się odczytać pliku: \(error.localizedDescription)"
            statusLevel = .error
        }
    }

    func generatePreview() {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            outputText = ""
            generatedCueCount = 0
            sourceLineCount = 0
            statusMessage = "Brak danych wejściowych."
            statusLevel = .info
            return
        }

        sourceLineCount = sourceText.components(separatedBy: .newlines).count

        let cues = parseTimestampedText(trimmed)

        guard !cues.isEmpty else {
            outputText = ""
            generatedCueCount = 0
            statusMessage = "Nie znaleziono poprawnych wpisów do konwersji."
            statusLevel = .warning
            return
        }

        generatedCueCount = cues.count
        outputText = renderSRT(from: cues)
        statusMessage = "Wygenerowano \(cues.count) wpisów SRT."
        statusLevel = .success
    }
}

private extension SublineWorkspace {
    struct SubtitleCue {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    func parseTimestampedText(_ text: String) -> [SubtitleCue] {
        splitBlocks(in: text).compactMap { block in
            guard let cue = parseTimestampedBlock(block) else {
                return nil
            }
            return cue
        }
    }

    func parseTimestampedBlock(_ block: [String]) -> SubtitleCue? {
        guard let timeLineIndex = block.firstIndex(where: { parseTimeRange(from: $0) != nil }) else {
            return nil
        }

        guard let range = parseTimeRange(from: block[timeLineIndex]) else {
            return nil
        }

        let textLines = block[(timeLineIndex + 1)...].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let subtitleText = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subtitleText.isEmpty else {
            return nil
        }

        return SubtitleCue(start: range.start, end: range.end, text: subtitleText)
    }

    func renderSRT(from cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            [
                String(index + 1),
                "\(formatTimestamp(cue.start)) --> \(formatTimestamp(cue.end))",
                cue.text
            ]
            .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: selectedEncoding.stringEncoding) {
            return text
        }

        return try readTextFallback(from: data)
    }

    func readTextFallback(from data: Data) throws -> String {
        let encodings: [String.Encoding] = [
            .windowsCP1250,
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                statusMessage = "Użyto awaryjnego kodowania: \(encoding.label)"
                statusLevel = .warning
                return text
            }
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func splitBlocks(in text: String) -> [[String]] {
        var blocks: [[String]] = []
        var currentBlock: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
                    currentBlock.removeAll(keepingCapacity: true)
                }
            } else {
                currentBlock.append(trimmed)
            }
        }

        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        return blocks
    }

    func parseTimeRange(from line: String) -> (start: TimeInterval, end: TimeInterval)? {
        let normalized = line
            .replacingOccurrences(of: "-->", with: " ")
            .replacingOccurrences(of: "→", with: " ")

        let tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)

        if tokens.count >= 3,
           isInteger(tokens[0]),
           let start = parseTimestamp(tokens[1]),
           let end = parseTimestamp(tokens[2]) {
            return (start, end)
        }

        if tokens.count >= 2,
           let start = parseTimestamp(tokens[0]),
           let end = parseTimestamp(tokens[1]) {
            return (start, end)
        }

        return nil
    }

    func isInteger(_ value: String) -> Bool {
        Int(value) != nil
    }

    func parseTimestamp(_ value: String) -> TimeInterval? {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            return nil
        }

        let secondsParts = parts[2].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard secondsParts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let seconds = Int(secondsParts[0]),
              let milliseconds = Int(secondsParts[1]) else {
            return nil
        }

        let totalMilliseconds = (hours * 3_600_000) + (minutes * 60_000) + (seconds * 1_000) + milliseconds
        return TimeInterval(totalMilliseconds) / 1_000
    }

    func formatTimestamp(_ value: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((value * 1_000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}

private extension String.Encoding {
    var label: String {
        switch self {
        case .windowsCP1250:
            return "Windows-1250"
        case .utf8:
            return "UTF-8"
        case .utf16:
            return "UTF-16"
        case .utf16LittleEndian:
            return "UTF-16 LE"
        case .utf16BigEndian:
            return "UTF-16 BE"
        case .isoLatin1:
            return "ISO Latin 1"
        default:
            return "Unknown"
        }
    }
}

struct SRTDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        text = string
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
