import AppKit
import Foundation

@MainActor
final class Updater {
    static let shared = Updater()

    private var pendingAppPath: String?
    private var observer: NSObjectProtocol?

    func start() {
        guard BuildInfo.commitHash != "dev" else { return }
        Task.detached(priority: .background) { [weak self] in
            await self?.checkAndStage()
        }
    }

    // MARK: - Check + download

    private func checkAndStage() async {
        guard let gh = Self.findGh() else { return }
        guard let latest = Self.runGhLatestTag(ghPath: gh) else { return }
        let prefix = "build-"
        guard latest.hasPrefix(prefix) else { return }
        let latestHash = String(latest.dropFirst(prefix.count))
        guard latestHash != BuildInfo.commitHash else { return }

        let stagedApp = Self.downloadAndUnzip(ghPath: gh, tag: latest)
        guard let stagedApp else { return }

        await MainActor.run {
            self.pendingAppPath = stagedApp
            self.armSwapOnIdle()
        }
    }

    // MARK: - Swap when frictionless

    private func armSwapOnIdle() {
        if hasVisibleWindows() == false {
            performSwapAndRelaunch()
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.hasVisibleWindows() == false {
                    self.performSwapAndRelaunch()
                }
            }
        }
    }

    private func hasVisibleWindows() -> Bool {
        NSApp.windows.contains { $0.isVisible && $0.className != "NSStatusBarWindow" && $0.level == .normal }
    }

    private func performSwapAndRelaunch() {
        guard let newApp = pendingAppPath else { return }
        pendingAppPath = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil

        let currentApp = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        set -e
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        rm -rf "\(currentApp)"
        mv "\(newApp)" "\(currentApp)"
        xattr -dr com.apple.quarantine "\(currentApp)" 2>/dev/null || true
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

        NSApp.terminate(nil)
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

    private static func downloadAndUnzip(ghPath: String, tag: String) -> String? {
        let stageDir = "/tmp/mdlens-update-\(tag)"
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
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
