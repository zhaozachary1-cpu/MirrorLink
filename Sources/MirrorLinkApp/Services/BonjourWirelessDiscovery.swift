import Darwin
import Foundation

/// Browse in this application's permission context instead of relying on the
/// shared ADB daemon's mDNS backend. Each scan owns and stops its own browsers.
/// Call off the main thread; no sockets are opened to unselected phones.
final class BonjourWirelessDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browsers: [NetServiceBrowser] = []
    private var resolving: [String: NetService] = [:]
    private var resolved: [String: [WirelessService]] = [:]

    static func discover(cancellation: ProcessCancellation?, duration: TimeInterval = 2) -> [WirelessService] {
        guard cancellation?.isCancelled != true else { return [] }
        return BonjourWirelessDiscovery().scan(cancellation: cancellation, duration: duration)
    }

    private func scan(cancellation: ProcessCancellation?, duration: TimeInterval) -> [WirelessService] {
        let loop = RunLoop.current
        for kind in [WirelessServiceKind.pairing, .connection] {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.schedule(in: loop, forMode: .default)
            browsers.append(browser)
            browser.searchForServices(ofType: kind.rawValue + ".", inDomain: "local.")
        }
        defer {
            for browser in browsers {
                browser.stop()
                browser.remove(from: loop, forMode: .default)
                browser.delegate = nil
            }
            for service in resolving.values {
                service.stop()
                service.remove(from: loop, forMode: .default)
                service.delegate = nil
            }
        }
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline, cancellation?.isCancelled != true {
            loop.run(until: min(deadline, Date().addingTimeInterval(0.05)))
        }
        guard cancellation?.isCancelled != true else { return [] }
        return WirelessService.merging(resolved.values.flatMap { $0 })
    }

    private func key(_ service: NetService) -> String {
        "\(service.name)|\(service.type)|\(service.domain)"
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let id = key(service)
        guard resolving[id] == nil else { return }
        resolving[id] = service
        service.delegate = self
        service.schedule(in: .current, forMode: .default)
        service.resolve(withTimeout: 1.5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = key(service)
        if let previous = resolving.removeValue(forKey: id) {
            previous.stop()
            previous.remove(from: .current, forMode: .default)
            previous.delegate = nil
        }
        resolved[id] = nil
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let kind = WirelessServiceKind(rawValue: sender.type.trimmingCharacters(in: CharacterSet(charactersIn: "."))),
              (1...65535).contains(sender.port) else { return }
        let candidates = (sender.addresses ?? []).compactMap {
            Self.endpoint(address: $0, port: sender.port).map {
                WirelessService(name: sender.name, kind: kind, endpoint: $0)
            }
        }
        // One resolved Bonjour instance may publish both IPv4 and IPv6. Keep
        // one numeric endpoint per instance, preferring IPv4, so one scan does
        // not appear to be two phones responding to the same QR credential.
        resolved[key(sender)] = candidates.sorted {
            if $0.endpoint.host.contains(":") != $1.endpoint.host.contains(":") {
                return !$0.endpoint.host.contains(":")
            }
            return $0.endpoint.address < $1.endpoint.address
        }.first.map { [$0] } ?? []
    }

    /// Only numeric, validated IP endpoints leave the Bonjour resolver. In
    /// particular, keep the interface scope on IPv6 link-local addresses.
    static func endpoint(address: Data, port: Int) -> WirelessEndpoint? {
        guard (1...65535).contains(port), address.count >= MemoryLayout<sockaddr>.size else { return nil }
        var storage = sockaddr_storage()
        guard address.count <= MemoryLayout.size(ofValue: storage) else { return nil }
        _ = withUnsafeMutableBytes(of: &storage) { address.copyBytes(to: $0) }
        let family = Int32(storage.ss_family)
        guard (family == AF_INET && address.count >= MemoryLayout<sockaddr_in>.size)
                || (family == AF_INET6 && address.count >= MemoryLayout<sockaddr_in6>.size) else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(address.count), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
            }
        }
        guard status == 0 else { return nil }
        let host = String(cString: buffer)
        return try? WirelessEndpoint(family == AF_INET6 ? "[\(host)]:\(port)" : "\(host):\(port)")
    }
}
