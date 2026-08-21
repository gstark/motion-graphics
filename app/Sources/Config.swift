import Foundation

// Resolves tool and directory locations. Prefers binaries bundled in the
// app's Resources, then falls back to development locations.
enum Config {
    static let appSupport: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MotionGraphics")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var jobsDir: URL { appSupport.appendingPathComponent("jobs") }

    // Development checkout, used when the app runs without bundled resources.
    static let devRoot = URL(fileURLWithPath: "/Users/gstark/dev/personal/motion-graphics")

    static var bundledBin: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let bin = res.appendingPathComponent("bin")
        return FileManager.default.fileExists(atPath: bin.path) ? bin : nil
    }

    static func tool(_ name: String, fallbacks: [String]) -> URL {
        if let bin = bundledBin {
            let candidate = bin.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        for fallback in fallbacks where FileManager.default.fileExists(atPath: fallback) {
            return URL(fileURLWithPath: fallback)
        }
        return URL(fileURLWithPath: "/usr/bin/false")
    }

    static var node: URL {
        tool("node", fallbacks: [
            "/opt/homebrew/bin/node",
            NSHomeDirectory() + "/.local/share/mise/shims/node",
            "/usr/local/bin/node",
        ])
    }

    static var ffmpeg: URL {
        tool("ffmpeg", fallbacks: ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"])
    }

    static var ffprobe: URL {
        tool("ffprobe", fallbacks: ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"])
    }

    static var ytdlp: URL {
        tool("yt-dlp", fallbacks: ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"])
    }

    static var transcriber: URL {
        tool("mg-transcribe", fallbacks: [devRoot.appendingPathComponent("bin/mg-transcribe").path])
    }

    // The worker runs from Application Support when the app bundles it
    // (so node_modules/.remotion stays writable); otherwise straight from
    // the development checkout.
    static var workerDir: URL {
        let installed = appSupport.appendingPathComponent("worker")
        if FileManager.default.fileExists(atPath: installed.appendingPathComponent("render.js").path) {
            return installed
        }
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("worker")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("render.js").path) {
                return bundled
            }
        }
        return devRoot.appendingPathComponent("worker")
    }

    static var bundledWorker: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let worker = res.appendingPathComponent("worker")
        return FileManager.default.fileExists(atPath: worker.appendingPathComponent("render.js").path) ? worker : nil
    }

    static var outputDir: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Motion Graphics")
        try? FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        return movies
    }
}
