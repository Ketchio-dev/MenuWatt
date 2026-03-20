import Foundation
import Testing
@testable import MenuWatt

private final class LaunchAtLoginControllerMock: LaunchAtLoginControlling {
    var isEnabled: Bool
    var error: (any Error)?

    init(isEnabled: Bool, error: (any Error)? = nil) {
        self.isEnabled = isEnabled
        self.error = error
    }

    func setEnabled(_ enabled: Bool) throws {
        if let error {
            throw error
        }

        isEnabled = enabled
    }
}

private enum MockError: Error {
    case registrationFailed
}

private func makeTestDefaults(testName: String = #function) -> UserDefaults {
    let suiteName = "MenuWattTests.AppPreferences.\(testName)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@Test
@MainActor
func launchAtLoginToggleUpdatesStateOnSuccess() {
    let controller = LaunchAtLoginControllerMock(isEnabled: false)
    let preferences = AppPreferences(launchAtLoginController: controller)

    preferences.setLaunchAtLogin(true)

    #expect(preferences.launchesAtLogin)
    #expect(preferences.launchAtLoginError == nil)
}

@Test
@MainActor
func launchAtLoginToggleShowsErrorOnFailure() {
    let controller = LaunchAtLoginControllerMock(isEnabled: false, error: MockError.registrationFailed)
    let preferences = AppPreferences(launchAtLoginController: controller)

    preferences.setLaunchAtLogin(true)

    #expect(!preferences.launchesAtLogin)
    #expect(preferences.launchAtLoginError != nil)
}

@Test
@MainActor
func launchAtLoginErrorCanBeDismissed() {
    let controller = LaunchAtLoginControllerMock(isEnabled: false, error: MockError.registrationFailed)
    let preferences = AppPreferences(launchAtLoginController: controller)

    preferences.setLaunchAtLogin(true)
    preferences.dismissLaunchAtLoginError()

    #expect(preferences.launchAtLoginError == nil)
}
