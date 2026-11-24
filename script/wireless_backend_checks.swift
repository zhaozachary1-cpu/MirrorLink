import Foundation

@main
enum WirelessBackendChecks {
    static func main() throws {
        var count = 0
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw NSError(domain: message, code: 1) }
            count += 1
            print("PASS: \(message)")
        }
        let adb = URL(fileURLWithPath: CommandLine.arguments[1])
        let paths = ToolPaths(root: adb.deletingLastPathComponent(), adb: adb, scrcpy: adb, server: adb)
        let backend = WirelessDebugBackend(paths: paths)
        defer { backend.stop() }
        let socketPath = String(backend.socket.dropFirst("localfilesystem:".count))
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try check(backend.activeSocket == nil, "constructing a backend starts no server")
        try check(backend.prepare(), "official ADB starts as an owned foreground server on a private Unix socket")
        try check(backend.activeSocket == backend.socket, "only a live owned server is offered to device refresh")
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
        try check((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700, "private socket directory excludes other users")
        func run(_ args: [String]) -> ProcessResult {
            ProcessRunner.run(executablePath: adb.path, arguments: args,
                environmentOverrides: ["ADB_SERVER_SOCKET": backend.socket], timeout: 4)
        }
        let status = run(["server-status"])
        try check(status.succeeded && status.stdout.contains("MDNS_DISABLED"), "owned server keeps the crashing mDNS driver disabled")
        try check(run(["devices", "-l"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "List of devices attached",
                  "wireless-only server does not claim attached USB phones or emulators")
        try check(backend.prepare() && run(["server-status"]).stdout == status.stdout,
                  "repeated preparation reuses the existing owned process")
        let other = WirelessDebugBackend(paths: paths)
        defer { other.stop() }
        try check(other.socket != backend.socket && other.prepare(), "separate app runtimes cannot share or steal a socket")
        backend.stop()
        try check(backend.activeSocket == nil && !backend.prepare(), "shutdown permanently prevents background resurrection")
        try check(!FileManager.default.fileExists(atPath: directory.path), "shutdown removes only its own private runtime directory")
        try check(other.activeSocket != nil, "stopping one owned backend preserves the other")
        let unavailable = WirelessDebugBackend(paths: nil)
        try check(!unavailable.prepare() && unavailable.activeSocket == nil, "missing tools never start a backend")
        let missingADB = directory.appendingPathComponent("not-an-executable")
        let invalidPaths = ToolPaths(root: directory, adb: missingADB, scrcpy: missingADB, server: missingADB)
        let invalid = WirelessDebugBackend(paths: invalidPaths)
        defer { invalid.stop() }
        let failedDirectory = URL(fileURLWithPath: String(invalid.socket.dropFirst("localfilesystem:".count))).deletingLastPathComponent()
        try check(!invalid.prepare() && invalid.activeSocket == nil && !FileManager.default.fileExists(atPath: failedDirectory.path),
                  "failed startup removes its private directory and publishes no server")
        print("PASS: \(count) real local ADB backend checks (no phone connection or QR pairing)")
    }
}
