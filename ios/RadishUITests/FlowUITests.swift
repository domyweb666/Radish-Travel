import XCTest

/// 主流程：從空白開一趟 → 看排好的行程 → 拔一站 → 一站、講一句、路線、附近 → 逛三個分頁和推進頁 → 關掉重開資料還在。
/// 每一步截一張圖，下載回來看畫面長得對不對。
final class FlowUITests: RadishUITestCase {
    /// 今天往後第幾天，yyyy-MM-dd
    private func isoAfter(_ offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date().addingTimeInterval(Double(offset) * 86400))
    }

    private func todayISO() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 往下捲到看得到那個識別碼的東西再點。
    private func tapId(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        scrollToSee(idQuery(identifier), "識別碼 \(identifier)", file: file, line: line).tap()
    }

    /// 同 tapId，但元件被畫面最下面的東西（懸浮分頁列、講的那一列）蓋住時再往下捲。
    /// isHittable 只看元件中心在不在螢幕裡，不管有沒有被蓋住；直接點會點到上面那層。
    /// 只用在分頁頁面和推進頁上；彈出卡會蓋住這兩列，用 tapId
    private func tapClear(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = scrollToSee(idQuery(identifier), "識別碼 \(identifier)", file: file, line: line)
        var tries = 0
        while element.frame.maxY > coverTop() - 16 && tries < 4 {
            scrollDown()
            tries += 1
        }
        element.tap()
    }

    /// 畫面最下面那幾層（一站頁講的那一列、分頁列）最上緣在哪。這趟分頁最下面沒有講的那一列了（QC-0013）
    private func coverTop() -> CGFloat {
        var top = app.frame.maxY
        for id in ["tab-trip", "talk-hint-0", "talk-input"] {
            let el = app.descendants(matching: .any).matching(identifier: id).firstMatch
            if el.exists && !el.frame.isEmpty {
                top = min(top, el.frame.minY)
            }
        }
        return top
    }

    /// 這趟分頁黏在上面的地圖和天數分頁的下緣。不在這趟分頁就是 0。
    /// 捲到那一塊底下的站，isHittable 還是對的，點下去會點到地圖
    private func pinBottom() -> CGFloat {
        let tab = idQuery("day-tab-1").firstMatch
        if tab.exists && !tab.frame.isEmpty && tab.frame.maxY.isFinite {
            return tab.frame.maxY
        }
        return 0
    }

    /// 這趟分頁捲回最上面：右上角的更多看得到為止
    private func scrollToTop() {
        for _ in 0..<8 where visibleElement(in: idQuery("open-more")) == nil {
            scrollUp()
        }
    }

    /// 有出現就點，沒出現就算了（看狀態才會有的按鈕）
    @discardableResult
    private func tapIfShown(_ identifier: String, timeout: TimeInterval = 3) -> Bool {
        let query = idQuery(identifier)
        if waitUntil(timeout: timeout, { self.visibleElement(in: query) != nil }) {
            visibleElement(in: query)?.tap()
            return true
        }
        return false
    }

    private func startTrip() {
        launch()
        seeText("開一趟", timeout: 40)
        shot("開一趟-空白")
        tapClear("cal-\(todayISO())")
        // 回來那天直接點月曆（QC-0013 #104）：今天出發、第 5 天回來
        let end: String = isoAfter(4)
        if !idQuery("cal-\(end)").firstMatch.waitForExistence(timeout: 2) {
            tapClear("cal-next")
        }
        tapClear("cal-\(end)")
        tapClear("arrive-am")
        tapClear("leave-pm")
        tapClear("people-2")
        tapClear("base-C")
        shot("開一趟-填到住哪")
        tapClear("start-go")
        scrollUp()
        scrollUp()
        requireVisible(idQuery("day-tab-1"), "第 1 天的分頁", timeout: 20)
    }

    func test01從空白開一趟到拔第一站() {
        startTrip()
        shot("這趟-排好了")
        scrollShots("這趟", count: 3)
        scrollUp()
        scrollUp()
        scrollUp()

        // 今天出發，所以是旅途中，「下一站」卡上可以拔
        tapClear("next-pull")
        requireVisible(idQuery("pull-moment"), "拔蘿蔔動畫", timeout: 8)
        shot("拔蘿蔔")
        // 動畫播完會自己關，等它關掉就好
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        XCTAssertFalse(idQuery("pull-moment").firstMatch.exists, "拔蘿蔔動畫沒有自己關掉")
        shot("拔完之後")

        // 下一站卡上的附近還有什麼（半頁）
        scrollUp()
        scrollUp()
        if visibleElement(in: idQuery("next-nearby")) != nil || waitUntil(timeout: 3, { self.visibleElement(in: self.idQuery("next-nearby")) != nil }) {
            tapClear("next-nearby")
            seeText("附近還有什麼")
            shot("附近還有什麼")
            tapButton("關閉")
        }
    }

    /// 行程裡整個露出來的一站：在黏在上面那一塊下面、分頁列上面。沒有就往下捲
    private func clearStopRow() -> XCUIElement {
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "stop-row-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "清單裡沒有站")
        for _ in 0..<8 {
            let top = pinBottom()
            let bottom = coverTop() - 16
            let hit = rows.allElementsBoundByIndex.first { (row: XCUIElement) -> Bool in
                let f = row.frame
                return row.exists && !f.isEmpty && f.minY >= top && f.maxY <= bottom
            }
            if let hit { return hit }
            scrollDown()
        }
        XCTFail("捲了八次，還是沒有整個露出來的一站")
        return rows.firstMatch
    }

    func test02一站與跟AI講() {
        startTrip()
        clearStopRow().tap()
        XCTAssertTrue(idQuery("stop-move").firstMatch.waitForExistence(timeout: 10), "沒有進到一站推進頁")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        shot("一站")
        // 有核對資料的站第一頁放不下，但最多捲兩次就要整顆看得到、不被講的那一列蓋住
        let move: XCUIElement = idQuery("stop-move").firstMatch
        for _ in 0..<2 where move.frame.maxY > coverTop() - 16 {
            scrollDown()
        }
        XCTAssertLessThanOrEqual(move.frame.maxY, coverTop(), "捲了兩次，移到別的時段還沒整顆露出來")
        shot("一站-移到別的時段")
        move.tap()
        seeText("關閉")
        shot("移到別的時段")
        tapButton("關閉")
        scrollShots("一站", count: 2)

        // 這趟分頁最下面沒有講的那一列了（QC-0013 #95），改在一站最下面那一列：點第一個說法，升起剛剛那一則
        shot("一站最下面的講")
        tapId("talk-hint-0")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("剛剛那一則")
        if tapIfShown("chat-ask-apply") {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            shot("剛剛那一則-按了套用")
        }
        if !tapIfShown("reply-done") {
            tapIfShown("reply-skip")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        goBack()
        XCTAssertFalse(idQuery("talk-input").firstMatch.exists, "這趟分頁最下面不該再有講的那一列")

        // 這一天的地圖黏在上面，捲到清單中間也看得到，點了開這天的路線
        tapClear("open-map")
        seeText("路線")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        shot("這天的路線")
        scrollShots("這天的路線", count: 1)
        tapButton("關閉")

        // 更多在右上角，捲回最上面才看得到
        scrollToTop()
        tapId("open-more")
        seeText("關閉")
        shot("更多")
        tapButton("關閉")
    }

    func test03三個分頁推進頁與重開留存() {
        startTrip()
        scrollUp()

        // 標題下面的兩個常駐入口：檢查這趟、須知（推進）
        tapId("open-check")
        seeText("檢查這趟")
        shot("檢查這趟")
        scrollShots("檢查這趟", count: 2)
        goBack()

        tapId("open-notes")
        seeText("須知")
        for part in ["在當地", "按天", "回程"] {
            tapButton(part)
            shot("須知-\(part)")
            scrollShots("須知-\(part)", count: 1)
            scrollUp()
        }
        goBack()

        // 右上角：更多（半頁）裡的花費推進一頁；平常的我推進一頁
        tapId("open-more")
        seeText("關閉")
        tapId("more-cost")
        seeText("花費", timeout: 10)
        shot("花費")
        scrollShots("花費", count: 1)
        goBack()

        tapId("open-me")
        seeText("平常的我")
        shot("平常的我")
        scrollShots("平常的我", count: 3)
        goBack()

        openTab("ask")
        requireVisible(idQuery("chat-input"), "問 AI 分頁的輸入框")
        shot("問 AI")
        tapId("chat-hint-0")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("問 AI-講完一句")
        if tapIfShown("chat-ask-apply") {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            shot("問 AI-按了套用")
        }

        openTab("trips")
        seeText("旅行")
        shot("旅行")
        if tapIfShown("trips-album-current") {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            shot("去過的那一趟")
            goBack()
        }
        openTab("trip")
        requireVisible(idQuery("day-tab-1"), "切回這趟，第 1 天的分頁")

        // 關掉重開：行程還在
        app.terminate()
        launch(reset: false)
        requireVisible(idQuery("day-tab-1"), "重開之後第 1 天的分頁", timeout: 40)
        shot("重開之後行程還在")
    }
}
