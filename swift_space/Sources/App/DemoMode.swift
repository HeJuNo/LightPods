import Foundation

/// Debug-only launch arguments for UI work without pods (the Simulator has no Bluetooth):
/// `-demo` simulates 24 ready pods that get hit automatically,
/// `-drill <index>` opens a drill, `-autostart` starts it, `-pods` opens the pod settings.
enum Demo {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demo")
    static let drillIndex = value(after: "-drill").flatMap(Int.init)
    static let autostart = ProcessInfo.processInfo.arguments.contains("-autostart")
    static let showsPods = ProcessInfo.processInfo.arguments.contains("-pods")

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    #else
    static let isOn = false
    static let drillIndex: Int? = nil
    static let autostart = false
    static let showsPods = false
    #endif
}
