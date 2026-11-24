// 掃 QR code（連電腦 Claude CLI 用）。用系統的 VisionKit DataScanner，只認 QR code，掃到第一個就交出去。
// 模擬器和比較舊的 iPhone 沒有這個功能，isAvailable 會是 false，畫面要改成貼網址。
// 相機權限在進到掃描畫面時才問；被拒絕就在這裡說去哪裡打開。
import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// 現在該畫什麼：在等使用者回答、可以掃、相機權限被關、相機被別的原因擋住
private enum CameraGate {
    case asking, ready, denied, blocked
}

struct QRScanner: View {
    let onFound: (String) -> Void
    @State private var gate: CameraGate = CameraGate.asking

    init(onFound: @escaping (String) -> Void) {
        self.onFound = onFound
    }

    /// 這支手機有沒有掃描功能。不看相機權限：還沒問過的要讓人按得進來才問得到
    @MainActor
    static var isAvailable: Bool {
        return DataScannerViewController.isSupported
    }

    var body: some View {
        ZStack {
            C.canvas
            switch gate {
            case .asking:
                EmptyView()
            case .ready:
                QRCamera(onFound: onFound, onFail: { gate = CameraGate.blocked })
            case .denied:
                DomyEmptyState(
                    title: "相機沒有打開",
                    message: "去 iPhone 的設定，找到蘿蔔旅行，把「相機」打開，再回來掃。不想開也可以，關掉這頁，貼上電腦印的網址。",
                    actionTitle: "打開設定",
                    action: { openAppSettings() }
                )
            case .blocked:
                DomyEmptyState(
                    title: "相機現在不能用",
                    message: "可能是螢幕使用時間擋住了。關掉這頁再試一次，或貼上電腦印的網址。"
                )
            }
        }
        .task {
            await askCamera()
        }
    }

    /// 沒問過就問，問過就看上次的答案
    @MainActor
    private func askCamera() async {
        let status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            gate = CameraGate.ready
        case .notDetermined:
            let ok: Bool = await AVCaptureDevice.requestAccess(for: .video)
            gate = ok ? CameraGate.ready : CameraGate.denied
        case .restricted:
            gate = CameraGate.blocked
        case .denied:
            gate = CameraGate.denied
        @unknown default:
            gate = CameraGate.denied
        }
    }

    @MainActor
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// 掃描的相機畫面本身。相機開不起來就叫 onFail
private struct QRCamera: UIViewControllerRepresentable {
    let onFound: (String) -> Void
    let onFail: () -> Void

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
        let owner: Coordinator = context.coordinator
        DispatchQueue.main.async {
            do {
                try vc.startScanning()
            } catch {
                owner.fail()
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(onFound: onFound, onFail: onFail)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        let onFail: () -> Void
        private var done: Bool = false

        init(onFound: @escaping (String) -> Void, onFail: @escaping () -> Void) {
            self.onFound = onFound
            self.onFail = onFail
        }

        func fail() {
            if done { return }
            done = true
            onFail()
        }

        /// 掃到一半相機被收走（例如權限被關）
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            fail()
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
