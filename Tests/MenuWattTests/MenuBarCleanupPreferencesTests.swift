import Foundation
import Testing
@testable import MenuWatt
@testable import MenuWattCore

@Test @MainActor
func cleanupRestoresSavedChoicesAcrossControllerInstances() {
    let domain = "MenuWatt.CleanupTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let controller = MenuBarCleanupController(defaults: defaults)
    controller.enabled = true
    controller.autoRehide = false
    controller.keepActivityControlsHidden = true
    controller.setSection(.alwaysHidden, for: "app:com.example.music")
    controller.setSection(.hidden, for: "system:5")

    let relaunched = MenuBarCleanupController(defaults: defaults)
    #expect(relaunched.enabled)
    #expect(!relaunched.autoRehide)
    #expect(relaunched.keepActivityControlsHidden)
    #expect(relaunched.section(for: "app:com.example.music") == .alwaysHidden)
    #expect(relaunched.section(for: "system:5") == .hidden)
}

@Test @MainActor
func cleanupRestoreDisablesTheFeatureButPreservesTheLayout() {
    let domain = "MenuWatt.CleanupTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let controller = MenuBarCleanupController(defaults: defaults)
    controller.setSection(.hidden, for: "app:com.example.music")
    controller.enabled = true
    controller.restoreSystemMenuBar()

    let relaunched = MenuBarCleanupController(defaults: defaults)
    #expect(!relaunched.enabled)
    #expect(relaunched.section(for: "app:com.example.music") == .hidden)
}
