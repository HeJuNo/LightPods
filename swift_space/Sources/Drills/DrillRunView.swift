import BlazePodDrills
import BlazePodKit
import SwiftUI

/// Full-screen live view of a running drill; turns into the results when it ends.
struct DrillRunView: View {
    @EnvironmentObject private var controller: PodController
    @Environment(\.dismiss) private var dismiss
    let definition: DrillDefinition

    @State private var runner: DrillRunner?
    @State private var confirmStop = false

    var body: some View {
        ZStack {
            Theme.runBackground.ignoresSafeArea()
            if let runner {
                RunContent(runner: runner, confirmStop: $confirmStop, onClose: close, onAgain: restart)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if runner == nil { restart() } }
        .onDisappear { runner?.stop() }
        .statusBarHidden()
    }

    private func restart() {
        runner?.stop()
        let r = DrillRunner(definition: definition, controller: controller)
        runner = r
        r.start()
    }

    private func close() {
        runner?.stop()
        dismiss()
    }
}

private struct RunContent: View {
    @ObservedObject var runner: DrillRunner
    @Binding var confirmStop: Bool
    let onClose: () -> Void
    let onAgain: () -> Void

    private var session: DrillSession { runner.session }
    private var style: DrillStyle { DrillStyle(runner.definition) }

    var body: some View {
        if runner.phase == .finished {
            DrillResultsView(definition: runner.definition, players: session.players,
                             stoppedEarly: session.stoppedEarly, nameFor: playerName,
                             onAgain: onAgain, onDone: onClose)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            live
                .transition(.opacity)
        }
    }

    private var live: some View {
        ZStack {
            // Ambient glow in the drill's colours.
            RadialGradient(colors: [style.accent.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                topBar
                Spacer(minLength: 0)
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    HeroRing(session: session, style: style, date: context.date)
                }
                .frame(height: 260)
                Spacer(minLength: 0)
                PodMap(runner: runner)
                Scoreboard(session: session, nameFor: playerName)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.impact(weight: .medium), trigger: runner.hitTick)
        .sensoryFeedback(.error, trigger: runner.strikeTick)
        .confirmationDialog("End the drill?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("End and show results", role: .destructive) { withAnimation { runner.stop() } }
            Button("Discard and close", role: .destructive, action: onClose)
        }
        .overlay(alignment: .top) {
            if let lost = runner.lostPod {
                Label("\(lost) disconnected", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.orange, in: Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: runner.lostPod)
    }

    private var topBar: some View {
        HStack {
            Button { confirmStop = true } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("End drill")
            Spacer()
            VStack(spacing: 2) {
                Text(runner.definition.name).font(.headline)
                if runner.definition.cycles > 1 {
                    CycleDots(total: runner.definition.cycles, current: currentCycle, style: style)
                }
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 8)
    }

    private var currentCycle: Int {
        switch session.phase {
        case .running(let c): c
        case .resting(let next): next - 1
        case .finished: runner.definition.cycles
        default: 0
        }
    }

    private func playerName(_ player: DrillPlayer) -> String {
        let def = runner.definition
        if def.stations == 1 { return def.playersPerStation == 1 ? "You" : "Player \(player.index + 1)" }
        if def.playersPerStation == 1 { return "Station \(player.station + 1)" }
        return "S\(player.station + 1) · P\(player.index + 1)"
    }
}

/// Countdown / timer / rest in one big ring.
private struct HeroRing: View {
    let session: DrillSession
    let style: DrillStyle
    /// Changes every frame so SwiftUI re-reads the session's clock.
    let date: Date

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 18)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: style.colors + [style.colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: style.accent.opacity(0.7), radius: 12)
            center
        }
        .padding(8)
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder private var center: some View {
        switch session.phase {
        case .ready:
            Text("Get ready").font(.title.weight(.bold))
        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(countsDown: true))
                .id(n)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
        case .running:
            VStack(spacing: 4) {
                if let remaining = session.cycleRemaining {
                    Text(Format.timer(remaining))
                        .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                    Text(remaining <= 5 ? "Last seconds!" : "remaining")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(remaining <= 5 ? style.accent : .white.opacity(0.6))
                } else {
                    Text("\(topHits)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("of \(session.definition.duration.hits ?? 0) hits · \(Format.timer(session.cycleElapsed))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        case .resting(let next):
            VStack(spacing: 4) {
                Text("Rest").font(.title2.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                Text(Format.timer(session.restRemaining ?? 0))
                    .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                Text("Next: cycle \(next)").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            }
        case .finished:
            Image(systemName: "flag.checkered").font(.system(size: 64))
        }
    }

    private var topHits: Int {
        guard let cycle = session.currentCycle else { return 0 }
        return session.players.map { $0.stats.hits(inCycle: cycle) }.max() ?? 0
    }

    private var progress: CGFloat {
        switch session.phase {
        case .countdown(let n): return CGFloat(n) / 3
        case .running:
            if let total = session.definition.duration.seconds {
                return CGFloat(min(1, session.cycleElapsed / Double(total)))
            }
            let target = Double(session.definition.duration.hits ?? 1)
            return CGFloat(min(1, Double(topHits) / target))
        case .resting:
            let rest = Double(session.definition.cycleRest)
            return CGFloat(rest > 0 ? (session.restRemaining ?? 0) / rest : 0)
        case .finished: return 1
        case .ready: return 0
        }
    }
}

private struct CycleDots: View {
    let total: Int
    let current: Int
    let style: DrillStyle

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? AnyShapeStyle(style.gradient) : AnyShapeStyle(.white.opacity(0.2)))
                    .frame(width: i == current ? 18 : 8, height: 6)
            }
        }
        .animation(.snappy, value: current)
    }
}

/// The pods as they are lit right now, grouped by station.
private struct PodMap: View {
    @ObservedObject var runner: DrillRunner

    var body: some View {
        let def = runner.definition
        let size: CGFloat = def.podsPerStation > 8 ? 26 : def.podsPerStation > 5 ? 34 : 44
        VStack(spacing: 10) {
            ForEach(0..<def.stations, id: \.self) { station in
                HStack(spacing: 10) {
                    if def.stations > 1 {
                        Text("S\(station + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 24)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<def.podsPerStation, id: \.self) { i in
                                let pod = station * def.podsPerStation + i
                                GlowPod(color: runner.session.litPods[pod], size: size, label: runner.podLabel(pod))
                            }
                        }
                        .padding(.vertical, size * 0.3)
                        .padding(.horizontal, size * 0.3)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollClipDisabled()
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .frame(maxHeight: 220)
    }
}

private struct Scoreboard: View {
    let session: DrillSession
    let nameFor: (DrillPlayer) -> String

    var body: some View {
        let players = session.players
        let columns = players.count == 1 ? 1 : 2
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(players) { player in
                    PlayerTile(player: player, name: nameFor(player), big: players.count == 1,
                               showsStrikes: session.definition.engine == .focus)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: players.count > 4 ? 260 : nil)
        .fixedSize(horizontal: false, vertical: players.count <= 4)
    }
}

private struct PlayerTile: View {
    let player: DrillPlayer
    let name: String
    let big: Bool
    let showsStrikes: Bool
    @State private var flash = false

    var body: some View {
        let color = player.primaryColor.swatch
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ForEach(player.colors, id: \.self) { c in
                        Circle().fill(c.swatch).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Theme.runBackground, lineWidth: 1.5))
                    }
                }
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if let last = player.stats.hits.last?.reactionMs {
                    Text("\(last) ms")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color.opacity(0.25), in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(player.stats.hitCount)")
                    .font(.system(size: big ? 56 : 40, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("hits").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("avg \(Format.ms(player.stats.averageMs))")
                    if showsStrikes {
                        Text("\(player.stats.strikes) strikes").foregroundStyle(player.stats.strikes > 0 ? .red : .white.opacity(0.5))
                    } else if player.stats.misses > 0 {
                        Text("\(player.stats.misses) missed")
                    }
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.07))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(flash ? 0.95 : 0.25), lineWidth: flash ? 3 : 1)
                .shadow(color: color.opacity(flash ? 0.8 : 0), radius: 12)
        }
        .animation(.snappy, value: player.stats.hitCount)
        .onChange(of: player.stats.hitCount) { _, _ in
            flash = true
            withAnimation(.easeOut(duration: 0.45).delay(0.05)) { flash = false }
        }
    }
}
