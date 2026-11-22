// 掃 QR code（連電腦 Claude CLI 用）。用系統的 VisionKit DataScanner，只認 QR code，掃到第一個就交出去。
// 模擬器和比較舊的 iPhone 沒有這個功能，isAvailable 會是 false，畫面要改成貼網址。
import SwiftUI
import VisionKit

struct QRScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    /// 這支手機能不能掃（有相機、支援、使用者沒擋相機權限）
    static var isAvailable: Bool {
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc: DataScannerViewController = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        // 畫面還沒出來時開相機會失敗，等下一輪再開
        DispatchQueue.main.async {
            try? vc.startScanning()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(onFound: onFound)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done: Bool = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            if done { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue, !text.isEmpty {
                    done = true
                    Haptic.notify(.success)
                    onFound(text)
                    return
                }
            }
        }
    }
}
