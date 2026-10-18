import BlazePodDrills
import BlazePodKit
import SwiftUI

/// Home screen: built-in and saved drills.
struct DrillLibraryView: View {
    @EnvironmentObject private var controller: PodController
    @EnvironmentObject private var store: DrillStore
    @State private var showsPods = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if controller.availablePodCount == 0 {
                        ConnectPodsBanner { showsPods = true }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Drills", subtitle: "Pick one, adjust it, go.")
                        ForEach(store.builtIns) { drill in
                            NavigationLink(value: drill.id) { DrillCard(drill: drill, prominent: true) }
                                .buttonStyle(CardButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("My Drills", subtitle: "Change any drill and save it as a new one.")
                        if store.custom.isEmpty {
                            EmptyMyDrills()
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                                      spacing: 14) {
                                ForEach(store.custom) { drill in
                                    NavigationLink(value: drill.id) { DrillCard(drill: drill, prominent: false) }
                                        .buttonStyle(CardButtonStyle())
                                        .contextMenu {
                                            Button {
                                                store.saveAsNew(drill, name: store.suggestedName(for: drill))
                                            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                            Button(role: .destructive) {
                                                withAnimation { store.delete(drill.id) }
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PodStatusButton { showsPods = true }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let drill = store.drill(id) {
                    DrillSetupView(original: drill) { saved in
                        // Jump from the built-in to the newly saved copy.
                        path.removeLast()
                        path.append(saved.id)
                    }
                }
            }
            .sheet(isPresented: $showsPods) {
                PodSettingsView()
            }
            .onAppear {
                if Demo.showsPods { showsPods = true }
                if let i = Demo.drillIndex, path.isEmpty {
                    let all = store.builtIns + store.custom
                    if all.indices.contains(i) { path.append(all[i].id) }
                }
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct DrillCard: View {
    let drill: DrillDefinition
    let prominent: Bool

    var body: some View {
        let style = DrillStyle(drill)
        ZStack(alignment: .topTrailing) {
            style.gradient
            Image(systemName: drill.symbol)
                .font(.system(size: prominent ? 120 : 80, weight: .bold))
                .foregroundStyle(.white.opacity(0.16))
                .rotationEffect(.degrees(-12))
                .offset(x: prominent ? 24 : 18, y: prominent ? -10 : -6)
            VStack(alignment: .leading, spacing: prominent ? 10 : 8) {
                HStack(spacing: 8) {
                    Image(systemName: drill.symbol)
                        .font(prominent ? .title3.weight(.bold) : .headline)
                        .frame(width: prominent ? 40 : 32, height: prominent ? 40 : 32)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if prominent {
                        Text(drill.engineTitle.uppercased())
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .opacity(0.85)
                    }
                }
                Spacer(minLength: 0)
                Text(drill.name)
                    .font(prominent ? .title2.weight(.heavy) : .headline.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if prominent {
                    Text(drill.summary)
                        .font(.subheadline)
                        .opacity(0.9)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    FactChip(symbol: "circle.hexagongrid.fill", text: drill.podsText, onGradient: true)
                    if prominent {
                        FactChip(symbol: "person.fill", text: drill.playersText, onGradient: true)
                    }
                    FactChip(symbol: "timer", text: drill.durationText, onGradient: true)
                }
                .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(prominent ? 20 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: prominent ? 228 : 170)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .shadow(color: style.accent.opacity(0.28), radius: 14, y: 8)
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

private struct ConnectPodsBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                HStack(spacing: -10) {
                    GlowPod(color: nil, size: 34)
                    GlowPod(color: .blue, size: 34)
                    GlowPod(color: nil, size: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your pods").font(.headline)
                    Text("Switch them on. Auto-connect does the rest.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .foregroundStyle(.primary)
    }
}

private struct EmptyMyDrills: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Open a drill, change stations, players, colours or timing, then tap **Save as New Drill**.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(.quaternary)
        }
    }
}
