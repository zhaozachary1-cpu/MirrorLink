import Foundation
import Darwin

struct BinaryProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
    let timedOut: Bool
    let outputLimitExceeded: Bool
    var succeeded: Bool { status == 0 && !timedOut && !outputLimitExceeded }
}

/// Drains both pipes without decoding binary stdout or retaining unbounded output.
/// Cancellation terminates only this command, never the shared ADB daemon.
enum BoundedProcessRunner {
    static func run(executable: URL, arguments: [String], environment: [String: String] = [:],
                    timeout: TimeInterval, outputLimit: Int = 262_144,
                    cancellation: ProcessCancellation? = nil) -> BinaryProcessResult {
        if cancellation?.isCancelled == true { return result(-999) }
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        var childEnvironment = ProcessInfo.processInfo.environment
        // Explicit route wins over inherited port/address and serial settings.
        for key in ["ANDROID_SERIAL", "ANDROID_ADB_SERVER_PORT", "ANDROID_ADB_SERVER_ADDRESS", "ADB_SERVER_SOCKET"] {
            childEnvironment.removeValue(forKey: key)
        }
        childEnvironment.merge(environment) { _, new in new }
        process.environment = childEnvironment
        do { try process.run() } catch { return result(-1) }
        cancellation?.registerOwnedProcess(process)
        defer { cancellation?.unregisterOwnedProcess(process) }
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        let handles = [output.fileHandleForReading, errors.fileHandleForReading]
        for handle in handles {
            let fd = handle.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }
        defer { for handle in handles { try? handle.close() } }
        var buffers = [Data(), Data()], closed = [false, false]
        var overflow = false, timedOut = false
        let deadline = Date().addingTimeInterval(timeout)
        var stoppedAt: Date?
        var terminated = false
        var bytes = [UInt8](repeating: 0, count: 65_536)
        while true {
            for index in handles.indices where !closed[index] {
                while true {
                    let count = Darwin.read(handles[index].fileDescriptor, &bytes, bytes.count)
                    if count > 0 {
                        let limit = index == 0 ? outputLimit : 65_536
                        let available = max(0, limit - buffers[index].count)
                        buffers[index].append(contentsOf: bytes.prefix(min(count, available)))
                        if count > available { overflow = true; break }
                    } else if count == 0 { closed[index] = true; break }
                    else if errno == EINTR { continue }
                    else { break }
                }
            }
            let cancelled = cancellation?.isCancelled == true
            if !terminated && process.isRunning && (cancelled || overflow || Date() >= deadline) {
                timedOut = !cancelled && !overflow
                process.terminate()
                terminated = true
                stoppedAt = Date()
            }
            if terminated && process.isRunning, let stoppedAt, Date().timeIntervalSince(stoppedAt) >= 0.5 {
                kill(process.processIdentifier, SIGKILL)
            }
            if !process.isRunning {
                if stoppedAt == nil { stoppedAt = Date() }
                if closed.allSatisfy({ $0 }) || Date().timeIntervalSince(stoppedAt!) > 0.5 { break }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        return BinaryProcessResult(status: cancellation?.isCancelled == true ? -999 : process.terminationStatus,
                                   stdout: buffers[0], stderr: buffers[1], timedOut: timedOut,
                                   outputLimitExceeded: overflow)
    }

    private static func result(_ status: Int32) -> BinaryProcessResult {
        BinaryProcessResult(status: status, stdout: Data(), stderr: Data(), timedOut: false, outputLimitExceeded: false)
    }
}
