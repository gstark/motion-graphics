import AppKit
import Foundation

// On first launch from Downloads (or a mounted image / Gatekeeper's
// translocated path), offer to move the app into /Applications and relaunch
// from there, then offer to bin the downloaded zip. Modeled on the common
// "LetsMove" behavior, kept small.
enum Relocator {
    private static let declinedKey = "MotionGraphics.declinedMoveToApplications"

    static func offerIfNeeded() {
        guard shouldOffer() else { return }

        let alert = NSAlert()
        alert.messageText = "Move to the Applications folder?"
        alert.informativeText = "MotionGraphics is running from your Downloads. Moving it to Applications keeps it in the right place and lets it update cleanly."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }

        guard let moved = move() else {
            let fail = NSAlert()
            fail.messageText = "Could not move the app"
            fail.informativeText = "You can drag MotionGraphics into your Applications folder yourself."
            fail.runModal()
            return
        }

        offerToRemoveZip()
        relaunch(at: moved)
    }

    // MARK: - Checks

    private static func shouldOffer() -> Bool {
        if UserDefaults.standard.bool(forKey: declinedKey) { return false }
        let path = Bundle.main.bundlePath
        if path.hasPrefix("/Applications/") { return false }

        let downloads = NSHomeDirectory() + "/Downloads/"
        let translocated = path.contains("/AppTranslocation/")
        return translocated || path.hasPrefix(downloads) || path.hasPrefix("/Volumes/")
    }

    // MARK: - Move

    // Copies the running bundle into /Applications, using an authorized copy
    // when the folder is not directly writable. Returns the destination.
    private static func move() -> URL? {
        let src = Bundle.main.bundleURL
        let dst = URL(fileURLWithPath: "/Applications").appendingPathComponent(src.lastPathComponent)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
            return dst
        } catch {
            // Fall back to an admin-authorized copy for a locked /Applications.
            let script = """
            do shell script "/bin/rm -rf '\(dst.path)' && /usr/bin/ditto '\(src.path)' '\(dst.path)'" with administrator privileges
            """
            if runAppleScript(script) { return dst }
            return nil
        }
    }

    private static func offerToRemoveZip() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let zip = downloads.appendingPathComponent("MotionGraphics.zip")
        guard FileManager.default.fileExists(atPath: zip.path) else { return }

        let alert = NSAlert()
        alert.messageText = "Remove the download?"
        alert.informativeText = "Move MotionGraphics.zip to the Trash. You no longer need it."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.trashItem(at: zip, resultingItemURL: nil)
    }

    private static func relaunch(at dst: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dst, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}
