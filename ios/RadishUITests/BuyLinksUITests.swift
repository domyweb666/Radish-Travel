import XCTest

/// Klook、KKday 連結：帶 -uitest-buylinks（假的連結表）時，一站頁的訂票頁下面多兩顆、平常的我多「排序和連結」；
/// 不帶就跟原本一模一樣。用場景 checked（第 2 天下午昌德宮與後苑 p6，要先訂）。找、捲、點的寫法照 StopQCUITests。
final class BuyLinksUITests: RadishUITestCase {
    override var shotPrefix: String {
        let last: String = name.components(separatedBy: " ").last ?? name
        var method: String = last.replacingOccurrences(of: "]", with: "")
        if method.hasPrefix("test") {
            method = String(method.dropFirst(4))
        }
        return "BuyLinks-" + method
    }

    /* ---------- 找、捲、點（照 StopQCUITests） ---------- */

    private func openScene(_ scene: String, _ extra: [String] = []) {
        launch(reset: true, ["-uitest-scene", scene] + extra)
        see("tab-trip", timeout: 40)
    }

    private func byId(_ id: String) -> XCUIElement {
        return idQuery(id).firstMatch
    }

    @discardableResult
    private func see(
        _ id: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let element: XCUIElement = byId(id)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "沒看到識別碼 \(id)", file: file, line: line)
        return element
    }

    private func pause(_ seconds: TimeInterval = 1) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func drag(_ from: CGFloat, _ to: CGFloat) {
        let a: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let b: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: 0.2)
    }

    /// 看得到、不會被分頁列蓋住的最下緣
    private func bottomLimit() -> CGFloat {
        var limit: CGFloat = app.frame.maxY - 34
        let tab: XCUIElement = byId("tab-trip")
        if tab.exists && !tab.frame.isEmpty {
            limit = min(limit, tab.frame.minY - 8)
        }
        return limit
    }

    private func placed(_ frame: CGRect) -> Bool {
        return !frame.isEmpty && !frame.isInfinite && frame.minY.isFinite && frame.maxY.isFinite
    }

    /// 黏在上面那一塊（這天的地圖和天數分頁）佔的上下緣。不在這趟頁就是 nil
    private func pinBand() -> (top: CGFloat, bottom: CGFloat)? {
        let map: XCUIElement = byId("open-map")
        let tab: XCUIElement = byId("day-tab-1")
        guard map.exists, tab.exists, placed(map.frame), placed(tab.frame) else { return nil }
        return (top: map.frame.minY, bottom: tab.frame.maxY)
    }

    /// 是不是黏在上面那一塊裡面的東西（地圖、天數分頁）
    private func inPin(_ id: String) -> Bool {
        return id == "open-map" || id.hasPrefix("day-tab-")
    }

    /// 捲到整個看得到。在上面就往回捲，在下面就往下捲；捲不動了就停
    @discardableResult
    private func bring(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element: XCUIElement = see(id, file: file, line: line)
        var lost: Int = 0
        for _ in 0..<16 {
            let before: CGRect = element.frame
            if !placed(before) {
                lost += 1
                if lost <= 5 {
                    drag(0.66, 0.3)
                } else {
                    drag(0.3, 0.62)
                }
                continue
            }
            let band: (top: CGFloat, bottom: CGFloat)? = inPin(id) ? nil : pinBand()
            // 狀態列底下點不到；黏在上面的地圖和天數分頁底下也點不到（點下去會開這天的路線）
            if before.minY < 64 {
                drag(0.3, 0.62)
            } else if let band, before.minY < band.bottom, before.maxY > band.top {
                drag(0.3, 0.62)
            } else if before.maxY > bottomLimit() {
                drag(0.66, 0.3)
            } else {
                break
            }
            if element.frame == before { break }
        }
        return element
    }

    private func tapId(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        bring(id, file: file, line: line).tap()
    }

    /// 開第 2 天下午的昌德宮與後苑（要先訂）
    private func openGarden(_ extra: [String]) {
        openScene("checked", extra)
        tapId("day-tab-2")
        pause()
        tapId("stop-row-p6")
        see("stop-show")
        pause()
    }

    /* ---------- 測試 ---------- */

    func test01一站頁_官網下面接Klook和KKday() {
        openGarden(["-uitest-buylinks"])
        let official: XCUIElement = bring("stop-book-open")
        let klook: XCUIElement = bring("stop-buy-klook")
        let kkday: XCUIElement = see("stop-buy-kkday")
        pause()
        XCTAssertTrue(klook.label.contains("在 Klook 看"), "Klook 那顆的字不對：\(klook.label)")
        XCTAssertTrue(kkday.label.contains("在 KKday 看"), "KKday 那顆的字不對：\(kkday.label)")
        // 順序固定：官網、Klook、KKday，由上往下
        XCTAssertGreaterThanOrEqual(klook.frame.minY, official.frame.maxY, "Klook 沒有排在打開訂票頁下面")
        XCTAssertGreaterThanOrEqual(kkday.frame.minY, klook.frame.maxY, "KKday 沒有排在 Klook 下面")
        // 連結旁邊不寫分潤
        XCTAssertEqual(anyElements(containing: "分潤").count, 0, "一站頁不該寫分潤，分潤在平常的我講")
        shot("一站頁-怎麼訂")
    }

    func test02平常的我_排序和連結() {
        openScene("plan", ["-uitest-buylinks"])
        see("open-me").tap()
        let row: XCUIElement = scrollToSee(idQuery("me-row-buylinks"), "排序和連結那一列")
        shot("平常的我-排序和連結那一列")
        row.tap()
        seeText("分潤")
        XCTAssertFalse(hasText("價格一樣"), "條款還沒確認，不能寫價格一樣")
        shot("排序和連結-說明")
    }

    func test03沒有連結_一站頁跟原本一樣() {
        openGarden([])
        bring("stop-book-open")
        pause()
        XCTAssertFalse(byId("stop-buy-klook").exists, "沒有連結表，不該有 Klook 那顆")
        XCTAssertFalse(byId("stop-buy-kkday").exists, "沒有連結表，不該有 KKday 那顆")
        shot("一站頁-沒有連結")
    }
}
