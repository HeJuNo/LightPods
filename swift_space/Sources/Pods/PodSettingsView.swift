import BlazePodKit
import SwiftUI

/// Toolbar button: number of connected pods; opens pod settings.
struct PodStatusButton: View {
    @EnvironmentObject private var controller: PodController
    let action: () -> Void

    var body: some View {
        let ready = controller.readyPods.count
        let connecting = !controller.connectingPods.isEmpty
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(ready > 0 ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    if connecting {
                        Circle()
                            .stroke(Color.orange, lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                            .phaseAnimator([0.4, 1]) { view, phase in view.opacity(phase) }
                    }
                }
                .frame(width: 14, height: 14)
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.subheadline)
                Text("\(ready)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)
            .animation(.snappy, value: ready)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ready) pods connected. Pod settings")
    }
}

/// Pod pairing and information.
struct PodSettingsView: View {
    @EnvironmentObject private var controller: PodController
    @Environment(\.dismiss) private var dismiss
    @State private var limitEnabled = false
    @State private var limit = 6

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    Toggle(isOn: $controller.autoConnectAll) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-connect")
                                Text("Connects your pods and any new pod that is switched on nearby.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .tint(.green)
                }

                Section {
                    if controller.myPods.isEmpty {
                        Text("No pods yet. Switch a pod on and add it below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.myPods) { known in
                        if let pod = known.pod {
                            NavigationLink(value: pod.id) { PodRow(pod: pod) }
                                .swipeActions {
                                    Button("Forget", role: .destructive) { controller.forget(known.id) }
                                }
                        } else {
                            OfflinePodRow(known: known)
                                .swipeActions {
                                    Button("Forget", role: .destructive) { controller.forget(known.id) }
                                }
                        }
                    }
                } header: {
                    Text("My Pods")
                } footer: {
                    Text("Pods connect in name order, so place them in that order for multi-station drills.")
                }

                Section {
                    ForEach(controller.nearbyPods, id: \.id) { pod in
                        PodRow(pod: pod, showsAdd: true)
                    }
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(controller.bluetoothOn ? "Searching… press a pod to switch it on." : "Turn on Bluetooth to find pods.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Nearby")
                }

                Section("All Pods") {
                    Button { controller.identifyAll() } label: {
                        Label("Identify all (30 s)", systemImage: "lightbulb.max.fill")
                    }
                    .disabled(controller.readyPods.isEmpty)
                    Button { controller.allOff() } label: {
                        Label("All lights off", systemImage: "lightbulb.slash")
                    }
                    .disabled(controller.readyPods.isEmpty)
                    Button(role: .destructive) { controller.disconnectAll() } label: {
                        Label("Disconnect all", systemImage: "xmark.circle")
                    }
                    .disabled(controller.readyPods.isEmpty && controller.connectingPods.isEmpty)
                }

                Section("Light") {
                    Picker("Brightness", selection: $controller.intensity) {
                        Text("Low").tag(LightIntensity.low)
                        Text("Medium").tag(LightIntensity.medium)
                        Text("High").tag(LightIntensity.max)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Advanced") {
                    Toggle("Limit connected pods", isOn: $limitEnabled)
                    if limitEnabled {
                        Stepper("Max pods: \(limit)", value: $limit, in: 1...24)
                    }
                    Toggle("Poll charger status", isOn: $controller.chargerPolling)
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Bluetooth log", systemImage: "waveform.path.ecg.text")
                    }
                }
                .onChange(of: limitEnabled) { _, _ in applyLimit() }
                .onChange(of: limit) { _, _ in applyLimit() }
            }
            .navigationTitle("Pods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let pod = controller.pod(id) {
                    PodDetailView(pod: pod)
                } else {
                    ContentUnavailableView("Pod not nearby", systemImage: "antenna.radiowaves.left.and.right.slash")
                }
            }
        }
    }

    private var header: some View {
        let ready = controller.readyPods
        return VStack(spacing: 14) {
            ZStack {
                ForEach(Array(0..<5), id: \.self) { i in
                    GlowPod(color: i < ready.count ? PodColor.assignmentOrder[i % 8] : nil, size: 46)
                        .offset(x: CGFloat(i - 2) * 38, y: i.isMultiple(of: 2) ? 0 : 14)
                }
            }
            .frame(height: 70)
            Text(ready.isEmpty ? "No pods connected" : "\(ready.count) pod\(ready.count == 1 ? "" : "s") connected")
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                FactChip(symbol: controller.bluetoothOn ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle.fill",
                         text: controller.bluetoothOn ? "Bluetooth on" : "Bluetooth off")
                if !controller.connectingPods.isEmpty {
                    FactChip(symbol: "arrow.triangle.2.circlepath", text: "\(controller.connectingPods.count) connecting")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .animation(.snappy, value: ready.count)
    }

    private func applyLimit() { controller.setMaxPods(limitEnabled ? limit : nil) }
}

struct PodRow: View {
    @EnvironmentObject private var controller: PodController
    let pod: BlazePod
    var showsAdd = false

    var body: some View {
        HStack(spacing: 14) {
            GlowPod(color: pod.isLightOn ? pod.currentColor : nil, size: 40)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(pod.statusColor).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(pod.name).font(.headline)
                HStack(spacing: 8) {
                    Text(pod.statusText).foregroundStyle(pod.statusColor)
                    SignalBars(bars: pod.signalBars)
                    if let level = pod.batteryLevel {
                        BatteryBadge(level: level, charging: pod.isCharging)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 4)
            if showsAdd {
                Button("Add") { controller.connect(pod) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            } else if pod.isReady {
                Button { controller.identify(pod) } label: {
                    Image(systemName: "lightbulb.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .accessibilityLabel("Identify \(pod.name)")
            } else if pod.intent != .connect, pod.isVisible {
                Button("Connect") { controller.connect(pod) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

struct OfflinePodRow: View {
    let known: KnownPod

    var body: some View {
        HStack(spacing: 14) {
            GlowPod(color: nil, size: 40).opacity(0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(known.name).font(.headline).foregroundStyle(.secondary)
                Text(known.lastConnected.map { "Not nearby · last used \($0.formatted(.relative(presentation: .named)))" }
                    ?? "Not nearby")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SignalBars: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityLabel("Signal \(bars) of 3")
    }
}

struct BatteryBadge: View {
    let level: Int
    let charging: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: charging ? "battery.100percent.bolt" : symbol)
                .foregroundStyle(level <= 15 && !charging ? .red : .secondary)
            Text("\(level)%").monospacedDigit()
        }
    }

    private var symbol: String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
