// Transcribes an audio file with the on-device SpeechAnalyzer (macOS 26).
//   mg-transcribe <input audio> <output json> [locale]
// Emits NDJSON progress on stdout, like the node worker scripts.
import AVFoundation
import Foundation
import Speech

struct Segment: Codable {
    let text: String
    let start: Double
    let end: Double
}

struct Transcript: Codable {
    let language: String
    let text: String
    let segments: [Segment]
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func failNow(_ message: String) -> Never {
    emit(["type": "error", "message": message])
    exit(1)
}

@main
struct Transcribe {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            failNow("usage: mg-transcribe <input audio> <output json> [locale]")
        }
        let inputURL = URL(fileURLWithPath: args[1])
        let outputURL = URL(fileURLWithPath: args[2])
        let localeID = args.count > 3 ? args[3] : Locale.current.identifier

        do {
            let locale = Locale(identifier: localeID)
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )

            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                emit(["type": "stage", "stage": "language-model-download"])
                try await request.downloadAndInstall()
            }

            emit(["type": "stage", "stage": "transcribing"])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let audioFile = try AVAudioFile(forReading: inputURL)

            let collector = Task {
                var segments: [Segment] = []
                for try await result in transcriber.results where result.isFinal {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let range = result.range
                    segments.append(Segment(text: text, start: range.start.seconds, end: range.end.seconds))
                }
                return segments
            }

            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                try await analyzer.cancelAndFinishNow()
            }

            let segments = try await collector.value
            let transcript = Transcript(
                language: localeID,
                text: segments.map(\.text).joined(separator: " "),
                segments: segments
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(transcript).write(to: outputURL)
            emit(["type": "done", "segments": segments.count, "output": outputURL.path])
        } catch {
            failNow("transcription failed: \(error)")
        }
    }
}
