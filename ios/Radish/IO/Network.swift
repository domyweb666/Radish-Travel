// 有沒有網路（線框 A19）。用系統的 NWPathMonitor 盯著，網路一變就更新 online。
// 只拿來決定「要 AI 的那句送不送得出去」：這趟、一站、須知、花費都在手機裡，沒網路照樣看、照樣改。
// 這個檔是 SwiftUI 版才有的，mobile/ 沒有對應的 TS。
// 用法：`NetWatch.shared.online`。畫面讀它會跟著網路變重畫（@Observable）。
import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetWatch {
    static let shared: NetWatch = NetWatch()

    /// 現在連得上網路嗎。系統第一次回報之前先當作連得上：真的沒網路，送出去會落到「沒收到回覆」，這趟不會動
    private(set) var online: Bool = true

    private let monitor: NWPathMonitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = NetWatch.handler()
        monitor.start(queue: DispatchQueue(label: "org.domyweb.radish.network", qos: .utility))
    }

    /// 系統在背景的佇列上叫這個，所以它不能綁在主執行緒上；拿到結果再回主執行緒改 online
    nonisolated private static func handler() -> @Sendable (NWPath) -> Void {
        return { (path: NWPath) -> Void in
            let ok: Bool = path.status == .satisfied
            Task { @MainActor in
                NetWatch.shared.update(ok)
            }
        }
    }

    private func update(_ ok: Bool) {
        if online != ok {
            online = ok
        }
    }
}
