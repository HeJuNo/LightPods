import Foundation

/// Registry of all available drill types.
/// Each entry provides a factory closure to create a fresh drill instance.
struct DrillCatalog {
    struct Entry: Identifiable {
        let id: String
        let name: String
        let description: String
        let iconName: String
        let minPods: Int
        let maxPods: Int?
        let playerRange: ClosedRange<Int>
        let factory: (_ config: DrillConfiguration) -> any Drill
    }

    static let all: [Entry] = [
        Entry(
            id: "random_light",
            name: "Random Light",
            description: "Tap each pod as fast as you can. Pods light up randomly.",
            iconName: "bolt.fill",
            minPods: 1, maxPods: nil,
            playerRange: 1...1,
            factory: { config in RandomLightDrill(config: config) }
        ),
        Entry(
            id: "reaction_time",
            name: "Reaction Time",
            description: "Wait for green, then tap as fast as you can!",
            iconName: "timer",
            minPods: 1, maxPods: 1,
            playerRange: 1...1,
            factory: { config in ReactionTimeDrill(config: config) }
        ),
        Entry(
            id: "sequence",
            name: "Sequence",
            description: "Pods light up one by one. Tap each in order.",
            iconName: "arrow.right.arrow.left",
            minPods: 2, maxPods: nil,
            playerRange: 1...1,
            factory: { config in SequenceDrill(config: config) }
        ),
        Entry(
            id: "color_match",
            name: "Color Match",
            description: "Multiple pods light up. Tap only the target color!",
            iconName: "paintpalette.fill",
            minPods: 2, maxPods: nil,
            playerRange: 1...1,
            factory: { config in ColorMatchDrill(config: config) }
        ),
        Entry(
            id: "speed_tap",
            name: "Speed Tap",
            description: "Tap as many lit pods as you can before time runs out!",
            iconName: "flame.fill",
            minPods: 1, maxPods: nil,
            playerRange: 1...6,
            factory: { config in SpeedTapDrill(config: config) }
        ),
    ]
}
