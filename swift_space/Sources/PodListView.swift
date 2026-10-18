import BlazePodKit
import SwiftUI

struct PodListView: View {
    @EnvironmentObject private var controller: PodController
    @State private var limitEnabled = false
    @State private var limit = 6

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    LabeledContent("Status") {
                        Text(controller.bluetoothOn ? "On" : "Unavailable")
                            .foregroundStyle(controller.bluetoothOn ? .green : .red)
                    }
                    Toggle("Scanning", isOn: Binding(get: { controller.isScanning }, set: controller.setScanning))
                    Picker("Intensity", selection: $controller.intensity) {
                        ForEach(LightIntensity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Charger polling (chgs, 300 ms)", isOn: $controller.chargerPolling)
                    Toggle("Pod limit", isOn: $limitEnabled)
                    if limitEnabled {
                        Stepper("Max connected pods: \(limit)", value: $limit, in: 0...12)
                    }
                }
                .onChange(of: limitEnabled) { _, _ in applyLimit() }
                .onChange(of: limit) { _, _ in applyLimit() }

                Section("Pods – \(controller.readyPods.count) ready / \(controller.pods.count) visible") {
                    if controller.pods.isEmpty {
                        Text(controller.isScanning ? "Searching… tap a pod to wake it." : "Scanning is off.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.pods, id: \.id) { pod in
                        NavigationLink(value: pod.id) { PodRow(pod: pod) }
                    }
                }

                Section("All pods") {
                    Button("Connect all visible", action: controller.connectAll)
                    Button("Disconnect all", action: controller.disconnectAll)
                    Button("Identify all (blue, 30 s)", action: controller.identifyAll)
                        .disabled(controller.readyPods.isEmpty)
                    Button("All lights off", action: controller.allOff)
                        .disabled(controller.readyPods.isEmpty)
                }
            }
            .navigationTitle("LightPods")
            .navigationDestination(for: UUID.self) { id in
                if let pod = controller.pod(id) {
                    PodDetailView(pod: pod)
                } else {
                    ContentUnavailableView("Pod gone", systemImage: "questionmark.circle")
                }
            }
        }
    }

    private func applyLimit() { controller.setMaxPods(limitEnabled ? limit : nil) }
}

struct PodRow: View {
    @EnvironmentObject private var controller: PodController
    let pod: BlazePod

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(pod.isLightOn ? (pod.currentColor?.swatch ?? .white) : pod.linkState.color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.secondary.opacity(0.4)))
            VStack(alignment: .leading, spacing: 2) {
                Text(pod.name).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(pod.intent == .connect ? "Disconnect" : "Connect") { controller.toggleConnection(pod) }
                .buttonStyle(.bordered)
        }
    }

    private var subtitle: String {
        var parts = [pod.linkState.title, "\(pod.rssi) dBm"]
        if let b = pod.battery ?? pod.advertisement?.batteryPercent { parts.append("\(b)%") }
        if pod.charger?.isOnCharger == true || pod.advertisement?.isCharging == true { parts.append("⚡︎") }
        if pod.connectAttempts > 0 && pod.linkState != .ready { parts.append("retry \(pod.connectAttempts)") }
        return parts.joined(separator: " · ")
    }
}
