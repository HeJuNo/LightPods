import SwiftUI
import SwiftData

struct DrillView: View {
    var bleManager: BLEManager
    @Query(sort: \PodGroup.name) private var groups: [PodGroup]
    @Query(sort: \DrillPreset.createdAt) private var presets: [DrillPreset]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedGroupID: PersistentIdentifier?
    @State private var drillEngine: DrillEngine?
    @State private var selectedDrillEntry: DrillCatalog.Entry?
    @State private var drillConfig = DrillConfiguration()
    @State private var showDrillConfig = false
    @State private var lastDrillStats: DrillStats?

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

                    // Presets
                    if !presets.isEmpty {
                        presetsSection
                    }

                    // Drill catalog
                    drillCatalogList
                }

                // Last drill results
                if let stats = lastDrillStats, stats.attempts > 0 {
                    statsView(stats: stats)
                }
            }
            .padding()
        }
        .navigationTitle("Drills")
        .sheet(isPresented: $showDrillConfig) {
            if let entry = selectedDrillEntry {
                NavigationStack {
                    DrillConfigView(
                        entry: entry,
                        config: drillConfig,
                        podCount: authenticatedPods.count,
                        onStart: { startDrill(entry: entry) },
                        onSavePreset: { name in savePreset(name: name, entryID: entry.id) }
                    )
                }
            }
        }
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

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets")
                .font(.headline)

            ForEach(presets) { preset in
                presetRow(preset)
            }
        }
    }

    private func presetRow(_ preset: DrillPreset) -> some View {
        let entry = DrillCatalog.all.first { $0.id == preset.drillTypeID }
        return Button {
            if let entry {
                selectedDrillEntry = entry
                drillConfig = preset.loadConfig()
                showDrillConfig = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry?.iconName ?? "star.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.subheadline.weight(.medium))
                    Text(entry?.name ?? "Unknown drill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            }
        }
        .tint(.primary)
        .contextMenu {
            Button(role: .destructive) {
                modelContext.delete(preset)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
            selectedDrillEntry = entry
            drillConfig = DrillConfiguration()
            showDrillConfig = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: entry.iconName)
                    .font(.title2)
                    .foregroundStyle(hasPods ? .blue : .secondary)
                    .frame(width: 44, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(hasPods ? Color.blue.opacity(0.15) : Color(.systemGray5))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(hasPods ? .primary : .secondary)
                    Text(entry.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(entry.minPods)\(entry.maxPods.map { $0 == entry.minPods ? "" : "-\($0)" } ?? "+")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "circle.grid.2x2")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
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
                lastDrillStats = drill.stats
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
            // Cycle indicator
            if stats.totalCycles > 1 {
                Text("Cycle \(stats.currentCycle) of \(stats.totalCycles)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

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

            // Per-player live scores (multi-player)
            if stats.hasMultiplePlayers {
                Divider().padding(.horizontal)
                playerScoreboard(stats: stats)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6))
        }
    }

    private func playerScoreboard(stats: DrillStats) -> some View {
        VStack(spacing: 8) {
            ForEach(stats.playerStats) { ps in
                HStack(spacing: 10) {
                    Circle()
                        .fill(ps.playerColor.swiftUIColor)
                        .frame(width: 12, height: 12)
                    Text(ps.playerName)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(ps.hits)")
                        .font(.subheadline.bold().monospacedDigit())
                    Text("hits")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let best = ps.bestMs {
                        Text("\(best)ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
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

            // Per-player breakdown
            if stats.hasMultiplePlayers {
                Divider()
                playerResultsBreakdown(stats: stats)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        }
    }

    private func playerResultsBreakdown(stats: DrillStats) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Player Breakdown")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            ForEach(stats.playerStats.sorted(by: { $0.hits > $1.hits })) { ps in
                HStack(spacing: 10) {
                    // Rank medal for top player
                    if ps.id == stats.playerStats.sorted(by: { $0.hits > $1.hits }).first?.id {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }

                    Circle()
                        .fill(ps.playerColor.swiftUIColor)
                        .frame(width: 14, height: 14)

                    Text(ps.playerName)
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("\(ps.hits) hits")
                                .font(.subheadline.bold().monospacedDigit())
                            if ps.attempts > 0 {
                                Text("\(Int(ps.accuracy * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            if let best = ps.bestMs {
                                Text("Best: \(best)ms")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if ps.hits > 0 {
                                Text("Avg: \(Int(ps.meanMs))ms")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                }
            }
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
        let drill = entry.factory(drillConfig)
        engine.start(drill)
    }

    private func savePreset(name: String, entryID: String) {
        let preset = DrillPreset(name: name, drillTypeID: entryID)
        preset.saveConfig(drillConfig)
        modelContext.insert(preset)
    }
}
