import Foundation
import Testing
@testable import MenuWatt

private final class LaunchAtLoginControllerMock: LaunchAtLoginControlling {
    var isEnabled: Bool
    var setEnabledError: (any Error)?
    var refreshError: (any Error)?

    init(
        isEnabled: Bool,
        setEnabledError: (any Error)? = nil,
        refreshError: (any Error)? = nil
    ) {
        self.isEnabled = isEnabled
        self.setEnabledError = setEnabledError
        self.refreshError = refreshError
    }

    func setEnabled(_ enabled: Bool) throws {
        if let setEnabledError {
            throw setEnabledError
        }

        isEnabled = enabled
    }

    func refreshConfigurationIfNeeded() throws {
        if let refreshError {
            throw refreshError
        }
    }
}

private enum MockError: Error {
    case registrationFailed
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
    let controller = LaunchAtLoginControllerMock(isEnabled: false, setEnabledError: MockError.registrationFailed)
    let preferences = AppPreferences(launchAtLoginController: controller)

    preferences.setLaunchAtLogin(true)

    #expect(!preferences.launchesAtLogin)
    #expect(preferences.launchAtLoginError != nil)
}

@Test
@MainActor
func launchAtLoginErrorCanBeDismissed() {
    let controller = LaunchAtLoginControllerMock(isEnabled: false, setEnabledError: MockError.registrationFailed)
    let preferences = AppPreferences(launchAtLoginController: controller)

    preferences.setLaunchAtLogin(true)
    preferences.dismissLaunchAtLoginError()

    #expect(preferences.launchAtLoginError == nil)
}

@Test
@MainActor
func refreshFailureDuringInitializationSurfacesError() {
    let controller = LaunchAtLoginControllerMock(
        isEnabled: true,
        refreshError: MockError.registrationFailed
    )

    let preferences = AppPreferences(launchAtLoginController: controller)

    #expect(preferences.launchesAtLogin)
    #expect(preferences.launchAtLoginError?.contains("Failed to refresh Launch at Login") == true)
}
