import SwiftUI
import SwiftData

struct PodsView: View {
    var bleManager: BLEManager
    @Query(sort: \PodGroup.name) private var groups: [PodGroup]
    @State private var selectedGroupID: PersistentIdentifier?

    private var displayedPods: [PodDevice] {
        if let groupID = selectedGroupID,
           let group = groups.first(where: { $0.persistentModelID == groupID }),
           let groupPodUUIDs = group.pods?.map({ $0.peripheralUUID }) {
            return bleManager.connectedPods.filter { groupPodUUIDs.contains($0.id.uuidString) }
        }
        return bleManager.connectedPods
    }

    var body: some View {
        Group {
            if bleManager.connectedPods.isEmpty {
                ContentUnavailableView {
                    Label("No Pods", systemImage: "circle.grid.2x2")
                } description: {
                    Text("Tap the gear icon to scan and add BlazePods.")
                }
            } else {
                VStack(spacing: 0) {
                    if !groups.isEmpty {
                        groupPicker
                    }
                    List {
                        ForEach(displayedPods) { pod in
                            PodCardView(pod: pod, bleManager: bleManager)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Pods (\(displayedPods.count))")
    }

    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                groupChip(name: "All", id: nil)
                ForEach(groups) { group in
                    groupChip(name: group.name, id: group.persistentModelID)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private func groupChip(name: String, id: PersistentIdentifier?) -> some View {
        let isSelected = selectedGroupID == id
        return Button {
            selectedGroupID = id
        } label: {
            Text(name)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(.systemGray5))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

struct PodCardView: View {
    var pod: PodDevice
    var bleManager: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pod.name)
                        .font(.headline)
                    statusBadge
                }
                Spacer()
                if let ms = pod.lastReactionTimeMs {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(ms) ms")
                            .font(.title2.monospacedDigit().bold())
                        Text("Last tap")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\u{2014}")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            if pod.connectionState == .authenticated {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PodColor.selectableColors) { color in
                            Button {
                                pod.selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if pod.selectedColor == color {
                                            Circle()
                                                .strokeBorder(.white, lineWidth: 3)
                                        }
                                    }
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        bleManager.lightUp(pod, color: pod.selectedColor)
                    } label: {
                        Label("Light Up", systemImage: "lightbulb.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(pod.selectedColor.swiftUIColor == .white ? .gray : pod.selectedColor.swiftUIColor)

                    Button {
                        bleManager.turnOff(pod)
                    } label: {
                        Label("Off", systemImage: "lightbulb.slash")
                    }
                    .buttonStyle(.bordered)
                }
            } else if pod.connectionState == .disconnected {
                HStack(spacing: 12) {
                    Button {
                        bleManager.reconnectPod(pod)
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if pod.connectionState == .error {
                if let msg = pod.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    bleManager.reconnectPod(pod)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(pod.connectionState.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(pod.connectionState.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch pod.connectionState {
        case .disconnected: return .gray
        case .connecting, .authenticating: return .orange
        case .connected: return .yellow
        case .authenticated: return .green
        case .error: return .red
        }
    }
}
