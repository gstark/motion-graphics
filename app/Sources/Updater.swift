import AppKit
import Foundation

// Checks GitHub releases for a newer version on launch. When the user
// accepts, downloads the release zip, verifies its signature, swaps the
// bundle in place, and relaunches.
enum Updater {
    static let repo = "gstark/motion-graphics"

    struct AvailableUpdate {
        let version: String // "0.2.0", no leading v
        let assetURL: URL
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // "dev" for unstamped builds run from Xcode; "v0.1.0" for releases.
    static var versionLabel: String {
        currentVersion == "0.0.0" ? "dev" : "v" + currentVersion
    }

    // MARK: - Check

    // Nil when up to date, offline, or running a dev or translocated build.
    static func check() async -> AvailableUpdate? {
        guard currentVersion != "0.0.0",
              !Bundle.main.bundlePath.contains("/AppTranslocation/") else { return nil }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return nil }

        let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard isNewer(latest, than: currentVersion),
              let asset = release.assets.first(where: { $0.name == "MotionGraphics.zip" })
        else { return nil }
        return AvailableUpdate(version: latest, assetURL: asset.url)
    }

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let url: URL
        enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
        }
    }

    // Numeric dotted-version comparison; unequal lengths pad with zero.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Install

    // Downloads, verifies, swaps the bundle, and relaunches. Does not
    // return on success. Throws a user-facing message on failure.
    static func install(_ update: AvailableUpdate, progress: @escaping @Sendable (String) -> Void) async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("MotionGraphicsUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        progress("Downloading version \(update.version)…")
        let zip = staging.appendingPathComponent("MotionGraphics.zip")
        try await download(from: update.assetURL, to: zip) { percent in
            progress("Downloading version \(update.version)… \(percent)%")
        }

        progress("Preparing the update…")
        let unpacked = staging.appendingPathComponent("unpacked")
        let ditto = await Sidecar.runProcess(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-xk", zip.path, unpacked.path]
        )
        guard ditto.ok else { throw SidecarError.failed("The update could not be unpacked.") }
        let newApp = unpacked.appendingPathComponent("MotionGraphics.app")
        guard fm.fileExists(atPath: newApp.path) else {
            throw SidecarError.failed("The update did not contain the app.")
        }

        progress("Checking the update's signature…")
        try await verify(newApp)
        // The zip arrived quarantined; drop the flag so the verified app
        // opens without a Gatekeeper prompt after the swap.
        _ = await Sidecar.runProcess(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", newApp.path]
        )

        progress("Installing…")
        try await replaceCurrentApp(with: newApp)
        progress("Restarting…")
        await MainActor.run { Relocator.relaunch(at: Bundle.main.bundleURL) }
    }

    // The update must carry a valid signature from the same team as the
    // running app; anything else is not ours.
    private static func verify(_ newApp: URL) async throws {
        let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
        let check = await Sidecar.runProcess(codesign, arguments: ["--verify", "--strict", newApp.path])
        guard check.ok else { throw SidecarError.failed("The downloaded update failed its signature check.") }

        let newTeam = await teamIdentifier(of: newApp)
        let myTeam = await teamIdentifier(of: Bundle.main.bundleURL)
        guard let newTeam, newTeam == myTeam else {
            throw SidecarError.failed("The downloaded update is signed by a different developer.")
        }
    }

    private static func teamIdentifier(of bundle: URL) async -> String? {
        let result = await Sidecar.runProcess(
            URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["-dvv", bundle.path]
        )
        for line in result.stderr.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let team = String(line.dropFirst("TeamIdentifier=".count))
            return team == "not set" ? nil : team
        }
        return nil
    }

    // Moves the running bundle aside and the new one into its place; the
    // open inodes keep the current process healthy until relaunch. Falls
    // back to an admin-authorized copy when the folder is not writable.
    private static func replaceCurrentApp(with newApp: URL) async throws {
        let current = Bundle.main.bundleURL
        let fm = FileManager.default
        let retired = fm.temporaryDirectory.appendingPathComponent("MotionGraphics-old-\(UUID().uuidString).app")
        do {
            try fm.moveItem(at: current, to: retired)
            do {
                try fm.moveItem(at: newApp, to: current)
            } catch {
                // Put the old app back rather than leave nothing installed.
                try? fm.moveItem(at: retired, to: current)
                throw error
            }
            try? fm.removeItem(at: retired)
        } catch {
            let script = """
            do shell script "/bin/rm -rf '\(current.path)' && /usr/bin/ditto '\(newApp.path)' '\(current.path)'" with administrator privileges
            """
            let ok = await MainActor.run { Relocator.runAppleScript(script) }
            guard ok else {
                throw SidecarError.failed("The update could not be installed. You can download it yourself from github.com/\(repo)/releases.")
            }
        }
    }

    // MARK: - Download

    private static func download(from url: URL, to destination: URL, onPercent: @escaping @Sendable (Int) -> Void) async throws {
        let delegate = DownloadDelegate(destination: destination, onPercent: onPercent)
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.downloadTask(with: url).resume()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let destination: URL
        let onPercent: @Sendable (Int) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        var session: URLSession?
        private var lastPercent = -1

        init(destination: URL, onPercent: @escaping @Sendable (Int) -> Void) {
            self.destination = destination
            self.onPercent = onPercent
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let percent = Int(totalBytesWritten * 100 / totalBytesExpectedToWrite)
            if percent != lastPercent {
                lastPercent = percent
                onPercent(percent)
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                finish(with: nil)
            } catch {
                finish(with: error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(with: error) }
        }

        private func finish(with error: Error?) {
            if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume(returning: ())
            }
            continuation = nil
            session?.finishTasksAndInvalidate()
            session = nil
        }
    }
}
