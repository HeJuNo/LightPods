import BlazePodDrills
import BlazePodKit
import Charts
import SwiftUI

struct DrillResultsView: View {
    let definition: DrillDefinition
    let players: [DrillPlayer]
    let stoppedEarly: Bool
    let nameFor: (DrillPlayer) -> String
    let onAgain: () -> Void
    let onDone: () -> Void

    @State private var appeared = false

    private var style: DrillStyle { DrillStyle(definition) }
    private var allHits: [Int] { players.flatMap { $0.stats.hits.map(\.reactionMs) } }
    private var winner: DrillPlayer? {
        guard players.count > 1 else { return nil }
        return players.max { ($0.stats.hitCount, -($0.stats.averageMs ?? .max)) < ($1.stats.hitCount, -($1.stats.averageMs ?? .max)) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                totals
                if let winner, winner.stats.hitCount > 0 { winnerCard(winner) }
                ForEach(players) { player in
                    PlayerResultCard(player: player, name: nameFor(player), definition: definition)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background {
            RadialGradient(colors: [style.accent.opacity(0.45), .clear], center: .top, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: onAgain) {
                    Label("Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GradientButtonStyle(style: style))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .foregroundStyle(.white)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.35)) { appeared = true } }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: stoppedEarly ? "flag.fill" : "trophy.fill")
                .font(.system(size: 54))
                .foregroundStyle(style.gradient)
                .shadow(color: style.accent.opacity(0.8), radius: 18)
                .scaleEffect(appeared ? 1 : 0.4)
                .symbolEffect(.bounce, value: appeared)
            Text(stoppedEarly ? "Drill ended" : "Great work!")
                .font(.largeTitle.weight(.heavy))
            Text(definition.name).font(.headline).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.bottom, 4)
    }

    private var totals: some View {
        HStack(spacing: 12) {
            StatTile(title: "Hits", value: "\(allHits.count)", symbol: "hand.tap.fill", style: style)
            StatTile(title: "Average", value: allHits.isEmpty ? "–" : "\(allHits.reduce(0, +) / allHits.count)",
                     unit: allHits.isEmpty ? nil : "ms", symbol: "gauge.with.dots.needle.50percent", style: style)
            StatTile(title: "Best", value: allHits.min().map(String.init) ?? "–",
                     unit: allHits.isEmpty ? nil : "ms", symbol: "bolt.fill", style: style)
        }
    }

    private func winnerCard(_ player: DrillPlayer) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "crown.fill").font(.title).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(nameFor(player)) wins").font(.headline)
                Text("\(player.stats.hitCount) hits · avg \(Format.ms(player.stats.averageMs))")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Circle().fill(player.primaryColor.swatch).frame(width: 22, height: 22)
                .shadow(color: player.primaryColor.swatch, radius: 8)
        }
        .padding(16)
        .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.yellow.opacity(0.4)))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var unit: String?
    let symbol: String
    let style: DrillStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(style.accent)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.title.weight(.heavy).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                if let unit { Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6)) }
            }
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PlayerResultCard: View {
    let player: DrillPlayer
    let name: String
    let definition: DrillDefinition

    var body: some View {
        let color = player.primaryColor.swatch
        let stats = player.stats
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 14, height: 14).shadow(color: color, radius: 6)
                Text(name).font(.headline)
                Spacer()
                if let accuracy = stats.accuracy {
                    Text("\(Int((accuracy * 100).rounded()))% accuracy")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(color.opacity(0.22), in: Capsule())
                }
            }

            HStack(spacing: 0) {
                metric("\(stats.hitCount)", "hits")
                metric(Format.ms(stats.averageMs), "average")
                metric(Format.ms(stats.bestMs), "best")
                if definition.engine == .focus {
                    metric("\(stats.strikes)", "strikes")
                } else if definition.lightsOut == .timeout {
                    metric("\(stats.timeouts)", "timed out")
                } else {
                    metric("\(stats.misses)", "missed")
                }
            }

            if stats.hits.count >= 2 {
                Chart {
                    ForEach(Array(stats.hits.enumerated()), id: \.offset) { i, hit in
                        AreaMark(x: .value("Hit", i + 1), y: .value("ms", hit.reactionMs))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.45), color.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Hit", i + 1), y: .value("ms", hit.reactionMs))
                            .foregroundStyle(color)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Hit", i + 1), y: .value("ms", hit.reactionMs))
                            .foregroundStyle(color)
                            .symbolSize(hit.reactionMs == stats.bestMs ? 80 : 20)
                    }
                    if let avg = stats.averageMs {
                        RuleMark(y: .value("Average", avg))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("avg \(avg) ms").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel().foregroundStyle(.white.opacity(0.5))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(.white.opacity(0.5))
                    }
                }
                .chartYAxisLabel("ms", position: .topLeading)
                .frame(height: 150)
            } else if stats.hits.isEmpty {
                Text("No hits recorded.").font(.subheadline).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
