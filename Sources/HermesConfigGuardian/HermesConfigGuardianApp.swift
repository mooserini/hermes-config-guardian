import AppKit
import SwiftUI

@main
struct HermesConfigGuardianApp: App {
    @StateObject private var model: GuardianModel
    #if !GUARDIAN_UI_TEST_WINDOW
    private let reviewWindowController: GuardianReviewWindowController
    #endif

    init() {
        let model = GuardianModel()
        _model = StateObject(wrappedValue: model)
        #if !GUARDIAN_UI_TEST_WINDOW
        let controller = GuardianReviewWindowController(model: model)
        reviewWindowController = controller
        model.setAttentionWindowHandler { [weak controller] in
            controller?.show()
        }
        #endif
    }

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
            GuardianMenuBarView(
                model: model,
                onOpenWindow: reviewWindowController.show
            )
                .frame(minWidth: 360, idealWidth: 440, maxWidth: 520, maxHeight: 640)
        }
        .menuBarExtraStyle(.window)
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
    let onOpenWindow: () -> Void

    var body: some View {
        GuardianView(
            model: model,
            onOpenWindow: onOpenWindow
        )
    }
}

@MainActor
private final class GuardianReviewWindowController {
    private let model: GuardianModel
    private var window: NSWindow?

    init(model: GuardianModel) {
        self.model = model
    }

    func show() {
        let reviewWindow: NSWindow
        if let window {
            reviewWindow = window
        } else {
            let hostingController = NSHostingController(
                rootView: GuardianView(model: model)
            )
            let created = NSWindow(contentViewController: hostingController)
            created.title = "Hermes Config Guardian"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.setContentSize(NSSize(width: 440, height: 520))
            created.minSize = NSSize(width: 360, height: 360)
            created.isReleasedWhenClosed = false
            created.center()
            window = created
            reviewWindow = created
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        reviewWindow.makeKeyAndOrderFront(nil)
    }
}
#endif
