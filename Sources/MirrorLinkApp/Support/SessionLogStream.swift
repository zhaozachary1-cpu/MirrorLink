import Darwin
import Foundation

/// scrcpy uses C stdio, which buffers stdout when it is a pipe. A private PTY
/// gives us line-buffered logs without changing the bundled executable, its
/// stdin, or the user's terminal. stderr can remain an ordinary pipe.
final class SessionLogStream: @unchecked Sendable {
    let childWriter: FileHandle
    private let reader: FileHandle
    private let lock = NSLock()
    private var exitedAt: UInt64?

    init(lineBuffered: Bool) throws {
        var descriptors: [Int32] = [-1, -1]
        let result: Int32
        if lineBuffered {
            var master: Int32 = -1
            var slave: Int32 = -1
            result = openpty(&master, &slave, nil, nil, nil)
            descriptors = [master, slave]
        } else {
            result = pipe(&descriptors)
        }
        guard result == 0 else { throw Self.posixError() }

        do {
            // Other concurrent sessions and ADB must not inherit our parent
            // descriptors and keep a finished session's log reader alive.
            for descriptor in descriptors {
                guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) != -1 else { throw Self.posixError() }
            }
            guard fcntl(descriptors[0], F_SETFL, O_NONBLOCK) != -1 else { throw Self.posixError() }
            if lineBuffered {
                var settings = termios()
                guard tcgetattr(descriptors[1], &settings) == 0 else { throw Self.posixError() }
                cfmakeraw(&settings) // Preserve UTF-8/newlines exactly; no terminal echo.
                guard tcsetattr(descriptors[1], TCSANOW, &settings) == 0 else { throw Self.posixError() }
            }
        } catch {
            descriptors.forEach { Darwin.close($0) }
            throw error
        }
        reader = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true)
        childWriter = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
    }

    /// Process duplicates this handle into the child; close the parent's copy
    /// after run() (including failure) so EOF is observable.
    func closeParentWriter() {
        try? childWriter.close()
    }

    func processDidExit() {
        lock.lock()
        exitedAt = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
    }

    private var drainExpired: Bool {
        lock.lock()
        let exitedAt = exitedAt
        lock.unlock()
        guard let exitedAt else { return false }
        // Drain final diagnostics, but don't wait forever for a descendant
        // that accidentally inherited stdout/stderr after scrcpy has exited.
        return DispatchTime.now().uptimeNanoseconds - exitedAt >= 500_000_000
    }

    /// Run on a worker queue. POSIX read handles PTY EOF (EIO on some systems)
    /// without FileHandle.availableData's possible Objective-C exception.
    func readChunks(_ receive: (Data) -> Void) {
        defer { try? reader.close() }
        var bytes = [UInt8](repeating: 0, count: 8192)
        while !drainExpired {
            var descriptor = pollfd(fd: reader.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, 100)
            if result == -1 {
                if errno == EINTR { continue }
                break
            }
            if result == 0 { continue }
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(reader.fileDescriptor, buffer.baseAddress, buffer.count)
            }
            if count > 0 {
                receive(Data(bytes.prefix(count)))
            } else if count == 0 {
                break
            } else if errno != EINTR && errno != EAGAIN {
                break
            }
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
