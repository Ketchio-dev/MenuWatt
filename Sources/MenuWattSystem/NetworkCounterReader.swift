import Darwin
import Foundation
import MenuWattCore

/// NET_RT_IFLIST2 exposes 64-bit byte counters; getifaddrs' if_data wraps at 4 GiB.
enum NetworkCounterReader {
    static func read() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<2 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return nil }
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes { bytes in
                sysctl(&mib, UInt32(mib.count), bytes.baseAddress, &size, nil, 0)
            }
            if result == 0 {
                guard size <= data.count else { return nil }
                data.count = size
                return parse(data)
            }
            guard errno == ENOMEM else { return nil } // Interfaces can change between calls.
        }
        return nil
    }

    static func parse(_ data: Data) -> NetworkCounters? {
        data.withUnsafeBytes { bytes in
            var offset = 0
            var down: UInt64 = 0
            var up: UInt64 = 0
            while offset < bytes.count {
                guard bytes.count - offset >= 4 else { return nil }
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, length <= bytes.count - offset else { return nil }
                let version = bytes[offset + 2]
                let type = bytes[offset + 3]
                if version == UInt8(RTM_VERSION), type == UInt8(RTM_IFINFO2) {
                    guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
                    let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if message.ifm_flags & IFF_UP != 0, message.ifm_flags & IFF_LOOPBACK == 0 {
                        let nextDown = down.addingReportingOverflow(message.ifm_data.ifi_ibytes)
                        let nextUp = up.addingReportingOverflow(message.ifm_data.ifi_obytes)
                        guard !nextDown.overflow, !nextUp.overflow else { return nil }
                        down = nextDown.partialValue
                        up = nextUp.partialValue
                    }
                }
                offset += length
            }
            return NetworkCounters(downBytes: down, upBytes: up)
        }
    }
}
