import BlazePodDrills
import BlazePodKit
import SwiftUI

/// Configure a drill, save it, start it.
struct DrillSetupView: View {
    @EnvironmentObject private var controller: PodController
    @EnvironmentObject private var store: DrillStore

    let original: DrillDefinition
    /// Called after "save as new" so the caller can show the saved drill.
    var onSavedAsNew: (DrillDefinition) -> Void

    @State private var draft: DrillDefinition
    @State private var askName = false
    @State private var newName = ""
    @State private var running: DrillDefinition?
    @State private var savedTick = 0
    @State private var editsPods = false

    init(original: DrillDefinition, onSavedAsNew: @escaping (DrillDefinition) -> Void) {
        self.original = original
        self.onSavedAsNew = onSavedAsNew
        var d = original
        d.normalize()
        _draft = State(initialValue: d)
    }

    private var style: DrillStyle { DrillStyle(original) }
    private var isModified: Bool { draft != normalized(original) }
    private var problem: String? { draft.problem(readyPods: controller.availablePodCount) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                podCheck
                setupCard
                podsCard
                colorsCard
                playersCard
                if draft.engine == .focus { distractionCard }
                if draft.engine == .random && draft.players > 1 { competitionCard }
                lightsOutCard
                delayCard
                durationCard
                cyclesCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { promptSaveAsNew() } label: { Label("Save as New Drill…", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) {
                        withAnimation { draft = normalized(original) }
                    } label: { Label("Reset Changes", systemImage: "arrow.uturn.backward") }
                        .disabled(!isModified)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onChange(of: draft) { _, _ in
            var d = draft
            d.normalize()
            if d != draft { draft = d }
        }
        .alert("Save as New Drill", isPresented: $askName) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveAsNew() }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Your settings are saved under “My Drills”.")
        }
        .fullScreenCover(item: $running) { drill in
            DrillRunView(definition: drill, selection: store.podSelection(for: original.id))
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .sheet(isPresented: $editsPods) {
            PodSelectionView(definition: draft, initial: store.podSelection(for: original.id)) {
                store.setPodSelection($0, for: original.id)
            }
        }
        .onAppear { if Demo.autostart { running = draft } }
    }

    // MARK: Header

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            style.gradient
            Image(systemName: original.symbol)
                .font(.system(size: 150, weight: .bold))
                .foregroundStyle(.white.opacity(0.14))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 30, y: -16)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(draft.engineTitle.uppercased())
                    if !original.isBuiltIn { Text("· MY DRILL") }
                    if isModified { Text("· EDITED") }
                }
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .opacity(0.85)
                Text(draft.name).font(.largeTitle.weight(.heavy)).lineLimit(2)
                if !draft.summary.isEmpty {
                    Text(draft.summary).font(.subheadline).opacity(0.92)
                }
                HStack(spacing: 6) {
                    FactChip(symbol: "circle.hexagongrid.fill", text: draft.podsText, onGradient: true)
                    FactChip(symbol: "person.fill", text: draft.playersText, onGradient: true)
                    FactChip(symbol: "timer", text: draft.durationText, onGradient: true)
                }
                .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(minHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner + 4, style: .continuous))
        .shadow(color: style.accent.opacity(0.3), radius: 18, y: 10)
        .padding(.top, 8)
    }

    private var podCheck: some View {
        let ready = controller.availablePodCount
        let needed = draft.totalPods
        let ok = ready >= needed
        return HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(ok ? .green : .orange)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(ok ? "Ready to go" : "More pods needed").font(.headline)
                Text("\(needed) needed · \(ready) connected").font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: -8) {
                ForEach(0..<min(needed, 8), id: \.self) { i in
                    GlowPod(color: i < ready ? draft.colors(forPlayer: 0).first : nil, size: 22)
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .animation(.snappy, value: ready)
    }

    // MARK: Cards

    private var setupCard: some View {
        SettingsCard(title: "Setup", symbol: "square.grid.2x2.fill", tint: style.accent) {
            ValueStepper("Stations", caption: "Separate groups of pods, each with its own players",
                         value: $draft.stations, in: Limits.stations)
            Divider()
            ValueStepper("Pods per station", value: $draft.podsPerStation,
                         in: (draft.engine == .focus ? Limits.focusMinPods : 1)...Limits.pods.upperBound)
            Divider()
            if draft.engine == .random {
                ValueStepper("Players per station", caption: "Each player has their own colour",
                             value: $draft.players, in: 1...min(Limits.players.upperBound, draft.podsPerStation))
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Players")
                        Text("One per station. Add stations for more players.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(draft.totalPlayers)").font(.body.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private var colorsCard: some View {
        SettingsCard(title: draft.engine == .focus ? "Target Colours" : "Colours per Player",
                     symbol: "paintpalette.fill", tint: style.accent) {
            ForEach(0..<draft.playersPerStation, id: \.self) { player in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(draft.engine == .focus ? "Hit these" : draft.displayName(station: 0, index: player))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(colorCountText(draft.playerColors[safe: player]?.count ?? 1))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ColorSwatchPicker(selection: playerColors(player),
                                      excluded: draft.engine == .focus ? Set(draft.distractingColors) : [])
                }
                if player < draft.playersPerStation - 1 { Divider() }
            }
            Text("With several colours, each light picks one of them at random.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var podsCard: some View {
        let assigned = controller.assignedPods(count: draft.totalPods, selection: store.podSelection(for: original.id))
        let custom = !store.podSelection(for: original.id).isEmpty
        return SettingsCard(title: "Pods", symbol: "circle.hexagongrid.fill", tint: style.accent) {
            Text(custom ? "Your chosen pods, in station order." : "Connected pods in name order.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<draft.stations, id: \.self) { station in
                HStack(spacing: 10) {
                    if draft.stations > 1 {
                        Text("S\(station + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 24)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<draft.podsPerStation, id: \.self) { i in
                                let index = station * draft.podsPerStation + i
                                let pod = assigned[safe: index]
                                VStack(spacing: 4) {
                                    GlowPod(color: pod == nil ? nil : stationColor(station), size: 34,
                                            label: "\(i + 1)")
                                    Text(pod.map { shortName($0.name) } ?? "–")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(pod == nil ? .orange : .secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollClipDisabled()
                }
            }
            HStack(spacing: 10) {
                Button {
                    controller.flash(assigned.enumerated().map { ($0.element, stationColor($0.offset / draft.podsPerStation)) })
                } label: {
                    Label("Identify", systemImage: "lightbulb.max.fill").frame(maxWidth: .infinity)
                }
                .disabled(assigned.isEmpty)
                Button { editsPods = true } label: {
                    Label("Edit Pods", systemImage: "list.number").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(style.accent)
            .controlSize(.large)
        }
    }

    private var playersCard: some View {
        SettingsCard(title: "Player Names", symbol: "person.2.fill", tint: style.accent) {
            ForEach(0..<draft.stations, id: \.self) { station in
                ForEach(0..<draft.playersPerStation, id: \.self) { player in
                    HStack(spacing: 12) {
                        Circle().fill(draft.colors(forPlayer: player).first?.swatch ?? .gray)
                            .frame(width: 14, height: 14)
                        TextField(draft.defaultPlayerName(station: station, index: player), text: nameBinding(station, player))
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                        if draft.stations > 1 && draft.playersPerStation > 1 {
                            Text("S\(station + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func nameBinding(_ station: Int, _ player: Int) -> Binding<String> {
        Binding(get: { draft.playerName(station: station, index: player) ?? "" },
                set: { draft.setPlayerName($0, station: station, index: player) })
    }

    private func shortName(_ name: String) -> String {
        name.hasPrefix("Pod ") ? String(name.dropFirst(4)) : name
    }

    private var distractionCard: some View {
        SettingsCard(title: "Distraction", symbol: "eye.trianglebadge.exclamationmark.fill", tint: style.accent) {
            ValueStepper("Distracting pods", caption: "Lit in other colours. Don't touch them!",
                         value: $draft.distractingPods, in: 1...max(1, draft.podsPerStation - 1))
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Distracting colours").font(.subheadline.weight(.medium))
                ColorSwatchPicker(selection: $draft.distractingColors, excluded: Set(draft.colors(forPlayer: 0)))
            }
            Divider()
            Toggle(isOn: Binding(get: { draft.strikeOut != nil },
                                 set: { draft.strikeOut = $0 ? 5 : nil })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strike out")
                    Text("End the cycle after too many wrong hits").font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(style.accent)
            if draft.strikeOut != nil {
                ValueStepper("Strikes allowed", value: Binding(get: { draft.strikeOut ?? 5 },
                                                               set: { draft.strikeOut = $0 }),
                             in: Limits.strikeOut)
            }
        }
    }

    private var competitionCard: some View {
        SettingsCard(title: "Competition", symbol: "flag.checkered", tint: style.accent) {
            PillPicker(options: [
                .init(value: CompetitionMode.regular, title: "Everyone", symbol: "person.3.fill"),
                .init(value: .firstToHit, title: "First to hit", symbol: "trophy.fill"),
            ], selection: $draft.competition, tint: style.accent)
            Text(draft.competition == .regular
                 ? "Each player has their own pod and keeps going independently."
                 : "All players get a pod at once. The fastest hit wins the round.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var lightsOutCard: some View {
        var options: [PillPicker<LightsOut>.Option] = [.init(value: .hit, title: "Hit", symbol: "hand.tap.fill")]
        if draft.engine == .random {
            options.append(.init(value: .timeout, title: "Timeout", symbol: "hourglass"))
        }
        options.append(.init(value: .hitOrTimeout, title: "Hit or timeout", symbol: "hourglass.badge.plus"))
        return SettingsCard(title: "Lights Out", symbol: "lightbulb.slash.fill", tint: style.accent) {
            PillPicker(options: options, selection: $draft.lightsOut, tint: style.accent)
            if draft.lightsOut.endsOnTimeout {
                ValueStepper("Light stays on", caption: draft.lightsOut == .timeout ? nil : "Then it counts as a miss",
                             seconds: $draft.lightsOutTimeout, in: Limits.lightsOut, step: 0.25)
            }
        }
    }

    private var delayCard: some View {
        SettingsCard(title: "Light Delay", symbol: "timer", tint: style.accent) {
            PillPicker(options: [
                .init(value: DelayKind.none, title: "None", symbol: "bolt.fill"),
                .init(value: .fixed, title: "Fixed", symbol: "equal.circle.fill"),
                .init(value: .random, title: "Random", symbol: "dice.fill"),
            ], selection: delayKind, tint: style.accent)
            switch draft.lightDelay {
            case .none:
                Text("The next light comes on right away.").font(.caption).foregroundStyle(.secondary)
            case .fixed:
                ValueStepper("Pause before next light", seconds: fixedDelay, in: Limits.lightDelay, step: 0.5)
            case .random:
                ValueStepper("From", seconds: randomFrom, in: 0.5...9.5, step: 0.5)
                ValueStepper("To", seconds: randomTo, in: 1...10, step: 0.5)
            }
        }
    }

    private var durationCard: some View {
        SettingsCard(title: "Duration", symbol: "stopwatch.fill", tint: style.accent) {
            PillPicker(options: [
                .init(value: DurationKind.time, title: "Time", symbol: "clock.fill"),
                .init(value: .hits, title: "Hit count", symbol: "number"),
                .init(value: .both, title: "Time or hits", symbol: "clock.badge.checkmark.fill"),
            ], selection: durationKind, tint: style.accent)
            if draft.duration.seconds != nil {
                ValueStepper("Time", value: durationSeconds, in: Limits.durationSeconds, step: 5,
                             format: Format.clock)
            }
            if draft.duration.hits != nil {
                ValueStepper("Hits", caption: "Per player; the first to reach it ends the cycle",
                             value: durationHits, in: Limits.hitCount)
            }
        }
    }

    private var cyclesCard: some View {
        SettingsCard(title: "Cycles", symbol: "repeat", tint: style.accent) {
            ValueStepper("Cycles", value: $draft.cycles, in: Limits.cycles)
            if draft.cycles > 1 {
                Divider()
                ValueStepper("Rest between cycles", value: $draft.cycleRest, in: Limits.cycleRest, step: 5,
                             format: Format.clock)
            }
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        VStack(spacing: 10) {
            if let problem {
                Label(problem, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                if !original.isBuiltIn && isModified {
                    Button {
                        store.save(draft)
                        savedTick += 1
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 18)
                            .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if original.isBuiltIn && isModified {
                    Button { promptSaveAsNew() } label: {
                        Label("Save as New", systemImage: "plus.square.on.square")
                            .font(.headline)
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 18)
                            .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    running = draft
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(GradientButtonStyle(style: style, enabled: problem == nil))
                .disabled(problem != nil)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
        .animation(.snappy, value: isModified)
    }

    private func promptSaveAsNew() {
        newName = store.suggestedName(for: draft)
        askName = true
    }

    private func saveAsNew() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var copy = draft
        copy.summary = original.isBuiltIn ? "Based on \(original.name). \(original.summary)" : draft.summary
        copy.symbol = original.symbol
        let saved = store.saveAsNew(copy, name: name)
        savedTick += 1
        onSavedAsNew(saved)
    }

    private func normalized(_ d: DrillDefinition) -> DrillDefinition {
        var d = d
        d.normalize()
        return d
    }

    private func colorCountText(_ n: Int) -> String { n == 1 ? "1 colour" : "\(n) colours" }

    // MARK: Bindings into enum payloads

    private enum DelayKind: Hashable { case none, fixed, random }
    private enum DurationKind: Hashable { case time, hits, both }

    private func playerColors(_ player: Int) -> Binding<[PodColor]> {
        Binding(get: { draft.colors(forPlayer: player) },
                set: { colors in
                    while draft.playerColors.count <= player { draft.playerColors.append([.default]) }
                    draft.playerColors[player] = colors
                })
    }

    private var delayKind: Binding<DelayKind> {
        Binding(get: {
            switch draft.lightDelay {
            case .none: .none
            case .fixed: .fixed
            case .random: .random
            }
        }, set: { kind in
            switch kind {
            case .none: draft.lightDelay = .none
            case .fixed: draft.lightDelay = .fixed(2)
            case .random: draft.lightDelay = .random(from: 1, to: 4)
            }
        })
    }

    private var fixedDelay: Binding<Double> {
        Binding(get: { if case .fixed(let s) = draft.lightDelay { s } else { 2 } },
                set: { draft.lightDelay = .fixed($0) })
    }

    private var randomFrom: Binding<Double> {
        Binding(get: { if case .random(let f, _) = draft.lightDelay { f } else { 1 } },
                set: { from in
                    guard case .random(_, let to) = draft.lightDelay else { return }
                    draft.lightDelay = .random(from: from, to: max(to, from + 0.5))
                })
    }

    private var randomTo: Binding<Double> {
        Binding(get: { if case .random(_, let t) = draft.lightDelay { t } else { 4 } },
                set: { to in
                    guard case .random(let from, _) = draft.lightDelay else { return }
                    draft.lightDelay = .random(from: min(from, to - 0.5), to: to)
                })
    }

    private var durationKind: Binding<DurationKind> {
        Binding(get: {
            switch draft.duration {
            case .time: .time
            case .hitCount: .hits
            case .timeOrHitCount: .both
            }
        }, set: { kind in
            let s = draft.duration.seconds ?? 30
            let h = draft.duration.hits ?? 10
            switch kind {
            case .time: draft.duration = .time(seconds: s)
            case .hits: draft.duration = .hitCount(h)
            case .both: draft.duration = .timeOrHitCount(seconds: s, hits: h)
            }
        })
    }

    private var durationSeconds: Binding<Int> {
        Binding(get: { draft.duration.seconds ?? 30 },
                set: { s in
                    switch draft.duration {
                    case .time: draft.duration = .time(seconds: s)
                    case .timeOrHitCount(_, let h): draft.duration = .timeOrHitCount(seconds: s, hits: h)
                    case .hitCount: break
                    }
                })
    }

    private var durationHits: Binding<Int> {
        Binding(get: { draft.duration.hits ?? 10 },
                set: { h in
                    switch draft.duration {
                    case .hitCount: draft.duration = .hitCount(h)
                    case .timeOrHitCount(let s, _): draft.duration = .timeOrHitCount(seconds: s, hits: h)
                    case .time: break
                    }
                })
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
