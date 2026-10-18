import BlazePodDrills
import BlazePodKit
import SwiftUI

/// Choose and order the pods a drill uses. Order = station order: the first
/// `podsPerStation` pods form station 1, and so on.
struct PodSelectionView: View {
    @EnvironmentObject private var controller: PodController
    @Environment(\.dismiss) private var dismiss

    let definition: DrillDefinition
    let initial: [UUID]
    let onSave: ([UUID]) -> Void

    @State private var list: [UUID] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(list.enumerated()), id: \.element) { position, id in
                        row(id, position: position)
                    }
                    .onMove { list.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { list.remove(atOffsets: $0) }
                    if list.isEmpty {
                        Text("No pods chosen. Add pods below.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Used in this drill · \(min(list.count, definition.totalPods)) of \(definition.totalPods)")
                } footer: {
                    Text(footer)
                }

                Section("Available") {
                    let available = candidates.filter { !list.contains($0.id) }
                    if available.isEmpty {
                        Text("No other pods.").foregroundStyle(.secondary)
                    }
                    ForEach(available) { known in
                        Button {
                            withAnimation { list.append(known.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.title3)
                                Text(known.name).foregroundStyle(.primary)
                                Spacer()
                                Text(known.pod?.isReady == true ? "Connected" : "Not connected")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        withAnimation { list = controller.assignedPods(count: definition.totalPods, selection: []).map(\.id) }
                    } label: {
                        Label("Reset to connected pods in name order", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        controller.flash(flashPlan)
                    } label: {
                        Label("Identify these pods", systemImage: "lightbulb.max.fill")
                    }
                    .disabled(flashPlan.isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Pods for \(definition.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(list)
                        dismiss()
                    }
                }
            }
            .onAppear {
                list = initial.isEmpty
                    ? controller.assignedPods(count: definition.totalPods, selection: []).map(\.id)
                    : initial
            }
        }
    }

    /// Connected pods plus pods added earlier.
    private var candidates: [KnownPod] {
        var all = controller.myPods
        for pod in controller.readyPods where !all.contains(where: { $0.id == pod.id }) {
            all.append(KnownPod(id: pod.id, name: pod.name, pod: pod, lastConnected: nil))
        }
        return all
    }

    private var flashPlan: [(BlazePod, PodColor)] {
        list.prefix(definition.totalPods).enumerated().compactMap { i, id in
            guard let pod = controller.pod(id), pod.isReady else { return nil }
            return (pod, stationColor(i / definition.podsPerStation))
        }
    }

    private var footer: String {
        var text = "Drag to change the order."
        if definition.stations > 1 {
            text += " Every \(definition.podsPerStation) pods form a station."
        }
        if list.count > definition.totalPods {
            text += " Extra pods are spares and step in when a chosen pod is not connected."
        } else {
            text += " Missing or disconnected pods are filled with other connected pods."
        }
        return text
    }

    private func row(_ id: UUID, position: Int) -> some View {
        let pod = controller.pod(id)
        let name = pod?.name ?? controller.store.name(for: id) ?? "Pod"
        let used = position < definition.totalPods
        let station = position / definition.podsPerStation
        return HStack(spacing: 12) {
            GlowPod(color: used ? stationColor(station) : nil, size: 30,
                    label: used ? "\(position % definition.podsPerStation + 1)" : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium))
                Text(subtitle(pod: pod, used: used, station: station))
                    .font(.caption)
                    .foregroundStyle(pod?.isReady == true ? Color.secondary : Color.orange)
            }
            Spacer()
            if let pod, pod.isReady {
                Button { controller.identify(pod) } label: { Image(systemName: "lightbulb.fill") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func subtitle(pod: BlazePod?, used: Bool, station: Int) -> String {
        let status = pod?.isReady == true ? "Connected" : "Not connected"
        guard used else { return "Spare · \(status)" }
        return definition.stations > 1 ? "Station \(station + 1) · \(status)" : status
    }
}

/// One colour per station for identifying pods.
func stationColor(_ station: Int) -> PodColor {
    PodColor.assignmentOrder[station % PodColor.assignmentOrder.count]
}

extension KnownPod: Hashable {
    static func == (a: KnownPod, b: KnownPod) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
