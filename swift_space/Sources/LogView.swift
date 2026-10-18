import SwiftUI

struct LogView: View {
    @EnvironmentObject private var controller: PodController
    @State private var filter = ""

    private var entries: [LogEntry] {
        let all = controller.log.reversed()
        return filter.isEmpty ? Array(all) : all.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .searchable(text: $filter, prompt: "Filter (e.g. auth, RX uart, TX 50C912A2)")
            .navigationTitle("Log")
            .toolbar {
                ToolbarItemGroup {
                    Toggle("Raw traffic", isOn: $controller.verboseLog)
                    ShareLink(item: controller.logText)
                    Button("Clear", systemImage: "trash", action: controller.clearLog)
                }
            }
        }
    }
}
