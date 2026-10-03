import Foundation
import Darwin

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }
}

enum ProcessRunner {
    static func run(
        executablePath: String,
        arguments: [String],
        environmentOverrides: [String: String] = [:],
        standardInput: String? = nil,
        timeout: TimeInterval = 10,
        cancellation: ProcessCancellation? = nil
    ) -> ProcessResult {
        guard cancellation?.isCancelled != true else {
            return ProcessResult(status: -999, stdout: "", stderr: "", timedOut: false)
        }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let inputPipe = standardInput == nil ? nil : Pipe()
        if let inputPipe {
            process.standardInput = inputPipe
            // A child may reject input and exit early. Do not let EPIPE kill the app.
            _ = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        process.environment = environment

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        if let inputPipe, let standardInput {
            try? inputPipe.fileHandleForReading.close()
            try? inputPipe.fileHandleForWriting.write(contentsOf: Data(standardInput.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }

        // Drain both pipes while the child is running: a full pipe must not block
        // process exit. These bounded diagnostic commands do not produce media.
        let readers = DispatchGroup()
        let output = CapturedData()
        let errors = CapturedData()
        for (pipe, capture) in [(outputPipe, output), (errorPipe, errors)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                capture.store(pipe.fileHandleForReading.readDataToEndOfFile())
                readers.leave()
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline && cancellation?.isCancelled != true {
            Thread.sleep(forTimeInterval: 0.05)
        }

        var timedOut = false
        if process.isRunning {
            timedOut = cancellation?.isCancelled != true
            process.terminate()
            let graceDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()

        _ = readers.wait(timeout: .now() + 2)
        let stdout = String(decoding: output.read(), as: UTF8.self)
        let stderr = String(decoding: errors.read(), as: UTF8.self)
        return ProcessResult(status: cancellation?.isCancelled == true ? -999 : process.terminationStatus,
                             stdout: stdout, stderr: stderr, timedOut: timedOut)
    }
}

private final class CapturedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        defer { lock.unlock() }
        data = value
    }

    func read() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
