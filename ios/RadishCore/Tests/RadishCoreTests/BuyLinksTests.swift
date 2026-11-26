// Klook、KKday 連結表：排行程那一邊碰不到、三個連結順序固定、表裡只放要先訂又不是吃的站。
// 規則在 docs/聯盟連結-排序規則-草案.md。
import XCTest

@testable import RadishCore

/// Sources/RadishCore 資料夾：從這支測試檔往上找
private func coreSourcesDir() -> URL {
    let here: URL = URL(fileURLWithPath: #filePath)
    let root: URL = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return root.appendingPathComponent("Sources").appendingPathComponent("RadishCore")
}

private func placeOf(_ id: String) -> Place? {
    return PLACES.first { (p: Place) -> Bool in p.id == id }
}

private let FAKE: BuyLink = BuyLink(klook: "https://www.klook.com/activity/1", kkday: "https://www.kkday.com/product/2")

final class BuyLinksTests: XCTestCase {
    /// 排序沒有私心：除了 BuyLinks.swift，規則引擎裡沒有一支檔提到連結表或分潤。
    /// 哪天有人把它接進排行程、換一個、附近、AI 提示詞，這條會紅
    func testOnlyBuyLinksFileKnowsTheTable() throws {
        let dir: URL = coreSourcesDir()
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let swift: [String] = names.filter { (n: String) -> Bool in n.hasSuffix(".swift") }
        XCTAssertTrue(swift.contains("BuyLinks.swift"), "找不到 \(dir.path)/BuyLinks.swift，資料夾找錯了")
        XCTAssertTrue(swift.count > 5, "\(dir.path) 裡的 .swift 太少，資料夾找錯了")
        let banned: [String] = ["BuyLink", "buyLink", "buy-links", "affiliate"]
        for name in swift where name != "BuyLinks.swift" {
            let text: String = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(name) 提到了「\(word)」：連結表只給畫面用，排行程和 AI 不准讀")
            }
        }
    }

    func testOrderIsFixed() {
        let all: [BuyOption] = buyOptions(official: "https://www.royal.example.kr", FAKE)
        XCTAssertEqual(all.map { (o: BuyOption) -> BuyShop in o.shop }, [.official, .klook, .kkday])
        XCTAssertEqual(all.map { (o: BuyOption) -> String in o.url }, [
            "https://www.royal.example.kr", "https://www.klook.com/activity/1", "https://www.kkday.com/product/2",
        ])
        XCTAssertEqual(BuyShop.allCases.map { (s: BuyShop) -> String in s.name }, ["官網", "Klook", "KKday"])
        XCTAssertFalse(BuyShop.official.earns)
        XCTAssertTrue(BuyShop.klook.earns)
        XCTAssertTrue(BuyShop.kkday.earns)
    }

    func testSkipsEmptyAndNotWeb() {
        let some: [BuyOption] = buyOptions(official: "", BuyLink(klook: "klook 那頁", kkday: "https://www.kkday.com/product/2"))
        XCTAssertEqual(some.map { (o: BuyOption) -> BuyShop in o.shop }, [.kkday])
        let noOfficial: [BuyOption] = buyOptions(official: nil, FAKE)
        XCTAssertEqual(noOfficial.map { (o: BuyOption) -> BuyShop in o.shop }, [.klook, .kkday])
        XCTAssertTrue(buyOptions(official: nil, nil).isEmpty)
        XCTAssertTrue(buyOptions(official: "", BuyLink(klook: "", kkday: nil)).isEmpty)
        XCTAssertTrue(buyOptions(official: "ftp://x.example.com", BuyLink(klook: "mailto:a@b.c", kkday: " ")).isEmpty)
    }

    /// 要先訂、不是吃的才有；不用先訂的、吃的，表裡有也不放
    func testOnlyBookedNotFood() throws {
        let table: BuyLinkTable = BuyLinkTable(links: ["p6": FAKE, "p0": FAKE, "p16b": FAKE])
        let garden: Place = try XCTUnwrap(placeOf("p6"))
        let palace: Place = try XCTUnwrap(placeOf("p0"))
        let dinner: Place = try XCTUnwrap(placeOf("p16b"))
        XCTAssertEqual(affiliateOptions(planToStop(garden, "測試"), table).map { (o: BuyOption) -> BuyShop in o.shop }, [.klook, .kkday])
        XCTAssertTrue(affiliateOptions(planToStop(palace, "測試"), table).isEmpty, "景福宮不用先訂，不放連結")
        XCTAssertTrue(affiliateOptions(planToStop(dinner, "測試"), table).isEmpty, "吃的不放連結")
        XCTAssertTrue(hasAffiliate(table))
        XCTAssertFalse(hasAffiliate(BuyLinkTable(links: ["p6": BuyLink(klook: nil, kkday: "")])))
    }

    func testBundledTableKeysAreBookedNotFood() throws {
        let table: BuyLinkTable = try XCTUnwrap(BuyLinkTable.bundled(), "buy-links.json 沒有打包或讀不出來")
        XCTAssertFalse(table.links.isEmpty)
        for id in table.links.keys {
            guard let p = placeOf(id) else {
                XCTFail("buy-links.json 的 \(id) 不是地點代號")
                continue
            }
            XCTAssertTrue(needsBook(planToStop(p, "測試")), "\(id) \(p.n) 不用先訂，不該在連結表裡")
            XCTAssertFalse(p.c == .eat || p.c == .cafe, "\(id) \(p.n) 是吃的，不該在連結表裡")
        }
    }

    /// 還沒有聯盟網址，表裡全是空的，畫面跟沒有這份表一樣。拿到網址填進去之後，這條改成檢查有填的都是 klook.com、kkday.com
    func testBundledTableIsStillEmpty() throws {
        let table: BuyLinkTable = try XCTUnwrap(BuyLinkTable.bundled())
        XCTAssertFalse(hasAffiliate(table))
    }
}
