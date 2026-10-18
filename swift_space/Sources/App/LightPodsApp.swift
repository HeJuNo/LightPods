import SwiftUI

@main
struct LightPodsApp: App {
    @StateObject private var controller = PodController()
    @StateObject private var drills = DrillStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DrillLibraryView()
                .environmentObject(controller)
                .environmentObject(drills)
                .onAppear { controller.setScanning(true) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: controller.manager.appDidEnterBackground()
            case .active: controller.manager.appWillEnterForeground()
            default: break
            }
        }
    }
}
