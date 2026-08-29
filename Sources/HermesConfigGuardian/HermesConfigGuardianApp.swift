import SwiftUI

@main
struct HermesConfigGuardianApp: App {
    @StateObject private var model = GuardianModel()

    var body: some Scene {
        #if GUARDIAN_UI_TEST_WINDOW
        WindowGroup("Hermes Config Guardian — Viability Test") {
            GuardianView(model: model)
        }
        .defaultSize(width: 440, height: 520)
        #else
        MenuBarExtra("Hermes Config Guardian", systemImage: model.status.symbol) {
            GuardianView(model: model)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
