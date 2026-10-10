import SwiftUI
import SwiftData

/// Full 6-section drill configuration view
struct DrillConfigView: View {
    let entry: DrillCatalog.Entry
    @Bindable var config: DrillConfiguration
    let podCount: Int
    var onStart: () -> Void
    var onSavePreset: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showSavePreset = false
    @State private var presetName = ""

    private let defaultColors: [PodColor] = [.white, .red, .green, .blue, .yellow, .purple, .orange, .cyan]

    var body: some View {
        Form {
            // Header
            drillHeader

            // Pod requirement
            podRequirementSection

            // Section 1: General Setup
            generalSetupSection

            // Section 2: Colors and Light Rules
            colorsAndRulesSection

            // Section 3: Light Delay Time
            lightDelaySection

            // Section 4: Duration
            durationSection

            // Section 5: Cycles
            cyclesSection

            // Section 6: Start Mode
            startModeSection
        }
        .navigationTitle("Configure Drill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        dismiss()
                        onStart()
                    } label: {
                        Label("Start Drill", systemImage: "play.fill")
                    }
                    .disabled(podCount < config.totalPodsNeeded)

                    Button {
                        showSavePreset = true
                    } label: {
                        Label("Save as Preset", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Text("Start")
                        .fontWeight(.semibold)
                } primaryAction: {
                    dismiss()
                    onStart()
                }
                .disabled(podCount < config.totalPodsNeeded)
            }
        }
        .alert("Save Preset", isPresented: $showSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) { presetName = "" }
            Button("Save") {
                if !presetName.isEmpty {
                    onSavePreset?(presetName)
                    presetName = ""
                }
            }
        } message: {
            Text("Save this configuration for quick access later.")
        }
    }

    // MARK: - Header

    private var drillHeader: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: entry.iconName)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.headline)
                    Text(entry.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Pod Requirement

    private var podRequirementSection: some View {
        Section {
            HStack {
                Image(systemName: "circle.grid.2x2.fill")
                    .foregroundStyle(podCount >= config.totalPodsNeeded ? Color.green : Color.red)
                Text("\(podCount) pod(s) available")
                Spacer()
                Text("\(config.totalPodsNeeded) needed")
                    .foregroundStyle(podCount >= config.totalPodsNeeded ? Color.secondary : Color.red)
            }
        }
    }

    // MARK: - Section 1: General Setup

    private var generalSetupSection: some View {
        Section("General Setup") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Light Intensity")
                    Spacer()
                    Text("\(Int(config.lightIntensity * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $config.lightIntensity, in: 0.1...1.0, step: 0.05)
            }

            Stepper("Stations: \(config.stationCount)",
                    value: $config.stationCount, in: 1...10)

            Stepper("Pods per Station: \(config.podsPerStation)",
                    value: $config.podsPerStation, in: 1...20)

            Stepper("Players per Station: \(config.playersPerStation)",
                    value: $config.playersPerStation, in: 1...10)
            .onChange(of: config.playersPerStation) { _, newValue in
                syncPlayers(count: newValue)
            }

            Picker("Competition Mode", selection: $config.competitionMode) {
                ForEach(CompetitionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        }
    }

    // MARK: - Section 2: Colors and Light Rules

    private var colorsAndRulesSection: some View {
        Section("Colors & Light Rules") {
            ForEach($config.players) { $player in
                playerRow(player: $player)
            }

            Picker("Lights Out", selection: $config.lightsOutMode) {
                ForEach(LightsOutMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if config.lightsOutMode == .timeout || config.lightsOutMode == .hitAndTimeout {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Timeout")
                        Spacer()
                        Text(formatSeconds(config.lightsOutTimeout))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.lightsOutTimeout, in: 0.25...30.0, step: 0.25)
                }
            }
        }
    }

    private func playerRow(player: Binding<PlayerConfig>) -> some View {
        HStack {
            TextField("Player Name", text: player.name)
            Spacer()
            Menu {
                ForEach(PodColor.selectableColors) { color in
                    Button {
                        player.wrappedValue.color = color.rawValue
                    } label: {
                        Label(color.displayName,
                              systemImage: player.wrappedValue.color == color.rawValue
                              ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                Circle()
                    .fill(player.wrappedValue.podColor.swiftUIColor)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: - Section 3: Light Delay Time

    private var lightDelaySection: some View {
        Section("Light Delay Time") {
            Picker("Delay Mode", selection: $config.lightDelayMode) {
                ForEach(LightDelayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if config.lightDelayMode == .fixed {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Delay")
                        Spacer()
                        Text(formatSeconds(config.lightDelayFixed))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.lightDelayFixed, in: 0.25...10.0, step: 0.25)
                }
            }

            if config.lightDelayMode == .random {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Min Delay")
                        Spacer()
                        Text(formatSeconds(config.lightDelayRandomMin))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.lightDelayRandomMin, in: 0.25...10.0, step: 0.25)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max Delay")
                        Spacer()
                        Text(formatSeconds(config.lightDelayRandomMax))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.lightDelayRandomMax,
                           in: max(0.25, config.lightDelayRandomMin)...10.0, step: 0.25)
                }
            }
        }
    }

    // MARK: - Section 4: Duration

    private var durationSection: some View {
        Section("Duration") {
            Picker("Mode", selection: $config.durationMode) {
                ForEach(DurationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if config.durationMode == .time || config.durationMode == .timeOrHitCount {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Time")
                        Spacer()
                        Text(formatMinutes(config.durationTimeMinutes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.durationTimeMinutes, in: 0.5...30.0, step: 0.5)
                }
            }

            if config.durationMode == .hitCount || config.durationMode == .timeOrHitCount {
                Stepper("Hits: \(config.durationHitCount)",
                        value: $config.durationHitCount, in: 1...100)
            }
        }
    }

    // MARK: - Section 5: Cycles

    private var cyclesSection: some View {
        Section("Cycles") {
            Stepper("Count: \(config.cycleCount)",
                    value: $config.cycleCount, in: 1...20)

            if config.cycleCount > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Rest Between Cycles")
                        Spacer()
                        Text(formatSeconds(config.timeBetweenCycles))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.timeBetweenCycles, in: 1.0...60.0, step: 1.0)
                }
            }
        }
    }

    // MARK: - Section 6: Start Mode

    private var startModeSection: some View {
        Section("Start Mode") {
            Picker("Start", selection: $config.startMode) {
                ForEach(StartMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Helpers

    private func syncPlayers(count: Int) {
        while config.players.count < count {
            let idx = config.players.count
            let color = defaultColors[idx % defaultColors.count]
            config.players.append(PlayerConfig.guest(index: idx, color: color))
        }
        while config.players.count > count {
            config.players.removeLast()
        }
    }

    private func formatSeconds(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return "\(Int(value))s"
        }
        return String(format: "%.2fs", value)
    }

    private func formatMinutes(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return "\(Int(value)) min"
        }
        return String(format: "%.1f min", value)
    }
}
