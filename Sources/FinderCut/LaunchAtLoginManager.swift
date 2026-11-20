import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var isSupported: Bool = false

    init() {
        isSupported = Bundle.main.bundleURL.pathExtension == "app"
        refresh()
    }

    func refresh() {
        guard isSupported else {
            isEnabled = false
            return
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Keep UI synchronized with actual system registration state.
        }
        refresh()
    }
}
