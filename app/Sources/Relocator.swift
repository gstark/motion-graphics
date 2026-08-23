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

        removeOriginal()
        offerToRemoveZip()
        relaunch(at: moved)
    }

    // MARK: - Checks

    private static func shouldOffer() -> Bool {
        if UserDefaults.standard.bool(forKey: declinedKey) { return false }
        if originalBundleURL().path.hasPrefix("/Applications/") { return false }

        let path = originalBundleURL().path
        let downloads = NSHomeDirectory() + "/Downloads/"
        return path.hasPrefix(downloads) || path.hasPrefix("/Volumes/")
    }

    // Gatekeeper runs a quarantined app from a read-only mount under
    // /private/var/folders/.../AppTranslocation/. Ask the Security framework
    // where the bundle really lives, so the checks and the cleanup below act
    // on the real copy. SecTranslocate is C-only, so look the symbols up at
    // run time.
    private typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<ObjCBool>, UnsafeMutableRawPointer?) -> Bool
    private typealias OriginalPath = @convention(c) (CFURL, UnsafeMutableRawPointer?) -> Unmanaged<CFURL>?

    private static func originalBundleURL() -> URL {
        let url = Bundle.main.bundleURL
        guard url.path.contains("/AppTranslocation/") else { return url }

        guard let isSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecTranslocateIsTranslocatedURL"),
              let pathSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecTranslocateCreateOriginalPathForURL")
        else { return url }

        var translocated = ObjCBool(false)
        let isTranslocated = unsafeBitCast(isSym, to: IsTranslocated.self)
        guard isTranslocated(url as CFURL, &translocated, nil), translocated.boolValue else { return url }

        let originalPath = unsafeBitCast(pathSym, to: OriginalPath.self)
        guard let original = originalPath(url as CFURL, nil) else { return url }
        return original.takeRetainedValue() as URL
    }

    // MARK: - Move

    // Copies the running bundle into /Applications, using an authorized copy
    // when the folder is not directly writable. Returns the destination.
    private static func move() -> URL? {
        let src = Bundle.main.bundleURL
        let dst = URL(fileURLWithPath: "/Applications").appendingPathComponent(originalBundleURL().lastPathComponent)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
        } catch {
            // Fall back to an admin-authorized copy for a locked /Applications.
            let script = """
            do shell script "/bin/rm -rf '\(dst.path)' && /usr/bin/ditto '\(src.path)' '\(dst.path)'" with administrator privileges
            """
            guard runAppleScript(script), fm.fileExists(atPath: dst.path) else { return nil }
        }

        clearQuarantine(at: dst)
        return dst
    }

    // A bundle that keeps com.apple.quarantine is translocated again on the
    // next launch, so the app would run from a random read-only path and ask
    // to move itself once more. Strip the flag from the copy we just made.
    private static func clearQuarantine(at url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-d", "-r", "com.apple.quarantine", url.path]
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    // Bin the copy we moved from, so the next launch cannot start it again.
    private static func removeOriginal() {
        let original = originalBundleURL()
        guard !original.path.hasPrefix("/Applications/"), !original.path.hasPrefix("/Volumes/") else { return }
        try? FileManager.default.trashItem(at: original, resultingItemURL: nil)
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

    // Also used by Updater after swapping the bundle.
    static func relaunch(at dst: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dst, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}
