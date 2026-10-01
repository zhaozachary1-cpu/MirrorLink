import Foundation

struct ToolPaths: Sendable {
    let root: URL
    let adb: URL
    let scrcpy: URL
    let server: URL

    var isUsable: Bool {
        FileManager.default.isExecutableFile(atPath: adb.path)
            && FileManager.default.isExecutableFile(atPath: scrcpy.path)
            && FileManager.default.fileExists(atPath: server.path)
    }

    static func discover(bundleURL: URL = Bundle.main.bundleURL) -> ToolPaths? {
        // Distributed apps only execute their sealed bundled tools, never binaries
        // found in the current directory or inherited shell configuration.
        let root = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let paths = ToolPaths(
            root: root,
            adb: root.appendingPathComponent("adb"),
            scrcpy: root.appendingPathComponent("scrcpy"),
            server: bundleURL.appendingPathComponent("Contents/Resources/scrcpy-server")
        )
        return paths.isUsable ? paths : nil
    }
}
