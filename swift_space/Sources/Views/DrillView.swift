import SwiftUI

struct DrillView: View {
    var bleManager: BLEManager
    var drillManager: DrillManager
    
    private var authenticatedCount: Int {
        bleManager.connectedPods.filter { $0.connectionState == .authenticated }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Big reaction time display
                reactionTimeCard
                
                // Controls
                controlsSection
                
                // Stats
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
                    drillManager.start(bleManager: bleManager)
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
