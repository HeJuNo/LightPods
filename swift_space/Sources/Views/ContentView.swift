import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var bleManager = BLEManager()
    @State private var showSettings = false
    @Environment(\.modelContext) private var modelContext
    @Query private var savedPods: [SavedPod]

    var body: some View {
        TabView {
            Tab("Pods", systemImage: "circle.grid.2x2.fill") {
                NavigationStack {
                    PodsView(bleManager: bleManager)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { showSettings = true } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                }
            }
            Tab("Drills", systemImage: "bolt.fill") {
                NavigationStack {
                    DrillView(bleManager: bleManager)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { showSettings = true } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(bleManager: bleManager)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            autoReconnectSavedPods()
        }
    }

    private func autoReconnectSavedPods() {
        let infos: [(uuid: UUID, mfrData: Data?)] = savedPods.compactMap { saved in
            guard let uuid = UUID(uuidString: saved.peripheralUUID) else { return nil }
            let mfrData = saved.manufacturerDataHex.flatMap { hexToData($0) }
            return (uuid: uuid, mfrData: mfrData)
        }
        guard !infos.isEmpty else { return }
        bleManager.reconnectSavedPods(infos)
    }

    private func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard nextIndex != index else { break }
            let byteString = String(hex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data.isEmpty ? nil : data
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SavedPod.self, PodGroup.self], inMemory: true)
}
