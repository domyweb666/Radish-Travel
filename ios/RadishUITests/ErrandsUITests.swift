import XCTest

/// 代購：從這趟標題下面的「代購」進去，加一樣、點一下勾買到、按復原退回還沒買。
/// 用現有的場景 plan（出發前的一趟，沒有代購）開，不另外做場景。找、捲、點的寫法照 StopQCUITests。
final class ErrandsUITests: RadishUITestCase {
    override var shotPrefix: String {
        let last: String = name.components(separatedBy: " ").last ?? name
        var method: String = last.replacingOccurrences(of: "]", with: "")
        if method.hasPrefix("test") {
            method = String(method.dropFirst(4))
        }
        return "Errands-" + method
    }

    /* ---------- 找、捲、點（照 StopQCUITests） ---------- */

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

    /// 看得到、不會被分頁列、鍵盤蓋住的最下緣
    private func bottomLimit() -> CGFloat {
        var limit: CGFloat = app.frame.maxY - 34
        let tab: XCUIElement = byId("tab-trip")
        if tab.exists && !tab.frame.isEmpty {
            limit = min(limit, tab.frame.minY - 8)
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

    /// 捲到整個看得到。在上面就往回捲，在下面就往下捲；捲不動了就停。
    /// 這趟頁的「代購」在黏在上面那一塊（地圖、天數分頁）的上面，不會被蓋住
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
            if before.minY < 64 {
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

    /// 識別碼掛在整格（小標加輸入框）上，先找真的輸入框
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
        // 打完按換行收鍵盤：下一格可能在鍵盤底下，捲不到
        field.typeText(text + "\n")
        pause()
    }

    /// 代購的每一列（點了勾買到的那一格）
    private func rows() -> XCUIElementQuery {
        return app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "errand-row-"))
    }

    /// 那一列現在念的是買到了還是還沒買
    private func state(_ element: XCUIElement) -> String {
        return (element.value as? String) ?? ""
    }

    /* ---------- 測試 ---------- */

    func test01加一樣_勾買到_復原() {
        openScene("plan")
        tapId("open-errands")
        see("errands-empty")
        pause()
        shot("代購-空的")

        enter("errand-what", "面膜")
        enter("errand-who", "媽媽")
        tapId("errand-add")
        pause()
        XCTAssertTrue(rows().firstMatch.waitForExistence(timeout: 8), "加了一樣，列表沒有出現")
        XCTAssertEqual(rows().count, 1)
        XCTAssertFalse(byId("errands-empty").exists, "加了一樣，空白說明還在")
        XCTAssertTrue(see("errands-left").label.contains("還差 1 樣"), "最上面沒有寫還差 1 樣")
        XCTAssertTrue(anyElements(containing: "媽媽").count > 0, "沒有照誰託的分組")
        shot("代購-加了一樣")

        // 點一下勾買到
        let rowId: String = rows().firstMatch.identifier
        tapId(rowId)
        pause()
        XCTAssertEqual(state(byId(rowId)), "買到了", "點了那一列沒有勾起來")
        XCTAssertTrue(see("errands-left").label.contains("都買到了"), "勾完最上面沒有寫都買到了")
        shot("代購-勾買到")

        // 按提示條的復原，退回還沒買
        see("notice-undo").tap()
        pause()
        XCTAssertEqual(state(byId(rowId)), "還沒買", "按了復原，那一列沒有退回還沒買")
        XCTAssertTrue(see("errands-left").label.contains("還差 1 樣"), "復原之後最上面沒有改回還差 1 樣")
        shot("代購-復原之後")
    }
}
