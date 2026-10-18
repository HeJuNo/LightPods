import BlazePodKit
import SwiftUI

struct PodDetailView: View {
    @EnvironmentObject private var controller: PodController
    let pod: BlazePod

    @State private var offOnHit = false
    @State private var confirmShutdown = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    GlowPod(color: pod.isLightOn ? pod.currentColor : nil, size: 96)
                    Text(pod.statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pod.statusColor)
                    HStack(spacing: 16) {
                        if let level = pod.batteryLevel {
                            BatteryBadge(level: level, charging: pod.isCharging)
                        }
                        HStack(spacing: 4) {
                            SignalBars(bars: pod.signalBars)
                            Text("\(pod.rssi) dBm").monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Light") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(PodColor.palette, id: \.self) { color in
                        Button { pod.lightOn(color, offOnHit: offOnHit) } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(color.swatch)
                                    .frame(width: 40, height: 40)
                                    .shadow(color: color.swatch.opacity(pod.currentColor == color ? 0.9 : 0), radius: 8)
                                    .overlay {
                                        if pod.isLightOn && pod.currentColor == color {
                                            Circle().strokeBorder(.white, lineWidth: 3)
                                        }
                                    }
                                Text(color.title).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                Toggle("Turn off when hit", isOn: $offOnHit)
                    .disabled(!pod.info.supportsTouchV2)
                Button { pod.lightOff() } label: { Label("Light off", systemImage: "lightbulb.slash") }
                Button { pod.lightOn(.default, for: 30) } label: { Label("Identify (30 s)", systemImage: "lightbulb.max") }
            }
            .disabled(!pod.isReady)

            Section("Recent Hits") {
                let podHits = controller.hits.filter { $0.podID == pod.id }.prefix(10)
                if podHits.isEmpty {
                    Text("Light the pod and tap it.").foregroundStyle(.secondary)
                }
                ForEach(podHits) { hit in
                    LabeledContent(hit.date.formatted(date: .omitted, time: .standard)) {
                        Text("\(hit.reactionMs) ms").monospacedDigit()
                    }
                }
            }

            Section("Device") {
                row("Model", pod.info.model.map { "\($0) (\(pod.info.hardware?.rawValue ?? "?"))" } ?? "–")
                row("Firmware", pod.info.appFirmware?.description ?? "–")
                row("Bootloader", pod.info.bootloaderFirmware?.description ?? "–")
                row("Serial", pod.info.serial ?? "–")
                row("Charger", pod.charger?.title ?? (pod.advertisement?.isCharging == true ? "On charger" : "–"))
                row("Identifier", pod.id.uuidString)
            }

            Section("Protocol") {
                row("Link", pod.linkState.title)
                row("Connect attempts", "\(pod.connectAttempts)")
                row("Touch v2 (fw ≥ 3.2)", pod.info.supportsTouchV2 ? "Yes" : "No")
                if let ad = pod.advertisement {
                    row("Adv version", "\(ad.version)")
                    row("Adv key", ad.key.hexString)
                    row("Auth response", PodAuthenticator.response(key: ad.key, version: ad.version).hexString)
                } else {
                    row("Adv data", "none – auth skipped")
                }
            }

            Section {
                Button(pod.intent == .connect ? "Disconnect" : "Connect") { controller.toggleConnection(pod) }
                Button("Shut down pod", role: .destructive) { confirmShutdown = true }
                    .disabled(!pod.isReady)
            } footer: {
                Text("Shutting down blinks the pod red 3 times. Press the pod to switch it on again.")
            }
        }
        .navigationTitle(pod.name)
        .confirmationDialog("Shut down \(pod.name)?", isPresented: $confirmShutdown, titleVisibility: .visible) {
            Button("Shut down", role: .destructive) { pod.shutDown() }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
        }
    }
}
