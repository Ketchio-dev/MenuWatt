import Darwin
import Foundation
import MenuWattCore

struct NetworkInterfaceSnapshot: Sendable, Equatable {
    let interfaces: [UInt16: NetworkCounters]
    let totals: NetworkCounters

    init?(interfaces: [UInt16: NetworkCounters]) {
        var down: UInt64 = 0
        var up: UInt64 = 0
        for counters in interfaces.values {
            let nextDown = down.addingReportingOverflow(counters.downBytes)
            let nextUp = up.addingReportingOverflow(counters.upBytes)
            guard !nextDown.overflow, !nextUp.overflow else { return nil }
            down = nextDown.partialValue
            up = nextUp.partialValue
        }
        self.interfaces = interfaces
        totals = NetworkCounters(downBytes: down, upBytes: up)
    }

    func delta(since previous: Self) -> NetworkCounters {
        var down: UInt64 = 0
        var up: UInt64 = 0
        for (index, current) in interfaces {
            guard let old = previous.interfaces[index] else { continue }
            if current.downBytes >= old.downBytes { down += current.downBytes - old.downBytes }
            if current.upBytes >= old.upBytes { up += current.upBytes - old.upBytes }
        }
        return NetworkCounters(downBytes: down, upBytes: up)
    }
}

/// NET_RT_IFLIST2 exposes 64-bit byte counters; getifaddrs' if_data wraps at 4 GiB.
enum NetworkCounterReader {
    static func read() -> NetworkInterfaceSnapshot? {
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

    static func parse(_ data: Data) -> NetworkInterfaceSnapshot? {
        data.withUnsafeBytes { bytes in
            var offset = 0
            var interfaces: [UInt16: NetworkCounters] = [:]
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
                        interfaces[message.ifm_index] = NetworkCounters(
                            downBytes: message.ifm_data.ifi_ibytes, upBytes: message.ifm_data.ifi_obytes)
                    }
                }
                offset += length
            }
            return NetworkInterfaceSnapshot(interfaces: interfaces)
        }
    }
}
