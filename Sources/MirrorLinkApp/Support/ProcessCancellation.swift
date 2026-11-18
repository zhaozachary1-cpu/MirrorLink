import Foundation
import Darwin

/// Cancels only a command spawned for this operation, never the ADB daemon.
final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var ownedProcesses: [ObjectIdentifier: Process] = [:]

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        for process in ownedProcesses.values where process.isRunning { process.terminate() }
    }

    /// Only callers that launched this exact Process may register it. The
    /// wireless runner keeps its existing flag-based cancellation semantics.
    func registerOwnedProcess(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        ownedProcesses[ObjectIdentifier(process)] = process
        // Cancellation may have happened between the runner's preflight check
        // and Process.run(). Do not let that newly launched child escape it.
        if cancelled && process.isRunning { process.terminate() }
    }

    func unregisterOwnedProcess(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        ownedProcesses[ObjectIdentifier(process)] = nil
    }

    /// Shutdown fallback only: never signal an unregistered PID, process group,
    /// shared ADB daemon, or process owned by another cancellation token.
    func forceTerminateOwnedProcesses() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        for process in ownedProcesses.values where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
