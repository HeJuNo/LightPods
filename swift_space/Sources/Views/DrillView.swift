import SwiftUI
import SwiftData

struct DrillView: View {
    var bleManager: BLEManager
    @Query(sort: \PodGroup.name) private var groups: [PodGroup]
    @State private var selectedGroupID: PersistentIdentifier?
    @State private var drillEngine: DrillEngine?
    @State private var selectedDrillEntry: DrillCatalog.Entry?

    private var authenticatedPods: [PodDevice] {
        var pods = bleManager.authenticatedPods
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
                if let engine = drillEngine, engine.isRunning, let drill = engine.currentDrill {
                    activeDrillView(drill: drill, engine: engine)
                } else {
                    // Status
                    podStatusBar

                    if !groups.isEmpty {
                        groupSelector
                    }

                    // Drill catalog
                    drillCatalogList
                }

                // Last drill results
                if let engine = drillEngine, !engine.isRunning, let drill = engine.currentDrill {
                    statsView(stats: drill.stats)
                } else if let engine = drillEngine, let drill = engine.currentDrill, drill.stats.attempts > 0 {
                    statsView(stats: drill.stats)
                }
            }
            .padding()
        }
        .navigationTitle("Drills")
    }

    // MARK: - Pod Status

    private var podStatusBar: some View {
        HStack {
            Image(systemName: "circle.grid.2x2.fill")
                .foregroundStyle(authenticatedPods.isEmpty ? Color.secondary : Color.green)
            Text("\(authenticatedPods.count) pod(s) ready")
                .font(.subheadline)
                .foregroundStyle(authenticatedPods.isEmpty ? .secondary : .primary)
            Spacer()
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        }
    }

    // MARK: - Group Selector

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
        .disabled(drillEngine?.isRunning == true)
    }

    // MARK: - Drill Catalog

    private var drillCatalogList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a Drill")
                .font(.headline)

            ForEach(DrillCatalog.all) { entry in
                drillCard(entry: entry)
            }
        }
    }

    private func drillCard(entry: DrillCatalog.Entry) -> some View {
        let hasPods = authenticatedPods.count >= entry.minPods
        return Button {
            startDrill(entry: entry)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: entry.iconName)
                    .font(.title2)
                    .foregroundStyle(hasPods ? .blue : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(hasPods ? .primary : .secondary)
                    Text(entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.minPods)\(entry.maxPods.map { $0 == entry.minPods ? "" : "-\($0)" } ?? "+") pods")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray6))
            }
        }
        .disabled(!hasPods)
    }

    // MARK: - Active Drill

    private func activeDrillView(drill: any Drill, engine: DrillEngine) -> some View {
        VStack(spacing: 20) {
            // Drill header
            HStack {
                Image(systemName: drill.iconName)
                    .font(.title2)
                Text(drill.name)
                    .font(.title2.bold())
                Spacer()
            }

            // Live stats
            liveStatsCard(stats: drill.stats)

            // Stop button
            Button {
                engine.stop()
            } label: {
                Label("Stop Drill", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func liveStatsCard(stats: DrillStats) -> some View {
        VStack(spacing: 12) {
            // Last reaction time
            if let last = stats.lastMs {
                Text("\(last)")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                Text("ms")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("\u{2014}")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("Tap the lit pod!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                miniStat(label: "Hits", value: "\(stats.hits)")
                miniStat(label: "Misses", value: "\(stats.misses)")
                if let best = stats.bestMs {
                    miniStat(label: "Best", value: "\(best)ms")
                }
                if stats.hits > 1 {
                    miniStat(label: "Avg", value: "\(Int(stats.meanMs))ms")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6))
        }
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats (post-drill)

    private func statsView(stats: DrillStats) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Results: \(stats.drillName)")
                    .font(.headline)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(title: "Hits", value: "\(stats.hits)", icon: "hand.tap.fill")
                statCard(title: "Misses", value: "\(stats.misses)", icon: "xmark.circle")
                if let best = stats.bestMs {
                    statCard(title: "Best", value: "\(best) ms", icon: "trophy.fill")
                }
                if stats.hits > 0 {
                    statCard(title: "Average", value: "\(Int(stats.meanMs)) ms", icon: "chart.bar.fill")
                }
                if let worst = stats.worstMs {
                    statCard(title: "Worst", value: "\(worst) ms", icon: "tortoise.fill")
                }
                if stats.attempts > 0 {
                    statCard(title: "Accuracy", value: "\(Int(stats.accuracy * 100))%", icon: "target")
                }
            }

            if stats.totalTimeMs > 0 {
                Text("Duration: \(String(format: "%.1f", Double(stats.totalTimeMs) / 1000.0))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Actions

    private func startDrill(entry: DrillCatalog.Entry) {
        let pods = authenticatedPods
        let engine = DrillEngine(bleManager: bleManager, pods: pods)
        self.drillEngine = engine
        let drill = entry.factory()
        engine.start(drill)
    }
}
