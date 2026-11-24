import Darwin
import Foundation

/// Request local-network access from the responsible app before asking its
/// short-lived ADB client to pair. UDP connect checks policy without sending a
/// packet or consuming Android's single-use TCP pairing listener (Apple TN3179).
enum LocalNetworkReadiness {
    static func wait(for endpoint: WirelessEndpoint, timeout: TimeInterval,
                     cancellation: ProcessCancellation?) -> Bool {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            guard cancellation?.isCancelled != true else { return false }
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
            hints.ai_socktype = SOCK_DGRAM
            var addresses: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(endpoint.host, "9", &hints, &addresses) == 0, let address = addresses else { return false }
            let fd = socket(address.pointee.ai_family, SOCK_DGRAM, 0)
            let permitted: Bool
            if fd >= 0 {
                _ = fcntl(fd, F_SETFL, O_NONBLOCK)
                permitted = Darwin.connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0
                Darwin.close(fd)
            } else { permitted = false }
            freeaddrinfo(addresses)
            if permitted { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }
}
