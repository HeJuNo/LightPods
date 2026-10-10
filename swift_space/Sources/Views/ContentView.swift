import SwiftUI

struct ContentView: View {
    @State private var bleManager = BLEManager()
    @State private var drillManager = DrillManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Scan", systemImage: "antenna.radiowaves.left.and.right", value: 0) {
                NavigationStack {
                    ScanView(bleManager: bleManager)
                }
            }
            Tab("Pods", systemImage: "circle.grid.2x2.fill", value: 1) {
                NavigationStack {
                    PodsView(bleManager: bleManager)
                }
            }
            Tab("Drill", systemImage: "bolt.fill", value: 2) {
                NavigationStack {
                    DrillView(bleManager: bleManager, drillManager: drillManager)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
