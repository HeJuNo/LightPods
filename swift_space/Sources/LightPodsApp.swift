import SwiftUI

@main
struct LightPodsApp: App {
    @StateObject private var controller = PodController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
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

struct ContentView: View {
    var body: some View {
        TabView {
            PodListView()
                .tabItem { Label("Pods", systemImage: "circle.hexagongrid") }
            ReactionTestView()
                .tabItem { Label("Reaction", systemImage: "stopwatch") }
            LogView()
                .tabItem { Label("Log", systemImage: "text.alignleft") }
        }
    }
}
