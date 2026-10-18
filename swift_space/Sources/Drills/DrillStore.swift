import BlazePodDrills
import Foundation

/// Built-in drills plus the user's saved drills (JSON in Application Support).
final class DrillStore: ObservableObject {
    @Published private(set) var custom: [DrillDefinition] = []
    /// Pods chosen for a drill, in station order (drill id → pod ids). Missing = automatic.
    @Published private(set) var podSelections: [UUID: [UUID]] = [:]

    let builtIns = DrillDefinition.builtIns
    private let url: URL

    init(fileName: String = "drills.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([DrillDefinition].self, from: data) {
            custom = saved
        }
        let raw = UserDefaults.standard.dictionary(forKey: Self.selectionsKey) as? [String: [String]] ?? [:]
        for (drill, pods) in raw {
            if let id = UUID(uuidString: drill) { podSelections[id] = pods.compactMap(UUID.init) }
        }
    }

    private static let selectionsKey = "lightpods.podSelections"

    func podSelection(for drill: UUID) -> [UUID] { podSelections[drill] ?? [] }

    /// Empty list = automatic (connected pods in name order).
    func setPodSelection(_ pods: [UUID], for drill: UUID) {
        podSelections[drill] = pods.isEmpty ? nil : pods
        let raw = Dictionary(uniqueKeysWithValues: podSelections.map { ($0.key.uuidString, $0.value.map(\.uuidString)) })
        UserDefaults.standard.set(raw, forKey: Self.selectionsKey)
    }

    func drill(_ id: UUID) -> DrillDefinition? {
        builtIns.first { $0.id == id } ?? custom.first { $0.id == id }
    }

    /// Inserts or updates a saved drill.
    func save(_ drill: DrillDefinition) {
        guard !drill.isBuiltIn else { return }
        if let i = custom.firstIndex(where: { $0.id == drill.id }) {
            custom[i] = drill
        } else {
            custom.insert(drill, at: 0)
        }
        persist()
    }

    @discardableResult
    func saveAsNew(_ drill: DrillDefinition, name: String) -> DrillDefinition {
        let copy = drill.duplicated(named: name)
        save(copy)
        if let pods = podSelections[drill.id] { setPodSelection(pods, for: copy.id) }
        return copy
    }

    func delete(_ id: UUID) {
        custom.removeAll { $0.id == id }
        setPodSelection([], for: id)
        persist()
    }

    /// A name that is not taken yet, e.g. "Fast Feet 2".
    func suggestedName(for drill: DrillDefinition) -> String {
        let names = Set((builtIns + custom).map(\.name))
        let base = drill.isBuiltIn ? "My \(drill.name)" : drill.name
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(custom)
            try data.write(to: url, options: .atomic)
        } catch {
            assertionFailure("Saving drills failed: \(error)")
        }
    }
}
