import XCTest

/// QC-0013 一站頁那三筆：建議停留（不再顯示為什麼排）、照片方塊、在這裡花的（韓元、台幣、刪掉再復原）。
/// 用場景 checked（第 2 天上午景福宮）直接開到那個狀態。找、捲、點的寫法照 SceneUITests。
final class StopQCUITests: RadishUITestCase {
    override var shotPrefix: String {
        let last: String = name.components(separatedBy: " ").last ?? name
        var method: String = last.replacingOccurrences(of: "]", with: "")
        if method.hasPrefix("test") {
            method = String(method.dropFirst(4))
        }
        return "StopQC-" + method
    }

    /* ---------- 找、捲、點（照 SceneUITests） ---------- */

    private func openScene(_ scene: String) {
        launch(reset: true, ["-uitest-scene", scene])
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

    /// 看得到、不會被講的那一列、分頁列、鍵盤蓋住的最下緣
    private func bottomLimit() -> CGFloat {
        var limit: CGFloat = app.frame.maxY - 34
        for id in ["tab-trip"] {
            let element: XCUIElement = byId(id)
            if element.exists && !element.frame.isEmpty {
                limit = min(limit, element.frame.minY - 8)
            }
        }
        let keyboard: XCUIElement = app.keyboards.firstMatch
        if keyboard.exists && !keyboard.frame.isEmpty {
            limit = min(limit, keyboard.frame.minY - 8)
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

    /// 識別碼可能掛在整格（小標加輸入框）上，先找真的輸入框
    private func fieldById(_ id: String) -> XCUIElement {
        for query in [app.textFields, app.textViews] {
            let hit: XCUIElement = query.matching(identifier: id).firstMatch
            if hit.exists { return hit }
        }
        return byId(id)
    }

    /// 捲到真的點得到的輸入框，點下去打字
    private func enter(_ id: String, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        bring(id, file: file, line: line)
        let field: XCUIElement = fieldById(id)
        XCTAssertTrue(field.isHittable, "點不到輸入框 \(id)", file: file, line: line)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "點了 \(id)，鍵盤沒有出來", file: file, line: line)
        field.typeText(text)
        pause()
    }

    /// 在這裡花的那幾筆
    private func spendRows() -> XCUIElementQuery {
        return app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "stop-spend-row-"))
    }

    /// 開第 2 天的景福宮那一頁
    private func openPalace() {
        openScene("checked")
        tapId("day-tab-2")
        pause()
        tapId("stop-row-p0")
        see("stop-show")
        pause()
    }

    /* ---------- 測試 ---------- */

    func test01建議停留_沒有為什麼排() {
        openPalace()
        shot("一站-最上面")
        let stay: XCUIElement = see("stop-stay")
        XCTAssertTrue(stay.label.contains("建議停留"), "建議停留那一列沒有小標：\(stay.label)")
        XCTAssertTrue(stay.label.contains("約"), "建議停留沒有寫約多久：\(stay.label)")
        XCTAssertTrue(stay.label.contains("粗估"), "建議停留沒有標粗估：\(stay.label)")
        XCTAssertEqual(anyElements(containing: "為什麼排").count, 0, "一站頁不該再有「為什麼排」")
        // 還沒去的站也有加照片的方塊
        bring("stop-add-photo")
        pause()
        shot("一站-照片方塊")
    }

    func test02在這裡花的_韓元台幣_刪掉再復原() {
        openPalace()
        bring("stop-spend-empty")
        shot("在這裡花的-還沒記")

        enter("stop-spend-amount", "12000")
        enter("stop-spend-note", "門票")
        tapId("stop-spend-add")
        pause()
        XCTAssertTrue(spendRows().firstMatch.waitForExistence(timeout: 8), "記了一筆，列表沒有出現")
        XCTAssertEqual(spendRows().count, 1)
        XCTAssertTrue(anyElements(containing: "₩ 12,000").count > 0, "記的那一筆沒有寫韓元金額")
        shot("在這裡花的-記了韓元")

        // 換台幣再記一筆：合計分開寫，不把台幣當韓元加
        bring("stop-spend-cur")
        app.buttons["台幣"].firstMatch.tap()
        enter("stop-spend-amount", "300")
        tapId("stop-spend-add")
        pause()
        XCTAssertEqual(spendRows().count, 2, "記了台幣那一筆，列表沒有變兩筆")
        XCTAssertTrue(anyElements(containing: "₩ 12,000 和 NT$ 300").count > 0, "合計沒有把韓元和台幣分開寫")
        shot("在這裡花的-韓元和台幣")

        // 點一筆刪掉，按復原回來
        let row: XCUIElement = spendRows().firstMatch
        let rowId: String = row.identifier
        tapId(rowId)
        pause()
        XCTAssertEqual(spendRows().count, 1, "點一筆沒有刪掉")
        see("notice-undo").tap()
        pause()
        XCTAssertEqual(spendRows().count, 2, "按了復原，那一筆沒有回來")
        shot("在這裡花的-復原之後")
    }
}
