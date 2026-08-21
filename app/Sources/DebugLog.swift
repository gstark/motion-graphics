import Foundation

// A running log of everything the pipeline does: each subprocess command,
// its raw output, and the agent's own tool calls. Shown in the Debug panel
// on the working screen.
final class DebugLog: ObservableObject {
    enum Kind: String {
        case command
        case stdout
        case stderr
        case tool
        case info
        case error
    }

    struct Line: Identifiable {
        let id = UUID()
        let time: Date
        let kind: Kind
        let text: String
    }

    @Published var lines: [Line] = []
    private let maxLines = 6000

    func log(_ kind: Kind, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.async {
            self.lines.append(Line(time: Date(), kind: kind, text: trimmed))
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { self.lines.removeAll() }
    }

    var plainText: String {
        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        return lines.map { "[\(stamp.string(from: $0.time))] \($0.kind.rawValue): \($0.text)" }
            .joined(separator: "\n")
    }
}
