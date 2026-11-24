import Darwin
import Foundation

/// A foreground ADB server owned by this app, with a private Unix socket.
/// Fresh helpers retain the current responsible app's network identity. A
/// random USB selector keeps this server from claiming connected USB phones.
final class WirelessDebugBackend: @unchecked Sendable {
    private let lock = NSLock()
    private let paths: ToolPaths?
    private let directory: URL
    let socket: String
    private let usbSelector = "MirrorLink-Wireless-" + UUID().uuidString
    private var process: Process?
    private var stopped = false

    init(paths: ToolPaths?) {
        self.paths = paths
        // Darwin Unix socket paths have a small fixed length. Keep the private
        // runtime directory short, outside source/output folders, mode 0700.
        directory = URL(fileURLWithPath: "/tmp/ml-adb-" + UUID().uuidString, isDirectory: true)
        socket = "localfilesystem:" + directory.appendingPathComponent("s").path
    }

    var activeSocket: String? {
        lock.lock(); defer { lock.unlock() }
        return !stopped && process?.isRunning == true ? socket : nil
    }

    func prepare() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, let paths else { return false }
        if process?.isRunning == true {
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent("s").path)
        }
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            let child = Process()
            child.executableURL = paths.adb
            child.arguments = ["-L", socket, "--one-device", usbSelector, "server", "nodaemon"]
            var environment = ProcessInfo.processInfo.environment
            for key in ["ADB_SERVER_SOCKET", "ANDROID_SERIAL", "ADB_TRACE", "ADB_VENDOR_KEYS"] {
                environment.removeValue(forKey: key)
            }
            environment["ADB_MDNS"] = "0"
            environment["ADB_MDNS_AUTO_CONNECT"] = "0"
            environment["ADB_LOCAL_TRANSPORT_MAX_PORT"] = "0"
            child.environment = environment
            child.standardInput = FileHandle.nullDevice
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            process = child
            let deadline = Date().addingTimeInterval(3)
            while child.isRunning, Date() < deadline {
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("s").path) { return true }
                Thread.sleep(forTimeInterval: 0.02)
            }
        } catch { /* Report startup failure after cleaning only our runtime. */ }
        stopChild()
        try? FileManager.default.removeItem(at: directory)
        return false
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        stopChild()
        try? FileManager.default.removeItem(at: directory)
    }

    /// The caller holds the lock. A failed startup must not leave a live child
    /// which a later prepare() could mistake for a ready server.
    private func stopChild() {
        if let child = process, child.isRunning {
            child.terminate()
            let deadline = Date().addingTimeInterval(1)
            while child.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() }
        }
        process = nil
    }
}
