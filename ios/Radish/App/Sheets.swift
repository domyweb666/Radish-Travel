// 彈出卡的總管：畫面只要說「打開哪一張」，同一時間只會有一張。
// 對應 mobile/src/sheets/host.tsx。
// 用法：`@Environment(Sheets.self) private var sheets`，然後 `sheets.open(.more(day: 1))`、`sheets.close()`。一站、去過的那一趟是推進頁，用 `nav.push`。
import Observation
import SwiftUI

/// 相簿那張卡要看哪一趟：現在這趟，或某一趟已經收起來的
enum AlbumSource: Hashable {
    case current
    case basket(id: String)
}

/// 半頁。一站、去過的那一趟改成推進頁了（Nav.swift 的 Push），不在這裡
enum SheetReq: Identifiable, Hashable {
    /// 剛剛那一則（S05，線框 A3）：這一天或一站最下面講完一句，升起來的回覆
    case reply
    /// 這一天的路線（S12，線框 A8）
    case map(day: Int)
    /// 附近還有什麼（S10，線框 A12）
    case nearby(day: Int)
    /// 移到別的時段（S07，線框 A6）
    case move(id: String)
    case add
    case settings
    case more(day: Int)

    var id: String {
        switch self {
        case .reply: return "reply"
        case .map(let day): return "map-\(day)"
        case .nearby(let day): return "nearby-\(day)"
        case .move(let id): return "move-\(id)"
        case .add: return "add"
        case .settings: return "settings"
        case .more(let day): return "more-\(day)"
        }
    }
}

@MainActor
@Observable
final class Sheets {
    var req: SheetReq?

    func open(_ next: SheetReq) {
        req = next
    }

    func close() {
        req = nil
    }
}

/// 照要求顯示對應的那一張卡。每張卡自己從環境拿 AppStore 和 Sheets
struct SheetRouter: View {
    let req: SheetReq

    var body: some View {
        switch req {
        case .reply:
            ReplySheet()
        case .map(let day):
            MapSheet(day: day)
        case .nearby(let day):
            NearbySheet(day: day)
        case .move(let id):
            MoveSheet(id: id)
        case .add:
            AddSheet()
        case .settings:
            TripSettingsSheet()
        case .more(let day):
            MoreSheet(day: day)
        }
    }
}
