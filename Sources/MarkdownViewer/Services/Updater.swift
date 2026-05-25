import AppKit
import Foundation

/// Silent, frictionless self-updater for Developer ID / notarized builds shipped
/// via GitHub Releases (`build-<hash>` tags).
///
/// Design rationale — see `docs/research/macos-self-update-patterns/`:
/// a running app must NEVER swap its own bundle on a termination/window-close
/// trigger. That races (the swap dispatch loses to app teardown) and is what
/// previously left updates downloaded-but-never-installed. Instead we split the
/// two phases across launches and hand the swap to an independent process:
///
///   1. STAGE on launch (background): if a newer release exists, download + verify
///      it into a persistent staging dir and record a pointer in UserDefaults.
///   2. APPLY on the next launch: if a verified staged build is pending, spawn a
///      DETACHED helper that waits for THIS process to exit, then atomically swaps
///      the bundle and relaunches. The helper is orphaned to launchd and outlives
///      the app, so the swap happens deterministically whenever the user quits —
///      no notification race, no forced relaunch.
///
/// The updater is an RCE channel, so a staged bundle is installed only after its
/// code signature verifies AND its Team ID matches the running app.
final class Updater {
    static let shared = Updater()

    private static let pendingPathKey = "pendingUpdateAppPath"
    private static let pendingVersionKey = "pendingUpdateVersion"

    func start() {
        guard BuildInfo.commitHash != "dev" else { return }
        Task.detached(priority: .background) {
            Self.applyPendingUpdate()   // install what a previous session staged
            Self.checkAndStage()        // stage the newest release for next launch
        }
    }

    // MARK: - Apply staged update (arm detached swap helper)

    private static func applyPendingUpdate() {
        let defaults = UserDefaults.standard
        guard let stagedApp = defaults.string(forKey: pendingPathKey),
              let stagedVersion = defaults.string(forKey: pendingVersionKey) else { return }

        // Clear the pointer up front so a stale/bad staged build can never wedge
        // launch; if the swap is missed (e.g. reboot before quit), checkAndStage
        // simply re-stages on a later launch.
        defaults.removeObject(forKey: pendingPathKey)
        defaults.removeObject(forKey: pendingVersionKey)

        guard stagedVersion != BuildInfo.commitHash else { return }
        guard FileManager.default.fileExists(atPath: stagedApp) else { return }
        guard verifyBundle(stagedApp) else {
            try? FileManager.default.removeItem(atPath: (stagedApp as NSString).deletingLastPathComponent)
            return
        }
        armSwapHelper(newApp: stagedApp)
    }

    // MARK: - Check + download + stage

    private static func checkAndStage() {
        guard let gh = findGh() else { return }
        guard let latest = runGhLatestTag(ghPath: gh) else { return }
        let prefix = "build-"
        guard latest.hasPrefix(prefix) else { return }
        let latestHash = String(latest.dropFirst(prefix.count))
        guard latestHash != BuildInfo.commitHash else { return }

        guard let stagedApp = downloadAndUnzip(ghPath: gh, tag: latest) else { return }
        guard verifyBundle(stagedApp) else {
            try? FileManager.default.removeItem(atPath: stagingDir(for: latest))
            return
        }
        UserDefaults.standard.set(stagedApp, forKey: pendingPathKey)
        UserDefaults.standard.set(latestHash, forKey: pendingVersionKey)
    }

    // MARK: - Detached swap helper

    /// Spawns a bash helper that outlives this process (orphaned to launchd), waits
    /// for our PID to exit, then swaps the bundle and relaunches. The swap moves the
    /// old bundle aside first and only `rm`s it after the new one is in place, so
    /// the install location is never left empty on failure (rollback on error).
    private static func armSwapHelper(newApp: String) {
        let currentApp = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        OLD="\(currentApp).old-$$"
        rm -rf "$OLD"
        mv "\(currentApp)" "$OLD" || exit 1
        if ! mv "\(newApp)" "\(currentApp)"; then
            mv "$OLD" "\(currentApp)"
            exit 1
        fi
        rm -rf "$OLD"
        xattr -dr com.apple.quarantine "\(currentApp)" 2>/dev/null || true
        open "\(currentApp)"
        """
        let scriptPath = "/tmp/mdlens-update-swap.sh"
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [scriptPath]
        task.standardOutput = nil
        task.standardError = nil
        try? task.run()
    }

    // MARK: - Verification

    /// Reject a staged bundle whose signature is invalid or whose Team ID differs
    /// from the running app — never install an unverified or foreign-signed build.
    private static func verifyBundle(_ path: String) -> Bool {
        guard runProcess("/usr/bin/codesign", ["--verify", "--strict", path]) != nil else { return false }
        guard let staged = teamIdentifier(ofBundleAt: path), !staged.isEmpty else { return false }
        guard let current = teamIdentifier(ofBundleAt: Bundle.main.bundlePath) else { return false }
        return staged == current
    }

    private static func teamIdentifier(ofBundleAt path: String) -> String? {
        // `codesign -d` writes its fields to STDERR.
        guard let out = runProcessCapturingStderr("/usr/bin/codesign", ["-d", "--verbose=2", path]) else { return nil }
        for line in out.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return value == "not set" ? nil : value
        }
        return nil
    }

    // MARK: - gh helpers

    private static func findGh() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func runGhLatestTag(ghPath: String) -> String? {
        let out = runProcess(ghPath, [
            "release", "view", "--repo", BuildInfo.repo,
            "--json", "tagName", "-q", ".tagName"
        ])
        return out?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    /// Persistent per-tag staging dir in Application Support (survives reboot,
    /// unlike /tmp, so a staged build isn't lost between download and next launch).
    private static func stagingDir(for tag: String) -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mdLens/updates", isDirectory: true)
        return base.appendingPathComponent(tag, isDirectory: true).path
    }

    private static func downloadAndUnzip(ghPath: String, tag: String) -> String? {
        let stageDir = stagingDir(for: tag)
        try? FileManager.default.removeItem(atPath: stageDir)
        try? FileManager.default.createDirectory(atPath: stageDir, withIntermediateDirectories: true)

        guard runProcess(ghPath, [
            "release", "download", tag,
            "--repo", BuildInfo.repo,
            "--pattern", "*.zip",
            "--dir", stageDir
        ]) != nil else { return nil }

        guard let zip = (try? FileManager.default.contentsOfDirectory(atPath: stageDir))?
                .first(where: { $0.hasSuffix(".zip") })
        else { return nil }

        let zipPath = "\(stageDir)/\(zip)"
        guard runProcess("/usr/bin/unzip", ["-q", "-o", zipPath, "-d", stageDir]) != nil else { return nil }

        let appPath = (try? FileManager.default.contentsOfDirectory(atPath: stageDir))?
            .first(where: { $0.hasSuffix(".app") })
            .map { "\(stageDir)/\($0)" }
        return appPath
    }

    // MARK: - Process helpers

    @discardableResult
    private static func runProcess(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    /// Like `runProcess` but returns STDERR — `codesign -d` writes there. Reads the
    /// pipe before waiting on exit to avoid a full-buffer deadlock.
    private static func runProcessCapturingStderr(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        let errPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errPipe
        do { try task.run() } catch { return nil }
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
