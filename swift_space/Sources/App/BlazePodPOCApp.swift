import SwiftUI
import SwiftData

@main
struct BlazePodPOCApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [SavedPod.self, PodGroup.self])
    }
}
