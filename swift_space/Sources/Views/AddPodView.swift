import SwiftUI
import SwiftData
import VisionKit

// MARK: - Add Pod Coordinator (observable state machine)

@Observable
class AddPodCoordinator {
    enum Phase: Equatable {
        case connecting
        case identifying   // blinking + waiting for triple tap
        case configuring   // user fills in details
        case saving
    }

    var phase: Phase = .connecting
    var tapTimestamps: [Date] = []
    var identifyTask: Task<Void, Never>?

    var tapProgress: Int {
        min(tapTimestamps.count, 3)
    }

    func recordTap() {
        let now = Date()
        // Keep only taps within the last 3 seconds
        tapTimestamps = tapTimestamps.filter { now.timeIntervalSince($0) < 3.0 }
        tapTimestamps.append(now)
        if tapTimestamps.count >= 3 {
            acceptPod()
        }
    }

    var onAccepted: (() -> Void)?

    func acceptPod() {
        identifyTask?.cancel()
        identifyTask = nil
        phase = .configuring
        onAccepted?()
    }

    func cleanup() {
        identifyTask?.cancel()
        identifyTask = nil
    }
}

// MARK: - Add Pod View

struct AddPodView: View {
    var bleManager: BLEManager
    var device: PodDevice
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPod.name) private var savedPods: [SavedPod]

    @State private var coordinator = AddPodCoordinator()

    // Config fields
    @State private var alias = ""
    @State private var serialNumber = ""
    @State private var comment = ""
    @State private var podDescription = ""
    @State private var showQRScanner = false

    @FocusState private var aliasFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.phase {
                case .connecting:
                    connectingContent
                case .identifying:
                    identifyingContent
                case .configuring, .saving:
                    configuringContent
                }
            }
            .navigationTitle("Add Pod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        cancelFlow()
                    }
                }
                if coordinator.phase == .configuring {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            savePod()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .interactiveDismissDisabled(coordinator.phase == .identifying)
        .onAppear {
            startFlow()
        }
        .onDisappear {
            coordinator.cleanup()
            bleManager.onTapReceived = nil
        }
        .onChange(of: device.connectionState) { _, newState in
            if newState == .authenticated && coordinator.phase == .connecting {
                startIdentification()
            } else if newState == .error {
                // stay on connecting, show error
            }
        }
    }

    // MARK: - Connecting Phase

    private var connectingContent: some View {
        VStack(spacing: 24) {
            Spacer()
            if device.connectionState == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text(device.errorMessage ?? "Connection failed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    bleManager.reconnectPod(device)
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Connecting to \(device.name)…")
                    .font(.headline)
                Text(device.connectionState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Identifying Phase

    private var identifyingContent: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "light.max")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse)

            Text("Find Your Pod")
                .font(.title2.bold())

            Text("The pod is blinking.\nTriple-tap it to confirm.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Tap progress dots
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < coordinator.tapProgress ? Color.green : Color(.systemGray4))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if i < coordinator.tapProgress {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }

            Text("\(coordinator.tapProgress) of 3 taps")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Skip — Configure Now") {
                coordinator.acceptPod()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Configuring Phase

    private var configuringContent: some View {
        Form {
            Section("Pod Identity") {
                LabeledContent("BLE Name", value: device.name)
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("Alias (e.g. Left, Station A)", text: $alias)
                        .focused($aliasFocused)
                }
                .contentShape(Rectangle())
                .onTapGesture { aliasFocused = true }

                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Serial Number", text: $serialNumber)
                    }
                    if DataScannerViewController.isSupported {
                        Button {
                            showQRScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title3)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("Description", text: $podDescription)
                }
            }

            Section("Notes") {
                TextField("Comment", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .sheet(isPresented: $showQRScanner) {
            NavigationStack {
                QRScannerView { code in
                    serialNumber = code
                }
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showQRScanner = false }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Flow Control

    private func startFlow() {
        // If already connected/authenticated, skip connecting
        if device.connectionState == .authenticated {
            startIdentification()
        } else if device.connectionState == .disconnected || device.connectionState == .error {
            bleManager.connectPod(device)
        }
        // else: already connecting/authenticating — wait for onChange
    }

    private func startIdentification() {
        coordinator.phase = .identifying

        // Turn off LED when pod is accepted (triple-tap or skip)
        coordinator.onAccepted = { [bleManager, device] in
            bleManager.turnOff(device)
        }

        // Start blink pattern: 3 blinks, pause, 3 blinks, pause, repeat
        coordinator.identifyTask = Task {
            while !Task.isCancelled {
                for _ in 0..<3 {
                    guard !Task.isCancelled else { return }
                    bleManager.setColor(device, color: .white)
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    bleManager.turnOff(device)
                    try? await Task.sleep(for: .milliseconds(200))
                }
                try? await Task.sleep(for: .milliseconds(800))
                for _ in 0..<3 {
                    guard !Task.isCancelled else { return }
                    bleManager.setColor(device, color: .white)
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    bleManager.turnOff(device)
                    try? await Task.sleep(for: .milliseconds(200))
                }
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }

        // Listen for taps from this pod
        let targetID = device.id
        bleManager.onTapReceived = { [coordinator] pod, _ in
            guard pod.id == targetID else { return }
            Task { @MainActor in
                coordinator.recordTap()
            }
        }
    }

    private func savePod() {
        // Ensure pod is in connectedPods
        if !bleManager.connectedPods.contains(where: { $0.id == device.id }) {
            bleManager.connectedPods.append(device)
        }

        // Save to SwiftData
        let existing = savedPods.first { $0.peripheralUUID == device.id.uuidString }
        if let existing = existing {
            existing.name = device.name
            if !alias.isEmpty { existing.alias = alias }
            if !serialNumber.isEmpty { existing.serialNumber = serialNumber }
            if !comment.isEmpty { existing.comment = comment }
            if !podDescription.isEmpty { existing.podDescription = podDescription }
            if let hex = device.manufacturerDataHex { existing.manufacturerDataHex = hex }
        } else {
            let saved = SavedPod(
                peripheralUUID: device.id.uuidString,
                name: device.name,
                manufacturerDataHex: device.manufacturerDataHex
            )
            saved.alias = alias.isEmpty ? nil : alias
            saved.serialNumber = serialNumber.isEmpty ? nil : serialNumber
            saved.comment = comment.isEmpty ? nil : comment
            saved.podDescription = podDescription.isEmpty ? nil : podDescription
            modelContext.insert(saved)
        }

        coordinator.cleanup()
        bleManager.onTapReceived = nil
        dismiss()
    }

    private func cancelFlow() {
        coordinator.cleanup()
        bleManager.onTapReceived = nil
        // If pod was connected during this flow but not saved, disconnect
        let wasSaved = savedPods.contains { $0.peripheralUUID == device.id.uuidString }
        if !wasSaved {
            bleManager.removePod(device)
        }
        dismiss()
    }
}
