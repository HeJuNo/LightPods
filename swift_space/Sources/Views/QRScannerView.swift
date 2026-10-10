import SwiftUI
import VisionKit

/// Camera-based QR / barcode scanner using DataScannerViewController
struct QRScannerView: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isReady: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .code128, .ean13, .ean8])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning {
            try? vc.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: QRScannerView
        private var delivered = false

        init(parent: QRScannerView) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in items {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue, !value.isEmpty {
                    delivered = true
                    DispatchQueue.main.async {
                        self.parent.onCodeScanned(value)
                        self.parent.dismiss()
                    }
                    return
                }
            }
        }
    }
}
