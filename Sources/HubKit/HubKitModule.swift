import AppKit
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum HubKitModule {
    @MainActor public static func install() {
        Services.hub = Hub.shared
        Services.onboarding = Onboarding.shared
    }
}
