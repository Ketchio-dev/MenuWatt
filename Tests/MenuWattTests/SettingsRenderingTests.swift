import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MenuWatt
@testable import MenuWattCore

/// These tests never present a window or send input to the user's desktop.
/// To export native, window-backed renders, set MENUWATT_RENDER_SETTINGS_DIR.
@Suite(.serialized)
@MainActor
struct SettingsRenderingTests {
    private static let sizes = [NSSize(width: 720, height: 520), NSSize(width: 920, height: 660)]

    @Test
    func initialPaneAndIntrinsicLayoutAtBothWindowSizes() async throws {
        for size in Self.sizes {
            for pane in SettingsPane.allCases {
                let fixture = SettingsRenderingFixture(pane: pane, size: size)
                defer { fixture.dispose() }
                try await fixture.settleLayout()

                try fixture.expectPane(pane)
                try fixture.expectLayout(size: size)
                let scroll = try fixture.paneScrollView()
                #expect(abs(scroll.contentView.bounds.minY - fixture.scrollOrigin(bottom: false, in: scroll)) < 1)
                if pane == .menuBar {
                    #expect(fixture.scrollExtent(in: scroll) > 100)
                }

                try await fixture.scroll(bottom: true)
                #expect(abs(scroll.contentView.bounds.minY - fixture.scrollOrigin(bottom: true, in: scroll)) < 1)
                try await fixture.scroll(bottom: false)
                try fixture.expectPane(pane)
                fixture.expectHiddenWindow()
            }
        }
    }

    @Test
    func localAccessibilityNavigationAndResizeKeepTheSelectedPane() async throws {
        let fixture = SettingsRenderingFixture(pane: .overview)
        defer { fixture.dispose() }
        try await fixture.settleLayout()

        for pane in [SettingsPane.menuBar, .notifications, .updates, .about, .overview] {
            try fixture.press(pane.title)
            try await fixture.settleLayout()
            try await fixture.scroll(bottom: false)
            try fixture.expectPane(pane)

            fixture.window.setContentSize(Self.sizes[1])
            try await fixture.settleLayout()
            try fixture.expectPane(pane)
            try fixture.expectLayout(size: Self.sizes[1])
            fixture.window.setContentSize(Self.sizes[0])
            try await fixture.settleLayout()
            try fixture.expectPane(pane)
            try fixture.expectLayout(size: Self.sizes[0])
        }
        fixture.expectHiddenWindow()
    }

    @Test
    func pauseAndResumeThroughLocalAccessibilityPreserveSavedChoices() async throws {
        let fixture = SettingsRenderingFixture(pane: .menuBar)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        let savedChoices = fixture.cleanup.configuration
        let savedDefaults = fixture.persistentDomain
        let sessionCount = fixture.runtime.sessions.count
        #expect(sessionCount > 0)
        #expect(fixture.cleanup.canRevealItems)

        try fixture.press("Pause Cleanup")
        try await fixture.settleLayout()
        #expect(fixture.cleanup.isPaused)
        #expect(fixture.cleanup.enabled)
        #expect(!fixture.cleanup.canRevealItems)
        #expect(fixture.cleanup.revealMode == .collapsed)
        #expect(fixture.runtime.sessions.count == sessionCount)
        #expect(fixture.runtime.sessions.allSatisfy { $0.invalidations == 1 })
        #expect(fixture.cleanup.configuration == savedChoices)
        #expect(fixture.persistentDomain == savedDefaults)
        #expect(fixture.button(named: "Resume Cleanup") != nil)

        try fixture.press("Resume Cleanup")
        try await fixture.settleLayout()
        #expect(!fixture.cleanup.isPaused)
        #expect(fixture.cleanup.canRevealItems)
        #expect(fixture.cleanup.revealMode == .collapsed)
        #expect(fixture.runtime.sessions.count == sessionCount + 1)
        #expect(fixture.runtime.sessions.last?.invalidations == 0)
        #expect(fixture.cleanup.errorMessage == nil)
        #expect(fixture.cleanup.configuration == savedChoices)
        #expect(fixture.persistentDomain == savedDefaults)
        #expect(fixture.button(named: "Pause Cleanup") != nil)
        fixture.expectHiddenWindow()
    }

    @Test
    func pausedStartupShowsResumeAndAppliesChoicesOnlyAfterLocalPress() async throws {
        let fixture = SettingsRenderingFixture(pane: .menuBar,
            startupEnvironment: ["MENUWATT_START_CLEANUP_PAUSED": "1"])
        defer { fixture.dispose() }
        let choices = fixture.cleanup.configuration
        let savedDefaults = fixture.persistentDomain
        #expect(fixture.cleanup.isPaused)
        #expect(fixture.runtime.sessions.isEmpty)
        try await fixture.settleLayout()
        try fixture.expectPane(.menuBar)
        #expect(fixture.cleanup.enabled)
        #expect(!fixture.cleanup.canRevealItems)
        #expect(fixture.button(named: "Resume Cleanup") != nil)
        #expect(fixture.button(named: "Pause Cleanup") == nil)
        #expect(fixture.runtime.sessions.isEmpty) // Settings onAppear must not apply cleanup.
        #expect(fixture.cleanup.configuration == choices)
        #expect(fixture.persistentDomain == savedDefaults)

        try fixture.press("Resume Cleanup")
        try await fixture.settleLayout()
        #expect(!fixture.cleanup.isPaused)
        #expect(fixture.cleanup.canRevealItems)
        #expect(fixture.cleanup.revealMode == .collapsed)
        #expect(fixture.runtime.sessions.count == 1)
        let plan = try #require(fixture.runtime.plans.last)
        #expect(!plan.allowedSystemItems.contains(5))
        #expect(!plan.allowedBundles.contains("com.example.settings.agenda"))
        #expect(!plan.allowedBundles.contains("com.example.settings.cloud"))
        #expect(fixture.cleanup.configuration == choices)
        #expect(fixture.persistentDomain == savedDefaults)
        #expect(fixture.button(named: "Pause Cleanup") != nil)
        fixture.expectHiddenWindow()
    }

    @Test
    func changingAppCatalogUpdatesIntrinsicHeightAndClampsScrollExtent() async throws {
        let fixture = SettingsRenderingFixture(pane: .menuBar)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        let scroll = try fixture.paneScrollView()
        let document = try #require(scroll.documentView)
        let originalHeight = document.frame.height
        let originalExtent = fixture.scrollExtent(in: scroll)
        try await fixture.scroll(bottom: true)

        // Exercise the real nested hosting view's intrinsic-size invalidation,
        // without typing into the app search field or touching real running apps.
        fixture.runtime.apps = Array(fixture.runtime.apps.prefix(2))
        fixture.cleanup.refresh()
        try await fixture.settleLayout()
        #expect(document.frame.height < originalHeight - 100)
        #expect(fixture.scrollExtent(in: scroll) < originalExtent - 100)
        #expect(scroll.contentView.bounds.maxY <= document.bounds.maxY + 1)
        try fixture.expectLayout(size: Self.sizes[0])
        try await fixture.scroll(bottom: false)
        try fixture.expectPane(.menuBar)
        fixture.expectHiddenWindow()
    }

    @Test
    func viewportTracksLegacyAndOverlayScrollerChanges() async throws {
        let fixture = SettingsRenderingFixture(pane: .menuBar)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        let scroll = try fixture.paneScrollView()
        for style in [NSScroller.Style.legacy, .overlay, .legacy] {
            scroll.scrollerStyle = style
            scroll.tile()
            try await fixture.settleLayout()
            try fixture.expectLayout(size: Self.sizes[0])
            try fixture.setAppSearch("no-fixture-matches-this")
            try await fixture.settleLayout()
            try fixture.expectLayout(size: Self.sizes[0])
            try fixture.press("Clear app search")
            try await fixture.settleLayout()
            try fixture.expectLayout(size: Self.sizes[0])
        }
    }

    @Test
    func graphsToggleInSettingsPersistsWithoutChangingOtherChoices() async throws {
        let fixture = SettingsRenderingFixture(pane: .overview)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        try await fixture.scroll(bottom: true)
        let savedDomain = fixture.persistentDomain
        #expect(fixture.preferences.showsGraphs)
        try fixture.pressToggle("Show graphs")
        try await fixture.settleLayout()
        #expect(!fixture.preferences.showsGraphs)
        #expect(fixture.defaults.object(forKey: "showsGraphs") as? Bool == false)
        var expected = savedDomain as! [String: Any]
        expected["showsGraphs"] = false
        #expect(fixture.persistentDomain == expected as NSDictionary)
        try fixture.pressToggle("Show graphs")
        try await fixture.settleLayout()
        #expect(fixture.preferences.showsGraphs)
        #expect(fixture.defaults.object(forKey: "showsGraphs") as? Bool == true)
    }

    @Test
    func ordinarySettingsTogglesPersistThroughNativeControls() async throws {
        let overview = SettingsRenderingFixture(pane: .overview)
        defer { overview.dispose() }
        try await overview.settleLayout()
        #expect(!overview.preferences.launchesAtLogin)
        try overview.pressToggle("Launch at Login")
        #expect(overview.preferences.launchesAtLogin)
        try overview.pressToggle("Show pixel character")
        #expect(!overview.preferences.showsSprite)
        #expect(overview.defaults.object(forKey: "showsSprite") as? Bool == false)
        try await overview.scroll(bottom: true)
        try overview.pressToggle("CPU")
        #expect(!overview.preferences.visibleDashboardSections.contains(.cpu))
        #expect(!(overview.defaults.array(forKey: "visibleDashboardSections") as? [String] ?? []).contains("cpu"))
        let notifications = SettingsRenderingFixture(pane: .notifications)
        defer { notifications.dispose() }
        try await notifications.settleLayout()
        try notifications.pressToggle("Notify when fully charged")
        try notifications.pressToggle("Notify when battery is low")
        try await notifications.settleLayout()
        #expect(!notifications.preferences.notifyChargeComplete)
        #expect(!notifications.preferences.notifyLowBattery)
        #expect(!SettingsAccessibilityNode.walk(try #require(notifications.window.contentView))
            .flatMap(\.text).contains("Low battery threshold"))
        let updates = SettingsRenderingFixture(pane: .updates)
        defer { updates.dispose() }
        try await updates.settleLayout()
        try updates.pressToggle("Check automatically")
        #expect(updates.preferences.autoCheckForUpdates)
        #expect(updates.defaults.object(forKey: "autoCheckForUpdates") as? Bool == true)
        #expect(updates.checker.status == .idle) // Toggle alone never sends a request.
    }

    @Test
    func nativeHoverTogglePersistsWithoutChangingAssignmentsOrResumingPause() async throws {
        let fixture = SettingsRenderingFixture(pane: .menuBar,
            startupEnvironment: ["MENUWATT_START_CLEANUP_PAUSED": "1"])
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        let choices = fixture.cleanup.configuration.sections
        #expect(fixture.cleanup.isPaused)
        #expect(!fixture.cleanup.revealOnHover)
        try fixture.pressToggle("Reveal on hover")
        try await fixture.settleLayout()
        #expect(fixture.cleanup.revealOnHover)
        #expect(fixture.defaults.bool(forKey: "menuBarCleanup.revealOnHover"))
        #expect(fixture.cleanup.isPaused)
        #expect(fixture.runtime.sessions.isEmpty)
        #expect(fixture.cleanup.configuration.sections == choices)
        try fixture.pressToggle("Reveal on hover")
        #expect(!fixture.cleanup.revealOnHover)
        #expect(fixture.cleanup.isPaused)
        fixture.expectHiddenWindow()
    }

    @Test
    func nativeRevealCollapseShowAllAndRestoreKeepAppAssignments() async throws {
        let fixture = SettingsRenderingFixture(pane: .menuBar)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        let savedSections = fixture.cleanup.configuration.sections
        try fixture.press("Show Hidden")
        try await fixture.settleLayout()
        #expect(fixture.cleanup.revealMode == .hidden)
        #expect(fixture.runtime.plans.last?.allowedBundles.contains("com.example.settings.agenda") == true)
        #expect(fixture.runtime.plans.last?.allowedBundles.contains("com.example.settings.cloud") == false)
        try fixture.press("Collapse")
        try await fixture.settleLayout()
        #expect(fixture.cleanup.revealMode == .collapsed)
        try fixture.press("Show All")
        try await fixture.settleLayout()
        #expect(fixture.cleanup.revealMode == .all)
        #expect(fixture.runtime.plans.last?.allowedBundles.contains("com.example.settings.cloud") == true)
        try fixture.press("Restore Menu Bar")
        try await fixture.settleLayout()
        #expect(!fixture.cleanup.enabled)
        #expect(fixture.cleanup.configuration.sections == savedSections)
        #expect(fixture.runtime.sessions.allSatisfy { $0.invalidations == 1 })
        fixture.expectHiddenWindow()
    }

    @Test
    func appSearchUsesNamesAndBundleIDsAndShrinksTheDocument() async throws {
        let fixture = SettingsRenderingFixture(pane: .menuBar)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        try await fixture.scroll(bottom: true)
        let scroll = try fixture.paneScrollView()
        let document = try #require(scroll.documentView)
        let originalHeight = document.frame.height
        let choices = fixture.cleanup.configuration
        let savedDefaults = fixture.persistentDomain
        try fixture.setAppSearch("  COM.EXAMPLE.SETTINGS.AGENDA  ")
        try await fixture.settleLayout()
        #expect(document.frame.height < originalHeight - 200)
        #expect(fixture.appPickerLabels() == ["Agenda"])

        try fixture.setAppSearch("cloud sync")
        try await fixture.settleLayout()
        #expect(fixture.appPickerLabels() == ["Cloud Sync"])

        try fixture.setAppSearch("no-menuwatt-fixture-matches-this")
        try await fixture.settleLayout()
        #expect(fixture.appPickerLabels().isEmpty)
        let text = SettingsAccessibilityNode.walk(document).flatMap(\.text)
        #expect(text.contains { $0.contains("No apps match") })
        #expect(scroll.contentView.bounds.maxY <= document.bounds.maxY + 1)

        try fixture.press("Clear app search")
        try await fixture.settleLayout()
        #expect(fixture.appPickerLabels().count == fixture.runtime.apps.count)
        #expect(abs(document.frame.height - originalHeight) < 2)
        #expect(fixture.cleanup.configuration == choices)
        #expect(fixture.persistentDomain == savedDefaults)
        fixture.expectHiddenWindow()
    }

    @Test
    func checkNowUsesStubSessionAndPersistsLastCheckedDate() async throws {
        let fixture = SettingsRenderingFixture(pane: .updates)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        #expect(fixture.preferences.lastUpdateCheck == nil)
        #expect(fixture.checker.status == .idle)

        try fixture.press("Check Now")
        for _ in 0..<50 {
            if fixture.preferences.lastUpdateCheck != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await fixture.settleLayout()
        let checked = try #require(fixture.preferences.lastUpdateCheck)
        #expect(fixture.defaults.object(forKey: "lastUpdateCheck") as? Date == checked)
        if case .updateAvailable(let release) = fixture.checker.status {
            #expect(release.tagName == "v999.0.0")
        } else {
            Issue.record("The Settings update action did not consume the stubbed release: \(fixture.checker.status)")
        }
        try fixture.expectPane(.updates)
        fixture.expectHiddenWindow()
    }

    @Test
    func unavailableBatteryDoesNotRenderAsZeroPercent() async throws {
        let localAccessibility = SettingsLocalAccessibility()
        defer { localAccessibility.restore() }
        let host = NSHostingView(rootView: MonitorPanelView(battery: .unavailable, system: .unavailable,
            processes: .unavailable, sprite: SpriteRenderer.image(for: .run1),
            visibleSections: [.battery], showsGraphs: false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let text = SettingsAccessibilityNode.walk(host).flatMap(\.text)
        #expect(text.contains("Unavailable"))
        #expect(!text.contains("0%"))
        #expect(!BoochiPresentation.tooltip(for: .unavailable).contains("0%"))
        #expect(!window.isVisible)
    }

    @Test
    func allMenuBarIndicatorsStayReachableWithoutSpriteOrSensorData() async throws {
        let fixture = SettingsRenderingFixture(pane: .overview)
        defer { fixture.dispose() }
        fixture.preferences.showsSprite = false
        let monitor = PowerMonitor(sampler: TestSampler(responses: []))
        let label = NSHostingView(rootView: MenuBarLabel(monitor: monitor, preferences: fixture.preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 24),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = label
        defer { window.contentView = nil; window.close() }
        for indicator in MenuBarIndicator.allCases {
            fixture.preferences.menuBarIndicator = indicator
            label.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            #expect(label.fittingSize.width >= 8)
            #expect(label.fittingSize.height >= 8)
            let text = SettingsAccessibilityNode.walk(label).flatMap(\.text)
            #expect(text.contains { $0.contains("unavailable") })
            #expect(!window.isVisible)
        }
    }

    @Test
    func expandedClickTargetsCoverMetricRowsAndButtonPadding() async throws {
        let dashboard = DashboardRenderingFixture(showsGraphs: false)
        defer { dashboard.dispose() }
        try await dashboard.settleLayout()
        let nodes = dashboard.accessibilityNodes
        for identifier in ["CPU details", "Memory details", "Fan details", "Network totals"] {
            let node = try #require(nodes.first { $0.identifier == identifier })
            #expect(node.role == NSAccessibility.Role.button.rawValue)
            #expect(node.frame.width >= 300, "The whole metric row must be a target")
            #expect(node.frame.height >= 24)
        }
        for label in ["Settings", "Quit MenuWatt", "2 more processes"] {
            let node = try #require(nodes.first { $0.role == NSAccessibility.Role.button.rawValue && $0.text.contains(label) })
            #expect(node.frame.height >= (label == "2 more processes" ? 20 : 24))
            if label == "2 more processes" { #expect(node.frame.width >= 300) }
        }
        let settings = SettingsRenderingFixture(pane: .menuBar)
        defer { settings.dispose() }
        try await settings.settleLayout()
        let pause = try #require(settings.button(named: "Pause Cleanup"))
        #expect(pause.frame.height >= 30)
        #expect(pause.frame.width >= 100)
        settings.expectHiddenWindow()
    }

    @Test
    func compactDashboardGraphsChangeHeightWithoutRemovingMetrics() async throws {
        let withGraphs = DashboardRenderingFixture(showsGraphs: true)
        defer { withGraphs.dispose() }
        let withoutGraphs = DashboardRenderingFixture(showsGraphs: false)
        defer { withoutGraphs.dispose() }
        try await withGraphs.settleLayout()
        try await withoutGraphs.settleLayout()
        for label in ["CPU history", "GPU history", "Network history"] {
            #expect(withGraphs.text.contains(label))
            #expect(!withoutGraphs.text.contains(label))
        }
        for label in ["CPU", "Memory", "GPU", "Fans", "Network", "Storage", "Top Energy", "Settings", "Quit MenuWatt"] {
            #expect(withGraphs.text.contains { $0.contains(label) })
            #expect(withoutGraphs.text.contains { $0.contains(label) })
        }
        for label in ["Cycle", "Source", "Menu Bar", "Show Icons", "Show All", "Restore", "Pause Cleanup"] {
            #expect(!withGraphs.text.contains(label))
            #expect(!withoutGraphs.text.contains(label))
        }
        // The displayed panel is capped; measure the unbounded metrics too.
        #expect(withGraphs.metricsHeight > withoutGraphs.metricsHeight + 100)
        #expect(withGraphs.contentHeight > withoutGraphs.contentHeight + 80)
        #expect(withGraphs.contentHeight <= 641)
        #expect(withoutGraphs.contentHeight < 500)
        #expect(!withoutGraphs.text.contains("Sys"))
        let compactHeight = withoutGraphs.contentHeight
        withoutGraphs.press("CPU details")
        try await withoutGraphs.settleLayout()
        #expect(withoutGraphs.text.contains("Sys"))
        #expect(withoutGraphs.text.contains("User"))
        #expect(withoutGraphs.contentHeight > compactHeight)
        withoutGraphs.press("CPU details")
        try await withoutGraphs.settleLayout()
        #expect(!withoutGraphs.text.contains("Sys"))
        #expect(abs(withoutGraphs.contentHeight - compactHeight) < 2)
        #expect(!withoutGraphs.text.contains("App"))
        withoutGraphs.press("Memory details")
        try await withoutGraphs.settleLayout()
        #expect(withoutGraphs.text.contains("App"))
        #expect(withoutGraphs.text.contains("Wired"))
        withoutGraphs.press("Memory details")
        withoutGraphs.press("Fan details")
        try await withoutGraphs.settleLayout()
        #expect(withoutGraphs.text.contains("Fan 0"))
        #expect(withoutGraphs.text.contains("Fan 1"))
        withoutGraphs.press("Fan details")
        withoutGraphs.press("Network totals")
        try await withoutGraphs.settleLayout()
        #expect(withoutGraphs.text.contains { $0.contains("↓") && $0.contains("↑") })
        withoutGraphs.press("Network totals")
        #expect(!withoutGraphs.text.contains { $0.contains("Sample Process 4") })
        withoutGraphs.press("2 more processes")
        try await withoutGraphs.settleLayout()
        #expect(withoutGraphs.text.contains { $0.contains("Sample Process 4") })
        #expect(withoutGraphs.text.contains { $0.contains("Sample Process 5") })
        withoutGraphs.press("2 more processes")
        try await withoutGraphs.settleLayout()
        #expect(!withoutGraphs.text.contains { $0.contains("Sample Process 4") })
        withGraphs.press("Settings")
        withoutGraphs.press("Quit MenuWatt")
        #expect(withGraphs.settingsPresses == 1)
        #expect(withoutGraphs.quitPresses == 1)
    }

    @Test(.enabled(if: !(ProcessInfo.processInfo.environment["MENUWATT_RENDER_SETTINGS_DIR"] ?? "").isEmpty))
    func exportNonVisibleNativeDashboardRenders() async throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["MENUWATT_RENDER_SETTINGS_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for graphs in [false, true] {
                let fixture = DashboardRenderingFixture(showsGraphs: graphs, appearance: appearance)
                defer { fixture.dispose() }
                try await fixture.settleLayout()
                let theme = appearance == .darkAqua ? "dark" : "light"
                try fixture.renderPNG().write(to: directory.appendingPathComponent("dashboard-\(graphs ? "graphs-on" : "graphs-off")-\(theme).png"))
            }
        }
    }

    @Test(.enabled(if: !(ProcessInfo.processInfo.environment["MENUWATT_RENDER_SETTINGS_DIR"] ?? "").isEmpty))
    func exportNonVisibleNativeSettingsRenders() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["MENUWATT_RENDER_SETTINGS_DIR"])
        let directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for renderCase in SettingsRenderCase.allCases {
                try await export(renderCase, size: Self.sizes[0], appearance: appearance, directory: directory)
            }
            // One enlarged case checks the same long pane at a different width.
            try await export(.menuBarActive, size: Self.sizes[1], appearance: appearance, directory: directory)
        }
    }

    private func export(_ renderCase: SettingsRenderCase, size: NSSize,
                        appearance: NSAppearance.Name, directory: URL) async throws {
        let fixture = SettingsRenderingFixture(pane: renderCase.pane, size: size, appearance: appearance)
        defer { fixture.dispose() }
        try await fixture.settleLayout()
        if renderCase == .menuBarPaused {
            try fixture.press("Pause Cleanup")
            try await fixture.settleLayout()
            #expect(fixture.cleanup.isPaused)
        } else if renderCase == .updates {
            _ = await fixture.checker.check()
            try await fixture.settleLayout()
        }
        try fixture.expectPane(renderCase.pane)
        try fixture.expectLayout(size: size)
        let scroll = try fixture.paneScrollView()
        let theme = appearance == .darkAqua ? "dark" : "light"
        let name = "\(renderCase.rawValue)-\(theme)-\(Int(size.width))x\(Int(size.height))"

        try await fixture.scroll(bottom: false)
        let upper = try fixture.renderPNG()
        try upper.write(to: directory.appendingPathComponent("\(name)-upper.png"), options: .atomic)
        try await fixture.scroll(bottom: true)
        let lower = try fixture.renderPNG()
        try lower.write(to: directory.appendingPathComponent("\(name)-lower.png"), options: .atomic)
        if fixture.scrollExtent(in: scroll) > 1 {
            #expect(upper != lower, "Scrolling a long pane must change the rendered viewport")
        }
        fixture.expectHiddenWindow()
    }
}

@MainActor
private final class DashboardRenderingFixture {
    private final class Actions {
        var settings = 0
        var quit = 0
    }
    private let actions = Actions()
    private let localAccessibility = SettingsLocalAccessibility()
    private let window: NSWindow
    private let measuringWindow: NSWindow
    private let root: NSHostingView<MenuBarDashboardView>
    private let panel: NSHostingView<MonitorPanelView>

    init(showsGraphs: Bool, appearance: NSAppearance.Name = .aqua) {
        let battery = BatterySnapshot(name: "Battery", percentage: 22, state: .pluggedIn,
            sourceDescription: "Power Adapter", timeEstimate: nil,
            rateDetail: .init(kind: .usage, watts: 11.4), liveInputDetail: nil,
            batteryWatts: 11.4, adapterWatts: 65, systemInputWatts: 11.4, systemLoadWatts: 11.4,
            cycleCount: 60, temperatureCelsius: nil, updatedAt: .now)
        let history: [Double] = [14, 27, 19, 32, 21, 16, 24, 29, 22, 18, 26, 37]
        let system = SystemSnapshot(
            cpu: .init(totalUsage: 25.6, userUsage: 17.9, systemUsage: 7.7, idleUsage: 74.4, history: history),
            memory: .init(usedPercent: 64.4, pressurePercent: 10, pressureLevel: .normal,
                          usedBytes: 41_200_000_000, appMemoryBytes: 29_060_000_000, wiredMemoryBytes: 5_430_000_000,
                          compressedBytes: 6_720_000_000, cachedFilesBytes: 19_830_000_000,
                          swapUsedBytes: 0, pressureHistory: []),
            storage: .init(usedPercent: 74.6, usedBytes: 691_150_000_000, totalBytes: 926_300_000_000),
            gpu: .init(utilizationPercent: 9, history: history.reversed()),
            fan: .init(fans: [.init(index: 0, rpm: 1500, maxRpm: 5000), .init(index: 1, rpm: 1700, maxRpm: 5000)]),
            network: .init(downloadBytesPerSecond: 100_000, uploadBytesPerSecond: 90_000,
                           totalDownBytes: 3_540_000_000, totalUpBytes: 6_640_000_000, history: history))
        let processes = ProcessEnergySnapshot(entries: (1...5).map {
            .init(pid: Int32.max - Int32($0), name: "Sample Process \($0)", energyImpact: Double(100 - $0), cpuPercent: 10)
        })
        let sprite = SpriteRenderer.image(for: .run1)
        let sections = Set(DashboardSection.allCases)
        let actions = self.actions
        root = NSHostingView(rootView: MenuBarDashboardView(battery: battery, system: system, processes: processes,
            sprite: sprite, visibleSections: sections, showsGraphs: showsGraphs,
            onOpenSettings: { actions.settings += 1 }, onQuit: { actions.quit += 1 }))
        panel = NSHostingView(rootView: MonitorPanelView(battery: battery, system: system, processes: processes,
            sprite: sprite, visibleSections: sections, showsGraphs: showsGraphs))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 640),
                          styleMask: [.titled], backing: .buffered, defer: false)
        measuringWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 1200),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        measuringWindow.isReleasedWhenClosed = false
        window.contentView = root
        measuringWindow.contentView = panel
        window.appearance = NSAppearance(named: appearance)
        measuringWindow.appearance = NSAppearance(named: appearance)
    }

    var accessibilityNodes: [SettingsAccessibilityNode] { SettingsAccessibilityNode.walk(root) }
    var text: [String] { accessibilityNodes.flatMap(\.text) }
    var contentHeight: CGFloat { root.fittingSize.height }
    var metricsHeight: CGFloat { panel.fittingSize.height }
    var settingsPresses: Int { actions.settings }
    var quitPresses: Int { actions.quit }

    func settleLayout() async throws {
        for _ in 0..<4 {
            root.layoutSubtreeIfNeeded()
            panel.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        window.setContentSize(NSSize(width: 340, height: root.fittingSize.height))
        root.layoutSubtreeIfNeeded()
        #expect(!window.isVisible && !measuringWindow.isVisible)
        #expect(!window.isKeyWindow && !measuringWindow.isKeyWindow)
    }

    func press(_ label: String) {
        let node = SettingsAccessibilityNode.walk(root).first {
            $0.role == NSAccessibility.Role.button.rawValue && ($0.text.contains(label) || $0.identifier == label)
        }
        #expect(node?.press() == true)
    }

    func renderPNG() throws -> Data {
        let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    func dispose() {
        window.contentView = nil
        measuringWindow.contentView = nil
        window.close()
        measuringWindow.close()
        localAccessibility.restore()
    }
}

private enum SettingsRenderCase: String, CaseIterable {
    case overview
    case menuBarActive = "menu-bar-active"
    case menuBarPaused = "menu-bar-paused"
    case notifications
    case updates
    case about

    var pane: SettingsPane {
        switch self {
        case .overview: .overview
        case .menuBarActive, .menuBarPaused: .menuBar
        case .notifications: .notifications
        case .updates: .updates
        case .about: .about
        }
    }
}

@MainActor
private final class SettingsRenderingFixture {
    let domain = "MenuWatt.SettingsRenderingTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let preferences: AppPreferences
    let runtime = SettingsRenderingRuntime()
    let cleanup: MenuBarCleanupController
    let checker: UpdateChecker
    let window: NSWindow
    private let session: URLSession
    private let localAccessibility = SettingsLocalAccessibility()
    private let previousIcon: NSImage?
    private let fixtureIcon: NSImage?

    init(pane: SettingsPane, size: NSSize = NSSize(width: 720, height: 520),
         appearance: NSAppearance.Name = .aqua, startupEnvironment: [String: String] = [:]) {
        defaults = UserDefaults(suiteName: domain)!
        defaults.setPersistentDomain([
            "menuBarIndicator": "power", "refreshIntervalSeconds": 3, "showsSprite": true,
            "notifyChargeComplete": true, "notifyLowBattery": true, "lowBatteryThreshold": 20,
            "autoCheckForUpdates": false,
            "menuBarCleanup.enabled": true, "menuBarCleanup.hideActivityControls": true,
            "menuBarCleanup.autoRehide": true,
            "menuBarCleanup.sections": ["system:5": "hidden", "app:com.example.settings.agenda": "hidden",
                                        "app:com.example.settings.cloud": "alwaysHidden"]
        ], forName: domain)
        preferences = AppPreferences(launchAtLoginController: SettingsRenderingLoginController(), defaults: defaults)
        cleanup = MenuBarCleanupController(defaults: defaults, runtime: runtime.runtime)
        MenuBarCleanupStartupOptions(environment: startupEnvironment).startCleanup(cleanup)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsReleaseURLProtocol.self]
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        checker = UpdateChecker(session: session)
        previousIcon = NSImage(named: NSImage.applicationIconName)
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        fixtureIcon = NSImage(contentsOf: sourceRoot.appendingPathComponent("Packaging/Resources/AppIcon.icns"))
        previousIcon?.setName("")
        fixtureIcon?.setName(NSImage.applicationIconName)
        // The factory hosts the production SettingsContentView; show() is intentionally never called.
        window = SettingsPanel(preferences: preferences, updateChecker: checker, cleanup: cleanup)
            .makeWindow(initialPane: pane)
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(size)
    }

    private static let minimumSize = NSSize(width: 720, height: 520)

    var persistentDomain: NSDictionary {
        (defaults.persistentDomain(forName: domain) ?? [:]) as NSDictionary
    }

    func dispose() {
        cleanup.stop()
        session.invalidateAndCancel()
        window.contentView = nil
        window.close()
        defaults.removePersistentDomain(forName: domain)
        localAccessibility.restore()
        fixtureIcon?.setName("")
        previousIcon?.setName(NSImage.applicationIconName)
    }

    func expectHiddenWindow() {
        #expect(!window.isVisible)
        #expect(!window.isKeyWindow)
        #expect(!window.isMainWindow)
    }

    func settleLayout() async throws {
        for _ in 0..<4 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        expectHiddenWindow()
    }

    func paneScrollView() throws -> NSScrollView {
        let root = try #require(window.contentView)
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        // A future native sidebar may also contain a scroll view; select the wider detail pane.
        return try #require(scrollViews(in: root).max { $0.frame.width < $1.frame.width })
    }

    func expectLayout(size: NSSize) throws {
        let root = try #require(window.contentView)
        #expect(abs(root.bounds.width - size.width) < 1)
        #expect(abs(root.bounds.height - size.height) < 1)
        #expect(root.fittingSize.width.isFinite && root.fittingSize.height.isFinite)
        #expect(root.fittingSize.width <= size.width + 1)
        #expect(root.fittingSize.height <= size.height + 1)
        let scroll = try paneScrollView()
        let document = try #require(scroll.documentView)
        #expect(window.styleMask.contains(.resizable))
        #expect(window.contentMinSize == Self.minimumSize)
        #expect(scroll.hasVerticalScroller)
        #expect(!scroll.hasHorizontalScroller)
        #expect(scroll.contentView.bounds.width > 200)
        #expect(scroll.contentView.bounds.height > 200)
        #expect(abs(document.frame.width - scroll.contentView.bounds.width) < 1)
        #expect(document.frame.height.isFinite && document.frame.height > 0)
        #expect(document.intrinsicContentSize.height > 0)
        #expect(abs(document.intrinsicContentSize.width - scroll.contentView.bounds.width) < 1)
        #expect(abs(document.frame.height - document.intrinsicContentSize.height) < 2)
    }

    func expectPane(_ pane: SettingsPane) throws {
        let document = try #require(try paneScrollView().documentView)
        let text = SettingsAccessibilityNode.walk(document).flatMap(\.text)
        let markers: [SettingsPane: String] = [
            .overview: "Launch at Login", .menuBar: "Enable Menu Bar Cleanup",
            .notifications: "Notify when fully charged", .updates: "Check Now", .about: "Discord"
        ]
        let marker = try #require(markers[pane])
        #expect(text.contains { $0.contains(marker) }, "The detail pane must start on \(pane.title)")
        for (other, otherMarker) in markers where other != pane {
            #expect(!text.contains { $0.contains(otherMarker) }, "An unselected pane must not remain in the detail view")
        }
    }

    func button(named label: String) -> SettingsAccessibilityNode? {
        guard let root = window.contentView else { return nil }
        return SettingsAccessibilityNode.walk(root).first {
            $0.role == NSAccessibility.Role.button.rawValue && $0.text.contains { $0.contains(label) }
        }
    }

    func setAppSearch(_ text: String) throws {
        let root = try #require(window.contentView)
        func fields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
        }
        let field = try #require(fields(in: root).first { $0.placeholderString == "Name or bundle ID" })
        field.stringValue = text
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        expectHiddenWindow()
    }

    func appPickerLabels() -> [String] {
        guard let root = window.contentView else { return [] }
        let titles = Set(cleanup.entries.filter { $0.bundleID != nil }.map(\.title))
        return SettingsAccessibilityNode.walk(root).filter {
            $0.role == NSAccessibility.Role.popUpButton.rawValue
        }.flatMap(\.text).filter { titles.contains($0) }
    }

    func pressToggle(_ label: String) throws {
        let root = try #require(window.contentView)
        let node = try #require(SettingsAccessibilityNode.walk(root).first {
            $0.text.contains(label) && ($0.role == NSAccessibility.Role.checkBox.rawValue || $0.role == "AXSwitch")
        }, "Missing labeled toggle: \(label)")
        #expect(node.press())
        expectHiddenWindow()
    }

    func press(_ label: String) throws {
        let node = try #require(button(named: label), "Missing local accessible button: \(label)")
        #expect(node.press(), "The local accessibility press must be handled: \(label)")
        expectHiddenWindow()
    }

    func scrollExtent(in scroll: NSScrollView) -> CGFloat {
        max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
    }

    func scrollOrigin(bottom: Bool, in scroll: NSScrollView) -> CGFloat {
        guard let document = scroll.documentView else { return 0 }
        let atMaximum = document.isFlipped ? bottom : !bottom
        return document.bounds.minY + (atMaximum ? scrollExtent(in: scroll) : 0)
    }

    func scroll(bottom: Bool) async throws {
        let scroll = try paneScrollView()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scrollOrigin(bottom: bottom, in: scroll)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settleLayout()
    }

    func renderPNG() throws -> Data {
        expectHiddenWindow()
        let root = try #require(window.contentView)
        let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        #expect(bitmap.pixelsWide >= Int(root.bounds.width))
        #expect(bitmap.pixelsHigh >= Int(root.bounds.height))
        // Reject an empty/uniform buffer rather than exporting a placeholder image.
        var brightness: [CGFloat] = []
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 32)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 32)) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    brightness.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
                }
            }
        }
        let minimum = try #require(brightness.min())
        let maximum = try #require(brightness.max())
        #expect(maximum - minimum > 0.05, "The native render must contain visible Settings content")
        expectHiddenWindow()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

private final class SettingsRenderingLoginController: LaunchAtLoginControlling {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

@MainActor
private final class SettingsRenderingSession: MenuBarCleanupSession {
    var invalidations = 0
    func invalidate() { invalidations += 1 }
}

@MainActor
private final class SettingsRenderingRuntime {
    var sessions: [SettingsRenderingSession] = []
    var plans: [MenuBarVisibilityPlan] = []
    var apps: [MenuBarCleanupApp] = [
        .init(bundleID: "com.example.settings.agenda", title: "Agenda",
              bundleURL: URL(fileURLWithPath: "/MenuWattSettingsFixtures/Agenda.app"), isProhibited: false),
        .init(bundleID: "com.example.settings.cloud", title: "Cloud Sync",
              bundleURL: URL(fileURLWithPath: "/MenuWattSettingsFixtures/Cloud Sync.app"), isProhibited: false)
    ] + (1...14).map { index in
        MenuBarCleanupApp(bundleID: "com.example.settings.app\(index)", title: "Example App \(index)",
                          bundleURL: URL(fileURLWithPath: "/MenuWattSettingsFixtures/Example App \(index).app"),
                          isProhibited: false)
    }

    var runtime: MenuBarCleanupRuntime {
        MenuBarCleanupRuntime(isSupported: true, makeSession: { [self] plan, completion in
            plans.append(plan)
            let session = SettingsRenderingSession()
            sessions.append(session)
            completion(nil)
            return session
        }, makeHotKeys: { _ in NSObject() }, runningApps: { [self] in apps },
        workspaceNotifications: NotificationCenter(), applicationNotifications: NotificationCenter())
    }
}

private final class SettingsReleaseURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let payload = #"{"tag_name":"v999.0.0","html_url":"https://example.invalid/menuwatt/release","published_at":"2026-01-01T00:00:00Z","body":"Settings rendering test release. No browser or download is opened."}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// SwiftUI defers its virtual AX tree until enhanced accessibility is enabled.
/// Change only the test process's local AppKit flag, then restore it. This does
/// not use AXUIElement, query another application, or request TCC permission.
@MainActor
private final class SettingsLocalAccessibility {
    private let application = NSApplication.shared
    private let attribute = "AXEnhancedUserInterface" as NSString
    private let previous: AnyObject?

    init() {
        previous = application.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: attribute)?
            .takeUnretainedValue()
        set(NSNumber(value: true))
    }

    func restore() { set(previous) }

    private func set(_ value: AnyObject?) {
        let selector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        guard application.responds(to: selector), let implementation = application.method(for: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject) -> Void
        unsafeBitCast(implementation, to: Setter.self)(application, selector, value, attribute)
    }
}

/// Some SwiftUI virtual nodes implement AX selectors without formally conforming
/// to NSAccessibilityProtocol. Read their object-valued selectors locally, and
/// invoke the BOOL press selector with its matching Objective-C ABI.
@MainActor
private struct SettingsAccessibilityNode {
    let object: NSObject

    private func value(_ selector: Selector) -> Any? {
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    var text: [String] {
        [#selector(NSAccessibilityProtocol.accessibilityLabel),
         #selector(NSAccessibilityProtocol.accessibilityTitle),
         #selector(NSAccessibilityProtocol.accessibilityValue)].compactMap { value($0) as? String }
    }

    var role: String? { value(#selector(NSAccessibilityProtocol.accessibilityRole)) as? String }
    var identifier: String? { value(#selector(NSAccessibilityProtocol.accessibilityIdentifier)) as? String }
    var frame: NSRect {
        if let element = object as? any NSAccessibilityProtocol { return element.accessibilityFrame() }
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector), let implementation = object.method(for: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(implementation, to: Getter.self)(object, selector)
    }

    func press() -> Bool {
        if let element = object as? any NSAccessibilityProtocol { return element.accessibilityPerformPress() }
        let selector = #selector(NSAccessibilityProtocol.accessibilityPerformPress)
        guard object.responds(to: selector), let implementation = object.method(for: selector) else { return false }
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(implementation, to: Press.self)(object, selector)
    }

    static func walk(_ root: NSObject) -> [Self] {
        var nodes: [Self] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            let node = Self(object: object)
            nodes.append(node)
            let children = node.value(#selector(NSAccessibilityProtocol.accessibilityChildren)) as? [NSObject] ?? []
            for child in children { visit(child) }
            // Representable/native containers may not forward all hosted children.
            if let view = object as? NSView {
                for child in view.subviews { visit(child) }
            }
        }
        visit(root)
        return nodes
    }
}
