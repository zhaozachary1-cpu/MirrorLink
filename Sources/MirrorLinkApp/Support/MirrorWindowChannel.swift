import Foundation
import Darwin

enum MirrorWindowAction: String, Codable {
    case ready, home, drawer, swipe, screenshot, recordStart, recordStop, sendFile, installAPK, cancel
}

struct MirrorWindowRequest: Decodable {
    let action: MirrorWindowAction
    let path: String?
}

/// One private, inherited socket pair per owned scrcpy process. No TCP port,
/// filesystem socket, device identifier, or command line credential is needed.
/// Datagrams are bounded and atomic; a blocked child cannot block the UI.
@MainActor
final class MirrorWindowChannel {
    let input: FileHandle
    private let descriptor: Int32
    private var source: DispatchSourceRead?
    private var closed = false
    private var lastState: Data?
    var onRequest: ((MirrorWindowRequest) -> Void)?

    init() throws {
        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &pair) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        descriptor = pair[0]
        input = FileHandle(fileDescriptor: pair[1], closeOnDealloc: true)
        for fd in pair {
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            var yes: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            // Darwin's default Unix datagram send buffer is only 2 KB. A
            // bilingual state plus saved media paths legitimately exceeds it.
            var capacity: Int32 = 65_536
            guard setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &capacity, socklen_t(MemoryLayout<Int32>.size)) == 0,
                  setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &capacity, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                let failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                Darwin.close(pair[0]); try? input.close()
                throw failure
            }
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        self.source = source
        source.setEventHandler { [weak self] in self?.receive() }
        let fd = descriptor
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    func childDidLaunch() { try? input.close() }

    func sendState(_ value: [String: Any], force: Bool = false) {
        guard !closed, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              data.count < 8192, force || data != lastState else { return }
        let sent = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, MSG_DONTWAIT) }
        if sent == data.count { lastState = data }
    }

    private func receive() {
        guard !closed else { return }
        var bytes = [UInt8](repeating: 0, count: 8192)
        while !closed {
            let count = recv(descriptor, &bytes, bytes.count, MSG_DONTWAIT)
            guard count > 0 else { return }
            guard count < bytes.count,
                  let request = try? JSONDecoder().decode(MirrorWindowRequest.self, from: Data(bytes.prefix(count))) else { continue }
            onRequest?(request)
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        onRequest = nil
        source?.cancel(); source = nil
        try? input.close()
    }

    deinit { source?.cancel() }
}
