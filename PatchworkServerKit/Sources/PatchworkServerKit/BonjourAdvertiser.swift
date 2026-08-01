import Foundation
#if os(macOS)
import dnssd

/// Advertises the sync server as _Patchwork-sync._tcp so it's discoverable with
/// `dns-sd -B _Patchwork-sync._tcp` (and, later, by other devices on the LAN).
final class BonjourAdvertiser {
    private var service: DNSServiceRef?

    func start(port: UInt16) {
        stop()
        DNSServiceRegister(
            &service,
            0, 0,
            "Patchwork",
            "_Patchwork-sync._tcp",
            nil, nil,
            port.bigEndian,
            0, nil, nil, nil
        )
    }

    func stop() {
        if let service {
            DNSServiceRefDeallocate(service)
            self.service = nil
        }
    }
}
#else
// iOS/visionOS advertising needs NSBonjourServices + local-network usage
// strings; loopback discovery isn't useful there anyway.
final class BonjourAdvertiser {
    func start(port: UInt16) {}
    func stop() {}
}
#endif
