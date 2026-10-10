import SwiftUI
import SwiftData

struct DrillView: View {
    var bleManager: BLEManager
    var drillManager: DrillManager
    @Query(sort: \PodGroup.name) private var groups: [PodGroup]
    @State private var selectedGroupID: PersistentIdentifier?

    private var authenticatedCount: Int {
        drillPods.count
    }

    private var drillPods: [PodDevice] {
        var pods = bleManager.connectedPods.filter { $0.connectionState == .authenticated }
        if let groupID = selectedGroupID,
           let group = groups.first(where: { $0.persistentModelID == groupID }),
           let groupPodUUIDs = group.pods?.map({ $0.peripheralUUID }) {
            pods = pods.filter { groupPodUUIDs.contains($0.id.uuidString) }
        }
        return pods
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                reactionTimeCard

                if !groups.isEmpty {
                    groupSelector
                }

                controlsSection

                if drillManager.totalHits > 0 {
                    statsSection
                }
            }
            .padding()
        }
        .navigationTitle("Drill")
    }

    private var reactionTimeCard: some View {
        VStack(spacing: 8) {
            if drillManager.isRunning {
                if let pod = drillManager.currentPod {
                    Text("Waiting for tap on")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(pod.name)
                        .font(.title3.bold())
                }
            }

            if let lastTime = drillManager.lastTime {
                Text("\(lastTime)")
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                Text("ms")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(drillManager.isRunning ? "Tap the lit pod!" : "Start a drill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6))
        }
    }

    private var groupSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pod Group")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    groupChip(name: "All Pods", id: nil)
                    ForEach(groups) { group in
                        groupChip(name: group.name, id: group.persistentModelID)
                    }
                }
            }
        }
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
        .disabled(drillManager.isRunning)
    }

    private var controlsSection: some View {
        VStack(spacing: 12) {
            if drillManager.isRunning {
                Button {
                    drillManager.stop()
                } label: {
                    Label("Stop Drill", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    let podIDs = Set(drillPods.map { $0.id })
                    drillManager.start(bleManager: bleManager, podIDs: podIDs)
                } label: {
                    Label("Start Random Drill", systemImage: "bolt.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(authenticatedCount == 0)

                if authenticatedCount == 0 {
                    Text("Connect and authenticate pods first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(authenticatedCount) pod(s) ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    drillManager.resetStats()
                }
                .font(.subheadline)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(title: "Hits", value: "\(drillManager.totalHits)", icon: "hand.tap.fill")
                if let mean = drillManager.meanReactionTime {
                    statCard(title: "Average", value: "\(Int(mean)) ms", icon: "chart.bar.fill")
                }
                if let best = drillManager.bestTime {
                    statCard(title: "Best", value: "\(best) ms", icon: "trophy.fill")
                }
                if let worst = drillManager.worstTime {
                    statCard(title: "Worst", value: "\(worst) ms", icon: "tortoise.fill")
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
        }
    }
}
