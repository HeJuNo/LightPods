import SwiftUI

struct PodsView: View {
    var bleManager: BLEManager
    
    var body: some View {
        Group {
            if bleManager.connectedPods.isEmpty {
                ContentUnavailableView {
                    Label("No Pods", systemImage: "circle.grid.2x2")
                } description: {
                    Text("Add pods from the Scan tab to control them here.")
                }
            } else {
                List {
                    ForEach(bleManager.connectedPods) { pod in
                        PodCardView(pod: pod, bleManager: bleManager)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Pods (\(bleManager.connectedPods.count))")
    }
}

struct PodCardView: View {
    var pod: PodDevice
    var bleManager: BLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
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
                    Text("—")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if pod.connectionState == .authenticated {
                // Color picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PodColor.allCases) { color in
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
                
                // Actions
                HStack(spacing: 12) {
                    Button {
                        bleManager.lightUp(pod, color: pod.selectedColor)
                    } label: {
                        Label("Light Up", systemImage: "lightbulb.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(pod.selectedColor.swiftUIColor == .white ? .gray : pod.selectedColor.swiftUIColor)
                    
                    Button(role: .destructive) {
                        bleManager.disconnectPod(pod)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
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
                    
                    Button(role: .destructive) {
                        bleManager.removePod(pod)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
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
