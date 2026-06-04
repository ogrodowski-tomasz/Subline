import Combine
import Foundation
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
    @Published var selectedEncoding: TextEncodingOption = .windowsCP1250 {
        didSet {
            guard sourceFileURL != nil else {
                return
            }

            reloadSource()
        }
    }
    @Published var manualFrameRateInput: String = "" {
        didSet { schedulePreviewRefresh() }
    }
    @Published var sourceText: String = "" {
        didSet { schedulePreviewRefresh() }
    }

    @Published var outputText: String = ""
    @Published var statusMessage: String = "Gotowe"
    @Published var statusLevel: StatusLevel = .info
    @Published var sourceLineCount: Int = 0
    @Published var generatedCueCount: Int = 0

    private var previewRefreshTask: Task<Void, Never>?

    var canGenerate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && effectiveFrameRate != nil
    }

    var canExport: Bool {
        !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sourceFileName: String {
        sourceFileURL?.lastPathComponent ?? "Nie wybrano pliku"
    }

    var defaultExportFilename: String {
        let baseName = sourceFileURL?.deletingPathExtension().lastPathComponent ?? "subline"
        return baseName
    }

    var summaryText: String {
        if let frameRate = effectiveFrameRate {
            return "Konwersja MicroDVD z \(formattedFrameRate(frameRate)) fps do SRT."
        }

        return "Konwersja MicroDVD z klatek do SRT."
    }

    var manualFrameRateValue: Double? {
        let normalized = manualFrameRateInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    var effectiveFrameRate: Double? {
        manualFrameRateValue
    }

    var effectiveFrameRateDescription: String {
        guard let frameRate = effectiveFrameRate else {
            return "Wpisz fps ręcznie."
        }

        return "Ręcznie: \(formattedFrameRate(frameRate)) fps"
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
            sourceFileURL = url
            sourceText = try readText(from: url)
            sourceLineCount = sourceText.components(separatedBy: .newlines).count
            statusMessage = "Zaimportowano plik napisów."
            statusLevel = .success
            generatePreview()
        } catch {
            statusMessage = "Nie udało się odczytać pliku: \(error.localizedDescription)"
            statusLevel = .error
        }
    }

    private func reloadSource() {
        guard let url = sourceFileURL else {
            return
        }

        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            sourceText = try readText(from: url)
            sourceLineCount = sourceText.components(separatedBy: .newlines).count
            statusMessage = "Przeładowano plik po zmianie kodowania."
            statusLevel = .success
            generatePreview()
        } catch {
            statusMessage = "Nie udało się ponownie odczytać pliku: \(error.localizedDescription)"
            statusLevel = .error
        }
    }

    func generatePreview() {
        previewRefreshTask?.cancel()
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

        guard let frameRate = effectiveFrameRate else {
            outputText = ""
            generatedCueCount = 0
            statusMessage = "Podaj poprawne fps ręcznie."
            statusLevel = .warning
            return
        }

        let parseResult = parseMicroDVDText(trimmed, frameRate: frameRate)
        let cues = parseResult.cues

        guard !cues.isEmpty else {
            outputText = ""
            generatedCueCount = 0
            if parseResult.matchedLineCount == 0 {
                statusMessage = "Nie wykryto żadnych linii w formacie MicroDVD {start}{end}tekst."
            } else if parseResult.emptySubtitleCount > 0 {
                statusMessage = "Wykryto \(parseResult.matchedLineCount) linii MicroDVD, ale \(parseResult.emptySubtitleCount) miało pusty tekst po znacznikach."
            } else if parseResult.invalidFrameCount > 0 {
                statusMessage = "Wykryto \(parseResult.matchedLineCount) linii MicroDVD, ale \(parseResult.invalidFrameCount) miało niepoprawne numery klatek."
            } else {
                statusMessage = "Wykryto \(parseResult.matchedLineCount) linii MicroDVD, ale żadna nie dała poprawnego napisu."
            }
            statusLevel = .warning
            return
        }

        generatedCueCount = cues.count
        outputText = renderSRT(from: cues)
        statusMessage = "Wygenerowano \(cues.count) wpisów SRT."
        statusLevel = .success
    }

    private func schedulePreviewRefresh() {
        previewRefreshTask?.cancel()

        previewRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else {
                return
            }

            self.generatePreview()
        }
    }
}

private extension SublineWorkspace {
    struct SubtitleCue {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    struct MicroDVDParseResult {
        let cues: [SubtitleCue]
        let matchedLineCount: Int
        let emptySubtitleCount: Int
        let invalidFrameCount: Int
    }

    struct MicroDVDLine {
        let startFrame: Int?
        let endFrame: Int?
        let subtitleText: String
    }

    func parseMicroDVDText(_ text: String, frameRate: Double) -> MicroDVDParseResult {
        var cues: [SubtitleCue] = []
        var matchedLineCount = 0
        var emptySubtitleCount = 0
        var invalidFrameCount = 0

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if parseDeclaredFrameRate(from: trimmed) != nil {
                continue
            }

            guard let parsedLine = parseMicroDVDLine(trimmed) else {
                continue
            }

            matchedLineCount += 1

            guard let startFrame = parsedLine.startFrame,
                  let endFrame = parsedLine.endFrame else {
                invalidFrameCount += 1
                continue
            }

            let subtitleText = microDVDText(from: parsedLine.subtitleText)
            guard !subtitleText.isEmpty else {
                emptySubtitleCount += 1
                continue
            }

            cues.append(
                SubtitleCue(
                    start: frameToTimestamp(startFrame, frameRate: frameRate),
                    end: frameToTimestamp(endFrame, frameRate: frameRate),
                    text: subtitleText
                )
            )
        }

        return MicroDVDParseResult(
            cues: cues,
            matchedLineCount: matchedLineCount,
            emptySubtitleCount: emptySubtitleCount,
            invalidFrameCount: invalidFrameCount
        )
    }

    func parseMicroDVDLine(_ line: String) -> MicroDVDLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if parseDeclaredFrameRate(from: trimmed) != nil {
            return nil
        }

        guard trimmed.first == "{",
              let firstClosingBrace = trimmed.firstIndex(of: "}") else {
            return nil
        }

        let afterStartBrace = trimmed.index(after: trimmed.startIndex)
        guard afterStartBrace < firstClosingBrace else {
            return nil
        }

        let startFrameString = String(trimmed[afterStartBrace..<firstClosingBrace])
        let remainder = trimmed[trimmed.index(after: firstClosingBrace)...]
        guard remainder.first == "{",
              let secondClosingBrace = remainder.firstIndex(of: "}") else {
            return nil
        }

        let afterSecondOpeningBrace = remainder.index(after: remainder.startIndex)
        guard afterSecondOpeningBrace < secondClosingBrace else {
            return nil
        }

        let endFrameString = String(remainder[afterSecondOpeningBrace..<secondClosingBrace])
        let subtitleText = String(remainder[remainder.index(after: secondClosingBrace)...])

        return MicroDVDLine(
            startFrame: Int(startFrameString),
            endFrame: Int(endFrameString),
            subtitleText: subtitleText
        )
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

    func parseDeclaredFrameRate(from line: String) -> Double? {
        guard let match = matchRegex(#"^\{1\}\{1\}(\d+(?:\.\d+)?)$"#, in: line) else {
            return nil
        }

        return Double(match[1])
    }

    func matchRegex(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let groupRange = match.range(at: index)
            guard let swiftRange = Range(groupRange, in: text) else {
                groups.append("")
                continue
            }
            groups.append(String(text[swiftRange]))
        }

        return groups
    }

    func frameToTimestamp(_ frame: Int, frameRate: Double) -> TimeInterval {
        TimeInterval(frame) / frameRate
    }

    func microDVDText(from text: String) -> String {
        text
            .replacingOccurrences(of: "|", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func formattedFrameRate(_ value: Double) -> String {
        String(format: "%.3f", value)
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
    static var readableContentTypes: [UTType] { [.srt] }

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
