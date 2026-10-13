import Darwin
import Foundation
import Testing
@testable import MenuWattCore
@testable import MenuWattSystem

@Test
func networkMessagesKeep64BitTotalsAndExcludeLoopbackAndDownInterfaces() {
    let big = UInt64(UInt32.max) + 1_000
    var data = networkMessage(down: big, up: big + 20, flags: IFF_UP)
    data.append(networkMessage(down: 100, up: 200, flags: IFF_UP))
    data.append(networkMessage(down: 999, up: 999, flags: IFF_UP | IFF_LOOPBACK))
    data.append(networkMessage(down: 999, up: 999, flags: 0))
    #expect(NetworkCounterReader.parse(data) == NetworkCounters(downBytes: big + 100, upBytes: big + 220))
}

@Test
func malformedNetworkMessagesAreRejectedWithoutOutOfBoundsReads() {
    #expect(NetworkCounterReader.parse(Data([1, 2, 3])) == nil)
    #expect(NetworkCounterReader.parse(Data([0, 0, UInt8(RTM_VERSION), UInt8(RTM_IFINFO2)])) == nil)
    var truncated = networkMessage(down: 1, up: 2, flags: IFF_UP)
    truncated.removeLast()
    #expect(NetworkCounterReader.parse(truncated) == nil)
    var overflow = networkMessage(down: UInt64.max, up: 1, flags: IFF_UP)
    overflow.append(networkMessage(down: 1, up: 1, flags: IFF_UP))
    #expect(NetworkCounterReader.parse(overflow) == nil)
}

private func networkMessage(down: UInt64, up: UInt64, flags: Int32) -> Data {
    var message = if_msghdr2()
    message.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
    message.ifm_version = UInt8(RTM_VERSION)
    message.ifm_type = UInt8(RTM_IFINFO2)
    message.ifm_flags = flags
    message.ifm_data.ifi_ibytes = down
    message.ifm_data.ifi_obytes = up
    return withUnsafeBytes(of: &message) { Data($0) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MENUWATT_LIVE_READ_CHECK"] == "1"))
func readOnlyLiveNetworkCountersAreAvailableOnThisHost() throws {
    let counters = try #require(NetworkCounterReader.read())
    print("Read-only live network totals: down=\(counters.downBytes) up=\(counters.upBytes)")
    #expect(counters.downBytes > 0 || counters.upBytes > 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MENUWATT_LIVE_READ_CHECK"] == "1"))
func readOnlyLiveSamplerExposesThisHostsAvailableMetrics() async throws {
    let sampler = LiveMonitorSampler()
    _ = await sampler.sample()
    try await Task.sleep(for: .milliseconds(150))
    let sample = await sampler.sample()
    print("Live read-only battery:", sample.battery.state, sample.battery.percentage,
          "power:", sample.battery.menuBarPowerText ?? "unavailable",
          "temperature:", sample.battery.temperatureCelsius.map(String.init(describing:)) ?? "unavailable")
    print("Live CPU:", sample.system.cpu.titleValue, "memory:", sample.system.memory.titleValue,
          "storage:", sample.system.storage.titleValue, "GPU:", sample.system.gpu.titleValue,
          "fans:", sample.system.fan.titleValue, "network:", sample.system.network.titleValue,
          "processes:", sample.processes.entries.count)
    #expect(sample.system.cpu.isAvailable)
    #expect(sample.system.memory.isAvailable)
    #expect(sample.system.storage.isAvailable)
    #expect(sample.system.network.isAvailable)
    #expect(sample.system.cpu.totalUsage.isFinite && (0...100).contains(sample.system.cpu.totalUsage))
    #expect(sample.system.network.downloadBytesPerSecond.isFinite)
    #expect(sample.system.network.uploadBytesPerSecond.isFinite)
    #expect(sample.processes.entries.allSatisfy { $0.energyImpact.isFinite && $0.cpuPercent.isFinite })
}
