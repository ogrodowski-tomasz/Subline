import AVFoundation
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

    enum FrameRateSource: String, CaseIterable, Identifiable {
        case manual
        case videoFile

        var id: String { rawValue }

        var title: String {
            switch self {
            case .manual:
                return "Ręcznie"
            case .videoFile:
                return "Z pliku wideo"
            }
        }
    }

    @Published var sourceFileURL: URL?
    @Published var selectedEncoding: TextEncodingOption = .windowsCP1250
    @Published var frameRateSource: FrameRateSource = .manual {
        didSet { generatePreview() }
    }
    @Published var manualFrameRateInput: String = "" {
        didSet { generatePreview() }
    }
    @Published var videoFileURL: URL?
    @Published var detectedVideoFrameRate: Double? {
        didSet { generatePreview() }
    }
    @Published var sourceText: String = "" {
        didSet { generatePreview() }
    }

    @Published var outputText: String = ""
    @Published var statusMessage: String = "Gotowe"
    @Published var statusLevel: StatusLevel = .info
    @Published var sourceLineCount: Int = 0
    @Published var generatedCueCount: Int = 0

    var canGenerate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && effectiveFrameRate != nil
    }

    var canExport: Bool {
        !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sourceFileName: String {
        sourceFileURL?.lastPathComponent ?? "Nie wybrano pliku"
    }

    var videoFileName: String {
        videoFileURL?.lastPathComponent ?? "Nie wybrano pliku wideo"
    }

    var defaultExportFilename: String {
        let baseName = sourceFileURL?.deletingPathExtension().lastPathComponent ?? "subline"
        return baseName + ".srt"
    }

    var summaryText: String {
        if let frameRate = effectiveFrameRate {
            return "Konwersja MicroDVD z \(formattedFrameRate(frameRate)) fps do SRT."
        }

        return "Konwersja MicroDVD z klatek do SRT."
    }

    var manualFrameRateValue: Double? {
        let normalized = manualFrameRateInput.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    var effectiveFrameRate: Double? {
        switch frameRateSource {
        case .manual:
            return manualFrameRateValue
        case .videoFile:
            return detectedVideoFrameRate ?? detectFrameRateInSourceText()
        }
    }

    var effectiveFrameRateDescription: String {
        guard let frameRate = effectiveFrameRate else {
            switch frameRateSource {
            case .manual:
                return "Wpisz fps ręcznie."
            case .videoFile:
                return "Wskaż plik wideo, aby pobrać fps."
            }
        }

        switch frameRateSource {
        case .manual:
            return "Ręcznie: \(formattedFrameRate(frameRate)) fps"
        case .videoFile:
            if let detectedVideoFrameRate {
                return "Z pliku wideo: \(formattedFrameRate(detectedVideoFrameRate)) fps"
            }

            return "Z pliku wideo: \(formattedFrameRate(frameRate)) fps"
        }
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

    func handleVideoImport(_ result: Result<URL, Error>) async {
        switch result {
        case .success(let url):
            await loadVideoMetadata(from: url)
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

    func loadVideoMetadata(from url: URL) async {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)

            guard let track = tracks.first else {
                videoFileURL = url
                detectedVideoFrameRate = nil
                statusMessage = "Plik wideo nie zawiera ścieżki wideo."
                statusLevel = .warning
                generatePreview()
                return
            }

            let frameRate = try await track.load(.nominalFrameRate)

            videoFileURL = url
            detectedVideoFrameRate = frameRate > 0 ? Double(frameRate) : nil

            if let detectedVideoFrameRate {
                statusMessage = "Pobrano fps z pliku wideo: \(formattedFrameRate(detectedVideoFrameRate))."
                statusLevel = .success
            } else {
                statusMessage = "Nie udało się pobrać fps z pliku wideo."
                statusLevel = .warning
            }

            generatePreview()
        } catch {
            videoFileURL = url
            detectedVideoFrameRate = nil
            statusMessage = "Nie udało się odczytać fps z pliku wideo: \(error.localizedDescription)"
            statusLevel = .error
            generatePreview()
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

        guard let frameRate = effectiveFrameRate else {
            outputText = ""
            generatedCueCount = 0
            statusMessage = frameRateSource == .manual ? "Podaj poprawne fps ręcznie." : "Wskaż plik wideo albo wpisz fps ręcznie."
            statusLevel = .warning
            return
        }

        let cues = parseMicroDVDText(trimmed, frameRate: frameRate)

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

    func parseMicroDVDText(_ text: String, frameRate: Double) -> [SubtitleCue] {
        text.components(separatedBy: .newlines).compactMap { line in
            parseMicroDVDLine(line, frameRate: frameRate)
        }
    }

    func parseMicroDVDLine(_ line: String, frameRate: Double) -> SubtitleCue? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let declaredFrameRate = parseDeclaredFrameRate(from: trimmed), declaredFrameRate > 0 {
            return nil
        }

        guard let match = matchMicroDVDLine(trimmed) else {
            return nil
        }

        guard let startFrame = Int(match[1]),
              let endFrame = Int(match[2]) else {
            return nil
        }

        let subtitleText = microDVDText(from: match[3])
        guard !subtitleText.isEmpty else {
            return nil
        }

        return SubtitleCue(
            start: frameToTimestamp(startFrame, frameRate: frameRate),
            end: frameToTimestamp(endFrame, frameRate: frameRate),
            text: subtitleText
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

    func matchMicroDVDLine(_ line: String) -> [String]? {
        matchRegex(#"^\{(\d+)\}\{(\d+)\}(.*)$"#, in: line)
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

    func detectFrameRateInSourceText() -> Double? {
        let lines = sourceText.components(separatedBy: .newlines)
        guard let firstNonEmptyLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }

        return parseDeclaredFrameRate(from: firstNonEmptyLine.trimmingCharacters(in: .whitespacesAndNewlines))
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
