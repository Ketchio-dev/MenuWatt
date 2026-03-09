import Foundation
import ServiceManagement
import MenuWattCore

protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct LaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?

    private let launchAtLoginController: any LaunchAtLoginControlling
    private let logger = MenuWattDiagnostics.preferences

    init(launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController()) {
        self.launchAtLoginController = launchAtLoginController
        self.launchesAtLogin = launchAtLoginController.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchesAtLogin = launchAtLoginController.isEnabled
            launchAtLoginError = nil
            logger.info("Launch at Login set to \(self.launchesAtLogin, privacy: .public)")
        } catch {
            launchesAtLogin = launchAtLoginController.isEnabled
            launchAtLoginError = "MenuWatt could not update Launch at Login. Check System Settings > General > Login Items."
            logger.error("Failed to update Launch at Login: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismissLaunchAtLoginError() {
        launchAtLoginError = nil
    }
}
