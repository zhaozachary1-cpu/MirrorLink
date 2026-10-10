// Test-only child executable. No ADB, USB, media capture or network access.
import Foundation
import Darwin

guard let serialIndex = CommandLine.arguments.firstIndex(of: "-s"),
      CommandLine.arguments.indices.contains(serialIndex + 1) else { exit(64) }
let serial = CommandLine.arguments[serialIndex + 1]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let mode = (try? String(contentsOf: root.appendingPathComponent("\(serial).mode"), encoding: .utf8)) ?? "ready"
let logURL = root.appendingPathComponent("\(serial).launches")
let record: [String: Any] = [
    "pid": getpid(), "serial": serial, "arguments": CommandLine.arguments,
    "socket": ProcessInfo.processInfo.environment["ADB_SERVER_SOCKET"] ?? "",
    "androidSerial": ProcessInfo.processInfo.environment["ANDROID_SERIAL"] ?? "",
    "adb": ProcessInfo.processInfo.environment["ADB"] ?? "",
    "server": ProcessInfo.processInfo.environment["SCRCPY_SERVER_PATH"] ?? ""
]
if !FileManager.default.fileExists(atPath: logURL.path) {
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
}
let log = try FileHandle(forWritingTo: logURL)
log.seekToEndOfFile()
log.write(try JSONSerialization.data(withJSONObject: record) + Data([10]))
try log.close()

func emitReady() {
    // Match scrcpy's fprintf(stdout, ...): line-buffered on a terminal, but
    // block-buffered on a pipe. Do not fflush; that would hide the regression.
    fputs("INFO: Texture: 1080x2400\n", stdout)
}
if mode == "ignore-term" { signal(SIGTERM, SIG_IGN) }
if mode == "fail" {
    let message = Data("模拟错误：授权失败\n最后一条无换行诊断".utf8)
    FileHandle.standardError.write(message.prefix(5))
    usleep(10_000)
    FileHandle.standardError.write(message.dropFirst(5))
    exit(23)
}
if mode == "inherited-logs" {
    // Simulate a short-lived descendant retaining both output descriptors.
    // Session cleanup must not wait for that unrelated lifetime indefinitely.
    let descendant = Process()
    descendant.executableURL = URL(fileURLWithPath: "/bin/sleep")
    descendant.arguments = ["2"]
    descendant.standardOutput = FileHandle.standardOutput
    descendant.standardError = FileHandle.standardError
    try descendant.run()
    fputs("final buffered stdout\n", stdout)
    fputs("final stderr\n", stderr)
    exit(23)
}
if mode == "malformed-texture" {
    fputs("ERROR: Texture: 1080x2400\nINFO: Texture: 0x2400\nINFO: Texture: 1080x2400 invalid\n", stdout)
} else if mode != "silent" { emitReady() }

// The bounded lifetime also prevents orphaned fixtures after an interrupted test.
let deadline = Date().addingTimeInterval(40)
var emittedOnCommand = false
var previousCommand: String?
while Date() < deadline {
    let command = try? String(contentsOf: root.appendingPathComponent("\(serial).command"), encoding: .utf8)
    if command == "exit" { exit(0) }
    if command == "fail" { exit(17) }
    if command == "disconnect" { exit(2) }
    if command == "ready" && !emittedOnCommand {
        emitReady()
        emittedOnCommand = true
    }
    if let command, command != previousCommand, command.hasPrefix("log:") {
        // A complete or deliberately chunked fake scrcpy log, emitted only
        // once per command change. No media capture or ADB access occurs.
        fputs(String(command.dropFirst(4)) + "\n", stdout)
    }
    if let command, command != previousCommand, command.hasPrefix("split-log:") {
        let bytes = Data((String(command.dropFirst(10)) + "\n").utf8)
        let split = min(8, bytes.count)
        FileHandle.standardOutput.write(bytes.prefix(split))
        usleep(10_000)
        FileHandle.standardOutput.write(bytes.dropFirst(split))
    }
    previousCommand = command
    usleep(20_000)
}
exit(99)
