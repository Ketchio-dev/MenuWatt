import Foundation
import Testing
@testable import MenuWatt

@MainActor
struct DashboardGraphPreferencesTests {
    @Test
    func defaultsToShowingGraphsWithoutPersistingTheDefault() {
        let domain = "MenuWatt.DashboardGraphPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        let preferences = AppPreferences(launchAtLoginController: GraphPreferencesLoginController(), defaults: defaults)

        #expect(preferences.showsGraphs)
        #expect(defaults.object(forKey: "showsGraphs") == nil)

        preferences.showsGraphs = true
        #expect(defaults.object(forKey: "showsGraphs") == nil)
    }

    @Test
    func storedFalseSurvivesNewPreferencesAndDefaultsInstances() {
        let domain = "MenuWatt.DashboardGraphPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "showsGraphs")

        let preferences = AppPreferences(launchAtLoginController: GraphPreferencesLoginController(), defaults: defaults)
        let reloaded = AppPreferences(
            launchAtLoginController: GraphPreferencesLoginController(),
            defaults: UserDefaults(suiteName: domain)!
        )

        #expect(!preferences.showsGraphs)
        #expect(!reloaded.showsGraphs)
        #expect(defaults.object(forKey: "showsGraphs") as? Bool == false)
    }

    @Test
    func togglingGraphsPersistsOnlyTheGraphSetting() {
        let domain = "MenuWatt.DashboardGraphPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let lastUpdateCheck = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.setPersistentDomain([
            "menuBarIndicator": "temperature",
            "refreshIntervalSeconds": 10,
            "showsSprite": false,
            "notifyChargeComplete": true,
            "notifyLowBattery": true,
            "lowBatteryThreshold": 35,
            "autoCheckForUpdates": false,
            "lastUpdateCheck": lastUpdateCheck,
            "visibleDashboardSections": ["battery", "cpu"],
            "knownDashboardSections": DashboardSection.allCases.map(\.rawValue),
            "menuBarCleanup.enabled": true,
            "menuBarCleanup.hideActivityControls": false,
            "menuBarCleanup.autoRehide": false,
            "menuBarCleanup.sections": ["app:com.example.music": "alwaysHidden", "system:5": "hidden"],
            "unrelatedSentinel": ["keep": ["original", "values"]],
        ], forName: domain)
        let preferences = AppPreferences(launchAtLoginController: GraphPreferencesLoginController(), defaults: defaults)
        // Initialization retains the existing dashboard-section migration writes.
        let savedPreferences = defaults.persistentDomain(forName: domain) ?? [:]

        for showsGraphs in [false, true, false] {
            preferences.showsGraphs = showsGraphs

            #expect(preferences.showsGraphs == showsGraphs)
            #expect(defaults.object(forKey: "showsGraphs") as? Bool == showsGraphs)
            var expected = savedPreferences
            expected["showsGraphs"] = showsGraphs
            #expect((defaults.persistentDomain(forName: domain) ?? [:]) as NSDictionary == expected as NSDictionary)
        }

        #expect(preferences.refreshInterval == .tenSeconds)
        #expect(preferences.menuBarIndicator == .temperature)
        #expect(preferences.visibleDashboardSections == [.battery, .cpu])
        #expect(!preferences.showsSprite)
        #expect(preferences.notifyChargeComplete)
        #expect(preferences.notifyLowBattery)
        #expect(preferences.lowBatteryThreshold == 35)
        #expect(!preferences.autoCheckForUpdates)
        #expect(preferences.lastUpdateCheck == lastUpdateCheck)
    }

    @Test
    func graphDefaultLeavesLegacyDashboardSectionMigrationIntact() {
        let domain = "MenuWatt.DashboardGraphPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["battery"], forKey: "visibleDashboardSections")

        let preferences = AppPreferences(launchAtLoginController: GraphPreferencesLoginController(), defaults: defaults)
        let expectedSections: Set<DashboardSection> = [.battery, .gpu, .fan, .network, .processes]

        #expect(preferences.showsGraphs)
        #expect(defaults.object(forKey: "showsGraphs") == nil)
        #expect(preferences.visibleDashboardSections == expectedSections)
        #expect(Set(defaults.stringArray(forKey: "visibleDashboardSections") ?? []) == Set(expectedSections.map(\.rawValue)))
        #expect(Set(defaults.stringArray(forKey: "knownDashboardSections") ?? []) == Set(DashboardSection.allCases.map(\.rawValue)))
    }
}

private struct GraphPreferencesLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}
