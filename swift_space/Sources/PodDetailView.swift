import BlazePodKit
import SwiftUI

struct PodDetailView: View {
    @EnvironmentObject private var controller: PodController
    let pod: BlazePod

    @State private var offOnHit = false
    @State private var confirmShutdown = false

    var body: some View {
        List {
            Section("Status") {
                row("Link", pod.linkState.title)
                row("Intent", "\(pod.intent)")
                row("RSSI", "\(pod.rssi) dBm")
                row("Battery", (pod.battery ?? pod.advertisement?.batteryPercent).map { "\($0)%" } ?? "–")
                row("Charger", pod.charger?.title ?? (pod.advertisement?.isCharging == true ? "On charger (adv)" : "–"))
                row("Connect attempts", "\(pod.connectAttempts)")
                row("Last seen", pod.lastSeen.formatted(date: .omitted, time: .standard))
            }

            Section("Device") {
                row("Identifier", pod.id.uuidString)
                row("Model", pod.info.model.map { "\($0) (\(pod.info.hardware?.rawValue ?? "?"))" } ?? "–")
                row("Firmware", pod.info.appFirmware?.description ?? "–")
                row("Bootloader", pod.info.bootloaderFirmware?.description ?? "–")
                row("Serial", pod.info.serial ?? "–")
                row("Touch v2 (fw ≥ 3.2)", pod.info.supportsTouchV2 ? "Yes" : "No")
                if let ad = pod.advertisement {
                    row("Adv version", "\(ad.version)")
                    row("Adv key", ad.key.hexString)
                    row("Auth response", PodAuthenticator.response(key: ad.key, version: ad.version).hexString)
                } else {
                    row("Adv data", "none – auth skipped")
                }
            }

            Section("Connection") {
                Button(pod.intent == .connect ? "Disconnect" : "Connect") { controller.toggleConnection(pod) }
                Toggle("Auto-connect", isOn: Binding(
                    get: { controller.autoConnect.contains(pod.id) },
                    set: { controller.setAutoConnect(pod, $0) }))
            }

            Section("Light") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(PodColor.palette, id: \.self) { color in
                        Button { pod.lightOn(color, offOnHit: offOnHit) } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color.swatch)
                                .frame(height: 40)
                                .overlay(Text(color.title).font(.caption2).foregroundStyle(.white).shadow(radius: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                Toggle("Turn off on hit (4th byte)", isOn: $offOnHit)
                    .disabled(!pod.info.supportsTouchV2)
                Button("Light off") { pod.lightOff() }
                Button("Identify (blue, 30 s)") { pod.lightOn(.default, for: 30) }
                LabeledContent("Current") {
                    Text(pod.isLightOn ? (pod.currentColor?.title ?? "On") : "Off")
                }
            }
            .disabled(pod.linkState != .ready)

            Section {
                let podHits = controller.hits.filter { $0.podID == pod.id }.prefix(15)
                if podHits.isEmpty {
                    Text("Light the pod and tap it.").foregroundStyle(.secondary)
                }
                ForEach(podHits) { hit in
                    LabeledContent(hit.date.formatted(date: .omitted, time: .standard)) {
                        Text("\(hit.reactionMs) ms").monospacedDigit()
                    }
                }
            } header: {
                Text("Hits")
            }

            Section {
                Button("Shut down pod", role: .destructive) { confirmShutdown = true }
                    .disabled(pod.linkState != .ready)
            } footer: {
                Text("Blinks red 3×, then sends tp7 + xrs. You need to press the pod to turn it on again.")
            }
        }
        .navigationTitle(pod.name)
        .confirmationDialog("Shut down \(pod.name)?", isPresented: $confirmShutdown) {
            Button("Shut down", role: .destructive) { pod.shutDown() }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
        }
    }
}
