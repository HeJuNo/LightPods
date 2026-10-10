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

    var body: some View {
        List {
            // MARK: - Scan Section
            Section {
                scanContent
            } header: {
                Text("Scan for BlazePods")
            }

            // MARK: - Saved Pods Section
            Section {
                if savedPods.isEmpty {
                    Text("No saved pods yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedPods, id: \.peripheralUUID) { saved in
                        savedPodRow(saved)
                    }
                    .onDelete(perform: deleteSavedPods)
                }
            } header: {
                Text("Saved Pods (\(savedPods.count))")
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
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
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
    }

    // MARK: - Scan Content
    @ViewBuilder
    private var scanContent: some View {
        if bleManager.bluetoothState != .poweredOn {
            bluetoothStatusRow
        } else {
            HStack {
                Button {
                    if bleManager.isScanning {
                        bleManager.stopScanning()
                    } else {
                        bleManager.startScanning()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if bleManager.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(bleManager.isScanning ? "Stop" : "Scan")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                if bleManager.isScanning {
                    Text("Searching…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if bleManager.isScanning && bleManager.discoveredDevices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for BlazePods…")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 8)
            }

            ForEach(bleManager.discoveredDevices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.subheadline.weight(.medium))
                        if let mfr = device.manufacturerData {
                            Text(mfr.map { String(format: "%02X", $0) }.joined(separator: " "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospaced()
                        }
                    }
                    Spacer()
                    rssiIndicator(device.rssi)
                    Button("Add") {
                        addPod(device)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
    }

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

    // MARK: - Saved Pod Row
    private func savedPodRow(_ saved: SavedPod) -> some View {
        let connectedPod = bleManager.connectedPods.first {
            $0.id.uuidString == saved.peripheralUUID
        }
        return HStack {
            Circle()
                .fill(statusColor(for: connectedPod))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.name)
                    .font(.subheadline.weight(.medium))
                Text(connectedPod?.connectionState.rawValue ?? "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let groups = saved.groups, !groups.isEmpty {
                Text(groups.map { $0.name }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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

    // MARK: - Actions
    private func addPod(_ device: PodDevice) {
        bleManager.connectPod(device)
        // Save to SwiftData
        let existing = savedPods.first { $0.peripheralUUID == device.id.uuidString }
        if existing == nil {
            let saved = SavedPod(
                peripheralUUID: device.id.uuidString,
                name: device.name,
                manufacturerDataHex: device.manufacturerDataHex
            )
            modelContext.insert(saved)
        } else {
            existing?.name = device.name
            if let hex = device.manufacturerDataHex {
                existing?.manufacturerDataHex = hex
            }
        }
    }

    private func deleteSavedPods(at offsets: IndexSet) {
        for idx in offsets {
            let saved = savedPods[idx]
            // Disconnect if connected
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
                            Text(pod.name)
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
