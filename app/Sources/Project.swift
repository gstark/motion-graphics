import Foundation

// Persisted metadata for a project, saved as project.json in the folder.
struct ProjectInfo: Codable {
    var name: String
    var mode: String            // LayoutMode rawValue
    var direction: String
    var sourceURLText: String?  // original link, when downloaded
    var createdAt: Date
    var updatedAt: Date
}

// A project is a folder on disk holding everything for one video:
// the source, transcript, the Remotion project the agent edits, and output.
struct Project: Identifiable {
    let folder: URL
    var info: ProjectInfo

    var id: String { folder.path }
    var name: String { info.name }

    // Layout mirrors the worker's jobPaths().
    var remotionDir: URL { folder.appendingPathComponent("project") }
    var metaFile: URL { remotionDir.appendingPathComponent("src/job/meta.json") }
    var transcriptFile: URL { remotionDir.appendingPathComponent("src/job/transcript.json") }
    var outputDir: URL { folder.appendingPathComponent("output") }
    var downloadDir: URL { folder.appendingPathComponent("download") }

    var sourceFile: URL? {
        let re = try? NSRegularExpression(pattern: "^source\\.(mp4|mov|webm|mkv|m4v)$", options: .caseInsensitive)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        for name in names {
            let range = NSRange(name.startIndex..., in: name)
            if re?.firstMatch(in: name, range: range) != nil {
                return folder.appendingPathComponent(name)
            }
        }
        return nil
    }

    var hasSource: Bool { sourceFile != nil }

    var hasTranscript: Bool {
        guard let data = try? Data(contentsOf: transcriptFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = json["segments"] as? [Any]
        else { return false }
        return !segments.isEmpty
    }

    var existingOutput: URL? {
        for name in ["final.mp4", "graphics.mov"] {
            let url = outputDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

@MainActor
enum ProjectStore {
    // Visible, Finder-accessible root that holds every project folder.
    static var root: URL {
        let url = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Motion Graphics")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func infoURL(_ folder: URL) -> URL {
        folder.appendingPathComponent("project.json")
    }

    static func save(_ project: Project) {
        var info = project.info
        info.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(info) {
            try? data.write(to: infoURL(project.folder))
        }
    }

    static func load(_ folder: URL) -> Project? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: infoURL(folder)),
              let info = try? decoder.decode(ProjectInfo.self, from: data)
        else { return nil }
        return Project(folder: folder, info: info)
    }

    static func list() -> [Project] {
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return names
            .compactMap { load($0) }
            .sorted { $0.info.updatedAt > $1.info.updatedAt }
    }

    static func create(name: String, mode: LayoutMode) -> Project {
        let safe = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let base = safe.isEmpty ? "Untitled" : safe
        var folder = root.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(base) \(n)")
            n += 1
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let info = ProjectInfo(
            name: folder.lastPathComponent,
            mode: mode.rawValue,
            direction: "",
            sourceURLText: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        let project = Project(folder: folder, info: info)
        save(project)
        return project
    }
}
