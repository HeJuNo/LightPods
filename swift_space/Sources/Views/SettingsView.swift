import SwiftUI
import SwiftData

struct SettingsView: View {
    var bleManager: BLEManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPod.name) private var savedPods: [SavedPod]
    @Query(sort: \PodGroup.name) private var groups: [PodGroup]
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var editingGroup: PodGroup?
    @State private var addingDevice: PodDevice?
    @State private var editingSavedPod: SavedPod?

    var body: some View {
        List {
            // MARK: - Discovered Section
            if bleManager.isScanning || !bleManager.discoveredDevices.isEmpty {
                Section {
                    if bleManager.isScanning && bleManager.discoveredDevices.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Looking for BlazePods…")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }

                    ForEach(bleManager.discoveredDevices) { device in
                        discoveredRow(device)
                    }
                } header: {
                    Text("Nearby")
                }
            }

            // MARK: - Saved Pods Section
            Section {
                if savedPods.isEmpty {
                    Text("No saved pods yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedPods, id: \.peripheralUUID) { saved in
                        Button {
                            editingSavedPod = saved
                        } label: {
                            savedPodRow(saved)
                        }
                        .tint(.primary)
                    }
                    .onDelete(perform: deleteSavedPods)
                }
            } header: {
                Text("My Pods (\(savedPods.count))")
            }

            // MARK: - Groups Section
            Section {
                ForEach(groups) { group in
                    Button {
                        editingGroup = group
                    } label: {
                        HStack {
                            Label(group.name, systemImage: "folder.fill")
                            Spacer()
                            Text("\(group.pods?.count ?? 0) pods")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    }
                    .tint(.primary)
                }
                .onDelete(perform: deleteGroups)

                Button {
                    showNewGroup = true
                } label: {
                    Label("New Group", systemImage: "plus.circle")
                }
            } header: {
                Text("Groups")
            }

            // MARK: - Auto-Detect
            Section {
                Toggle(isOn: Binding(
                    get: { bleManager.autoDetectEnabled },
                    set: { newVal in
                        bleManager.autoDetectEnabled = newVal
                        if newVal && !bleManager.isScanning {
                            bleManager.startScanning()
                        }
                    }
                )) {
                    Label("Auto-Detect Pods", systemImage: "antenna.radiowaves.left.and.right")
                }
            } footer: {
                Text("Automatically connect and save discovered BlazePods as \"Pod XXX\".")
            }

            // MARK: - Bluetooth Status
            if bleManager.bluetoothState != .poweredOn {
                Section {
                    bluetoothStatusRow
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                scanButton
            }
        }
        .alert("New Group", isPresented: $showNewGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) { newGroupName = "" }
            Button("Create") {
                let group = PodGroup(name: newGroupName)
                modelContext.insert(group)
                newGroupName = ""
            }
        }
        .sheet(item: $editingGroup) { group in
            NavigationStack {
                GroupEditView(group: group, savedPods: savedPods)
            }
        }
        .sheet(item: $addingDevice) { device in
            AddPodView(bleManager: bleManager, device: device)
        }
        .sheet(item: $editingSavedPod) { saved in
            NavigationStack {
                PodEditView(saved: saved, bleManager: bleManager)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { editingSavedPod = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Scan Button (toolbar)

    private var scanButton: some View {
        Button {
            if bleManager.isScanning {
                bleManager.stopScanning()
            } else {
                bleManager.startScanning()
            }
        } label: {
            if bleManager.isScanning {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Stop")
                }
            } else {
                Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
        .disabled(bleManager.bluetoothState != .poweredOn)
    }

    // MARK: - Discovered Row

    private func discoveredRow(_ device: PodDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                if let mfr = device.manufacturerData {
                    Text(mfr.map { String(format: "%02X", $0) }.joined())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            Spacer()
            rssiIndicator(device.rssi)
            Button {
                addingDevice = device
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Saved Pod Row

    private func savedPodRow(_ saved: SavedPod) -> some View {
        let connectedPod = bleManager.connectedPods.first {
            $0.id.uuidString == saved.peripheralUUID
        }
        return HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(statusColor(for: connectedPod))
                .frame(width: 8, height: 8)

            // Left: Name + Serial below
            VStack(alignment: .leading, spacing: 3) {
                Text(saved.displayName)
                    .font(.subheadline.weight(.medium))
                if let serial = connectedPod?.bleSerialNumber, !serial.isEmpty {
                    Text("S/N \(serial)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
            }

            Spacer()

            // Right side: battery (icon above %), status, chevron
            HStack(spacing: 12) {
                // Battery: icon above percentage
                if let pod = connectedPod, let level = pod.batteryLevel {
                    VStack(spacing: 1) {
                        Image(systemName: pod.batteryIconName)
                            .foregroundStyle(pod.batteryColor)
                            .font(.caption)
                        Text("\(level)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                // Status badge top-right
                Text(connectedPod?.connectionState.rawValue ?? "Not connected")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusTextColor(for: connectedPod))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(statusColor(for: connectedPod).opacity(0.2))
                    }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
    }

    // MARK: - Bluetooth Status

    private var bluetoothStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bluetooth")
                .font(.title2)
                .foregroundStyle(.orange)
            switch bleManager.bluetoothState {
            case .poweredOff:
                Text("Bluetooth is turned off")
            case .unauthorized:
                Text("Bluetooth permission denied")
            case .unsupported:
                Text("Bluetooth not supported")
            default:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for Bluetooth…")
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func rssiIndicator(_ rssi: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: rssi > -50 ? "wifi.circle.fill" : rssi > -70 ? "wifi.circle" : "wifi.exclamationmark.circle")
                .foregroundStyle(rssi > -50 ? .green : rssi > -70 ? .yellow : .red)
                .font(.caption)
            Text("\(rssi)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func statusColor(for pod: PodDevice?) -> Color {
        guard let pod = pod else { return .gray }
        switch pod.connectionState {
        case .authenticated: return .green
        case .connecting, .authenticating, .connected: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private func statusTextColor(for pod: PodDevice?) -> Color {
        guard let pod = pod else { return .secondary }
        switch pod.connectionState {
        case .authenticated: return .green
        case .connecting, .authenticating, .connected: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    // MARK: - Actions

    private func deleteSavedPods(at offsets: IndexSet) {
        for idx in offsets {
            let saved = savedPods[idx]
            if let pod = bleManager.connectedPods.first(where: { $0.id.uuidString == saved.peripheralUUID }) {
                bleManager.removePod(pod)
            }
            modelContext.delete(saved)
        }
    }

    private func deleteGroups(at offsets: IndexSet) {
        for idx in offsets {
            modelContext.delete(groups[idx])
        }
    }
}

// MARK: - Group Edit View

struct GroupEditView: View {
    @Bindable var group: PodGroup
    let savedPods: [SavedPod]
    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String = ""

    var body: some View {
        List {
            Section("Group Name") {
                TextField("Name", text: $editedName)
            }

            Section("Pods") {
                ForEach(savedPods, id: \.peripheralUUID) { pod in
                    let isInGroup = group.pods?.contains(where: { $0.peripheralUUID == pod.peripheralUUID }) ?? false
                    Button {
                        togglePod(pod, isInGroup: isInGroup)
                    } label: {
                        HStack {
                            Text(pod.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isInGroup {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    if !editedName.isEmpty {
                        group.name = editedName
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            editedName = group.name
        }
    }

    private func togglePod(_ pod: SavedPod, isInGroup: Bool) {
        if isInGroup {
            group.pods?.removeAll { $0.peripheralUUID == pod.peripheralUUID }
        } else {
            if group.pods == nil {
                group.pods = []
            }
            group.pods?.append(pod)
        }
    }
}
