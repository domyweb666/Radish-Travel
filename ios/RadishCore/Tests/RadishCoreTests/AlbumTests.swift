// 回來後的地圖網頁檔的測試。照 mobile/tests/trips.test.ts 裡測 albumHtml、sketchSvg 的那兩條搬。
import XCTest
@testable import RadishCore

final class AlbumTests: XCTestCase {
    /// TS 的 (s.match(/…/g) ?? []).length：某段字出現幾次
    private func count(_ s: String, _ piece: String) -> Int {
        return s.components(separatedBy: piece).count - 1
    }

    func test地圖網頁_使用者打的字不會變成網頁的程式() {
        let html: String = albumHtml(
            Album(
                title: "首爾 <5> 天",
                dates: "12/1–12/5",
                stops: [
                    AlbumStop(
                        n: "景福宮", kr: "경복궁", day: 1, date: "12/1（二）",
                        say: "</script><script>alert(1)</script>",
                        lat: 37.5796, lng: 126.977,
                        photos: ["data:image/jpeg;base64,AAAA"]
                    ),
                    AlbumStop(n: "自己加的店", day: 2, photos: []),
                ]
            )
        )
        XCTAssertFalse(html.contains("<script>alert(1)"), "那一句裡的標籤要被換掉")
        XCTAssertTrue(html.contains("首爾 &lt;5&gt; 天"))
        XCTAssertTrue(html.contains("第 1 天") && html.contains("第 2 天"))
        XCTAssertTrue(html.contains("有 1 站沒有位置資料"))
        XCTAssertEqual(count(html, "<article "), 2)
        XCTAssertTrue(html.contains("integrity=\"sha256-"), "外部的 Leaflet 要帶完整性雜湊")
    }

    func test路線圖_有位置的站各一個圓點_沒位置的不畫_一站也畫得出來() {
        let svg: String = sketchSvg([
            AlbumStop(n: "a", lat: 37.58, lng: 126.98, photos: []),
            AlbumStop(n: "b", photos: []),
            AlbumStop(n: "c", lat: 37.5, lng: 127.03, photos: []),
        ])
        XCTAssertEqual(count(svg, "class=\"pin\""), 2)
        XCTAssertFalse(svg.contains("NaN"))
        let one: String = sketchSvg([AlbumStop(n: "a", lat: 37.58, lng: 126.98, photos: [])])
        XCTAssertFalse(one.contains("NaN"))
        // Swift 把壞掉的數字印成小寫的 nan、inf，所以多查這兩種，上面那兩條才不會形同沒查
        XCTAssertFalse(svg.contains("nan") || svg.contains("inf"))
        XCTAssertFalse(one.contains("nan") || one.contains("inf"))
        XCTAssertEqual(sketchSvg([AlbumStop(n: "b", photos: [])]), "")
    }
}
