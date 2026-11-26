// 要先訂的站，除了官網，還能在哪裡買：Klook、KKday 的商品頁。資料在 Resources/buy-links.json。
// 透過 Klook、KKday 的連結買，蘿蔔旅行會拿到一點分潤，所以這份表只給畫面顯示用：
// 站已經排進這趟、一站頁和檢查這趟要顯示的時候才來查。
// 排這趟、換一個、附近還有什麼、給 AI 的提示詞，都不准讀這份表，也不准知道哪一站有分潤（鐵則：排序沒有私心）。
// BuyLinksTests 會掃這個資料夾的每一支檔，除了這一支，誰提到這份表測試就紅。
// 順序固定：官網、Klook、KKday，不看哪家便宜（我們沒有即時價格）。
// 規則的來由寫在 docs/聯盟連結-排序規則-草案.md。
import Foundation

/// 一個地點在兩家的商品頁。沒有就是 nil
struct BuyLink: Codable, Hashable, Sendable {
    var klook: String?
    var kkday: String?
}

/// 整份表，鍵是地點代號
struct BuyLinkTable: Codable, Hashable, Sendable {
    var links: [String: BuyLink]

    static let shared: BuyLinkTable = bundled() ?? BuyLinkTable(links: [:])

    /// UI 測試塞假資料用（UITestScenes 的 -uitest-buylinks）。平常是 nil
    nonisolated(unsafe) static var override: BuyLinkTable?

    /// 跟著 app 打包的那一份。讀不到、讀不出來是 nil：畫面當成沒有連結，不讓 app 當掉
    static func bundled() -> BuyLinkTable? {
        #if SWIFT_PACKAGE
            let bundle: Bundle = Bundle.module
        #else
            let bundle: Bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "buy-links", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(BuyLinkTable.self, from: data)
    }
}

/// 畫面要用的那一份：測試塞的假表優先
func buyLinkTable() -> BuyLinkTable {
    return BuyLinkTable.override ?? BuyLinkTable.shared
}

/// 在哪裡買。順序就是畫面上的順序
enum BuyShop: String, CaseIterable, Hashable, Sendable {
    case official, klook, kkday

    var name: String {
        switch self {
        case .official: return "官網"
        case .klook: return "Klook"
        case .kkday: return "KKday"
        }
    }

    /// 透過這裡買，蘿蔔旅行會拿到分潤
    var earns: Bool {
        return self != .official
    }
}

struct BuyOption: Identifiable, Hashable, Sendable {
    var shop: BuyShop
    var url: String

    var id: BuyShop {
        return shop
    }
}

/// 官網、Klook、KKday 照固定順序排，空的、不是網址的跳過
func buyOptions(official: String?, _ link: BuyLink?) -> [BuyOption] {
    let pairs: [(shop: BuyShop, url: String?)] = [
        (shop: BuyShop.official, url: official),
        (shop: BuyShop.klook, url: link?.klook),
        (shop: BuyShop.kkday, url: link?.kkday),
    ]
    var out: [BuyOption] = []
    for pair in pairs {
        guard let url = pair.url, bookHost(url) != nil else { continue }
        out.append(BuyOption(shop: pair.shop, url: url))
    }
    return out
}

/// 吃的、咖啡都不放連結
private func buyIsFood(_ c: Cat) -> Bool {
    return c == .eat || c == .cafe
}

/// 一站要接在官網後面的 Klook、KKday。只有要先訂、不是吃的才有；官網照舊由 BookInfo.url 那邊負責
func affiliateOptions(_ it: Stop, _ table: BuyLinkTable) -> [BuyOption] {
    guard needsBook(it), !buyIsFood(it.c) else { return [] }
    return buyOptions(official: nil, table.links[it.id])
}

/// 表裡有沒有任何一個真的網址。沒有就不用講分潤
func hasAffiliate(_ table: BuyLinkTable) -> Bool {
    return table.links.values.contains { (l: BuyLink) -> Bool in
        !buyOptions(official: nil, l).isEmpty
    }
}
