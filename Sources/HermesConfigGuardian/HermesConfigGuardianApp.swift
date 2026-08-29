import SwiftUI

@main
struct HermesConfigGuardianApp: App {
    @StateObject private var model = GuardianModel()

    var body: some Scene {
        #if GUARDIAN_UI_TEST_WINDOW
        WindowGroup("Hermes Config Guardian — Viability Test") {
            GeometryReader { proxy in
                GuardianView(model: model)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(minWidth: 360, minHeight: 360)
            .onAppear(perform: applySpecimenWindowSize)
        }
        .defaultSize(width: 440, height: 520)
        .windowResizability(.contentMinSize)
        #else
        MenuBarExtra("Hermes Config Guardian", systemImage: model.status.symbol) {
            GuardianMenuBarView(model: model)
                .frame(minWidth: 360, idealWidth: 440, maxWidth: 520, maxHeight: 640)
        }
        .menuBarExtraStyle(.window)

        Window("Hermes Config Guardian", id: "guardian-review") {
            GuardianView(model: model)
        }
        .defaultSize(width: 440, height: 520)
        .windowResizability(.contentMinSize)
        #endif
    }

    #if GUARDIAN_UI_TEST_WINDOW
    private func applySpecimenWindowSize() {
        let spec = ProcessInfo.processInfo.environment["HCG_UI_WINDOW_SIZE"] ?? ""
        let parts = spec.split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]) else { return }
        DispatchQueue.main.async {
            NSApplication.shared.windows.first { $0.isVisible }?
                .setContentSize(NSSize(width: width, height: height))
        }
    }
    #endif
}

#if !GUARDIAN_UI_TEST_WINDOW
private struct GuardianMenuBarView: View {
    @ObservedObject var model: GuardianModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GuardianView(
            model: model,
            onOpenWindow: { openWindow(id: "guardian-review") }
        )
    }
}
#endif
