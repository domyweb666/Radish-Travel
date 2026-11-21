// 彈出卡的總管：畫面只要說「打開哪一張」，同一時間只會有一張。
// 對應 mobile/src/sheets/host.tsx。
// 用法：`@Environment(Sheets.self) private var sheets`，然後 `sheets.open(.stop(id: it.id))`、`sheets.close()`。
import Observation
import SwiftUI

/// 相簿那張卡要看哪一趟：現在這趟，或某一趟已經收起來的
enum AlbumSource: Hashable {
    case current
    case basket(id: String)
}

enum SheetReq: Identifiable, Hashable {
    case stop(id: String)
    case chat
    case map(day: Int)
    case add
    case settings
    case more(day: Int)
    case album(AlbumSource)

    var id: String {
        switch self {
        case .stop(let id): return "stop-\(id)"
        case .chat: return "chat"
        case .map(let day): return "map-\(day)"
        case .add: return "add"
        case .settings: return "settings"
        case .more(let day): return "more-\(day)"
        case .album(let source):
            switch source {
            case .current: return "album-current"
            case .basket(let id): return "album-\(id)"
            }
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
        case .stop(let id):
            StopSheet(id: id)
        case .chat:
            ChatSheet()
        case .map(let day):
            MapSheet(day: day)
        case .add:
            AddSheet()
        case .settings:
            TripSettingsSheet()
        case .more(let day):
            MoreSheet(day: day)
        case .album(let source):
            AlbumSheet(source: source)
        }
    }
}
