import BlazePodDrills
import BlazePodKit
import SwiftUI

// MARK: Colours

extension PodColor {
    /// Display colour, tuned to look like the LED rather than the CSS colour name.
    var swatch: Color {
        switch self {
        case .red: Color(red: 1.00, green: 0.23, blue: 0.27)
        case .orange: Color(red: 1.00, green: 0.55, blue: 0.10)
        case .yellow: Color(red: 1.00, green: 0.86, blue: 0.15)
        case .green: Color(red: 0.20, green: 0.92, blue: 0.40)
        case .lightBlue: Color(red: 0.25, green: 0.85, blue: 1.00)
        case .blue: Color(red: 0.20, green: 0.42, blue: 1.00)
        case .purple: Color(red: 0.66, green: 0.33, blue: 1.00)
        case .pink: Color(red: 1.00, green: 0.36, blue: 0.75)
        case .random: .gray
        }
    }

    var title: String {
        switch self {
        case .lightBlue: "Light Blue"
        default: rawValue.capitalized
        }
    }
}

enum Theme {
    static let corner: CGFloat = 24
    static let smallCorner: CGFloat = 16
    static let runBackground = Color(red: 0.04, green: 0.05, blue: 0.09)
}

/// Visual identity of a drill: gradient + symbol.
struct DrillStyle {
    let colors: [Color]

    init(_ drill: DrillDefinition) {
        switch drill.id {
        case DrillDefinition.colorCatch.id:
            colors = [Color(red: 0.55, green: 0.22, blue: 1.0), Color(red: 1.0, green: 0.30, blue: 0.62)]
        case DrillDefinition.plankFocusChallenge.id:
            colors = [Color(red: 0.0, green: 0.62, blue: 0.62), Color(red: 0.25, green: 0.88, blue: 0.45)]
        case DrillDefinition.fastFeet.id:
            colors = [Color(red: 1.0, green: 0.40, blue: 0.12), Color(red: 1.0, green: 0.18, blue: 0.33)]
        case DrillDefinition.random.id:
            colors = [Color(red: 0.13, green: 0.36, blue: 1.0), Color(red: 0.42, green: 0.25, blue: 0.95)]
        default:
            // Custom drills take their first player's colour.
            let base = drill.colors(forPlayer: 0).first?.swatch ?? .blue
            colors = [base, base.mix(with: .black, by: 0.35)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accent: Color { colors[0] }
}

// MARK: Building blocks

/// A pod as seen from above: dark shell, glowing lens when lit.
struct GlowPod: View {
    var color: PodColor?
    var size: CGFloat = 44
    var label: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
            Circle()
                .fill(lens)
                .frame(width: size * 0.76, height: size * 0.76)
                .background {
                    if let c = color?.swatch {
                        Circle().fill(c).frame(width: size, height: size).blur(radius: size * 0.3).opacity(0.85)
                    }
                }
            if let label {
                Text(label)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(color == nil ? Color.white.opacity(0.45) : .white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.12), value: color)
    }

    private var lens: some ShapeStyle {
        if let c = color?.swatch {
            return AnyShapeStyle(RadialGradient(colors: [.white.opacity(0.95), c, c.mix(with: .black, by: 0.2)],
                                                center: .center, startRadius: 0, endRadius: size * 0.45))
        }
        return AnyShapeStyle(RadialGradient(colors: [Color(white: 0.28), Color(white: 0.14)],
                                            center: .center, startRadius: 0, endRadius: size * 0.45))
    }
}

/// Small rounded label with an icon, used for drill facts.
struct FactChip: View {
    let symbol: String
    let text: String
    var onGradient = false

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(onGradient ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.fill.tertiary), in: Capsule())
            .foregroundStyle(onGradient ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

/// Grouped card used on the drill setup screen.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Stepper row with a big value, used throughout the setup screen.
struct ValueStepper: View {
    let title: String
    var caption: String?
    let value: String
    let canDecrement: Bool
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton("minus", enabled: canDecrement, action: decrement)
                Text(value)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 64)
                    .contentTransition(.numericText())
                stepButton("plus", enabled: canIncrement, action: increment)
            }
            .background(.fill.tertiary, in: Capsule())
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

extension ValueStepper {
    /// Integer stepper over a range.
    init(_ title: String, caption: String? = nil, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         format: @escaping (Int) -> String = { "\($0)" }) {
        self.init(title: title, caption: caption, value: format(value.wrappedValue),
                  canDecrement: value.wrappedValue - step >= range.lowerBound,
                  canIncrement: value.wrappedValue + step <= range.upperBound,
                  decrement: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) },
                  increment: { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) })
    }

    /// Seconds stepper over a range.
    init(_ title: String, caption: String? = nil, seconds: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        self.init(title: title, caption: caption, value: Format.seconds(seconds.wrappedValue),
                  canDecrement: seconds.wrappedValue - step >= range.lowerBound - 0.0001,
                  canIncrement: seconds.wrappedValue + step <= range.upperBound + 0.0001,
                  decrement: { seconds.wrappedValue = max(range.lowerBound, seconds.wrappedValue - step) },
                  increment: { seconds.wrappedValue = min(range.upperBound, seconds.wrappedValue + step) })
    }
}

/// Segmented choice with icons, drawn as pills.
struct PillPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        let symbol: String
        var id: String { title }
    }

    let options: [Option]
    @Binding var selection: Value
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy) { selection = option.value }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.body.weight(.semibold))
                        Text(option.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.fill.tertiary))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Colour picker: tap swatches to toggle; keeps at least one selected.
struct ColorSwatchPicker: View {
    @Binding var selection: [PodColor]
    var excluded: Set<PodColor> = []
    var maxCount = Limits.colorsPerPlayer.upperBound

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PodColor.palette, id: \.self) { color in
                let isOn = selection.contains(color)
                let isExcluded = excluded.contains(color)
                Button {
                    withAnimation(.snappy) { toggle(color) }
                } label: {
                    ZStack {
                        Circle().fill(color.swatch)
                            .frame(width: 30, height: 30)
                            .shadow(color: isOn ? color.swatch.opacity(0.8) : .clear, radius: 6)
                        if isOn {
                            Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 30, height: 30)
                            Image(systemName: "checkmark").font(.caption2.weight(.black)).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .opacity(isExcluded ? 0.18 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isExcluded)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func toggle(_ color: PodColor) {
        if let i = selection.firstIndex(of: color) {
            if selection.count > 1 { selection.remove(at: i) }
        } else if selection.count < maxCount {
            selection.append(color)
        } else {
            selection.removeFirst()
            selection.append(color)
        }
    }
}

/// Full-width primary action with the drill's gradient.
struct GradientButtonStyle: ButtonStyle {
    let style: DrillStyle
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(style.gradient) : AnyShapeStyle(Color.gray.opacity(0.45)))
                    .shadow(color: enabled ? style.accent.opacity(0.45) : .clear, radius: 16, y: 8)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}

// MARK: Formatting

enum Format {
    static func seconds(_ s: Double) -> String {
        var text = String(format: "%.2f", s)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + " s"
    }

    static func clock(_ seconds: Int) -> String {
        seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds) s"
    }

    static func timer(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func ms(_ v: Int?) -> String { v.map { "\($0) ms" } ?? "–" }
}

extension DrillDefinition {
    var engineTitle: String {
        switch engine {
        case .random: "Random"
        case .focus: "Focus"
        }
    }

    var durationText: String {
        switch duration {
        case .time(let s): Format.clock(s)
        case .hitCount(let h): "\(h) hits"
        case .timeOrHitCount(let s, let h): "\(Format.clock(s)) / \(h) hits"
        }
    }

    var podsText: String { "\(totalPods) pod\(totalPods == 1 ? "" : "s")" }
    var playersText: String { "\(totalPlayers) player\(totalPlayers == 1 ? "" : "s")" }
}
