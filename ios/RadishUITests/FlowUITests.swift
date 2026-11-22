import XCTest

/// 主流程：從空白開一趟 → 看排好的行程 → 拔一站 → 一站、講一句、路線、附近 → 逛三個分頁和推進頁 → 關掉重開資料還在。
/// 每一步截一張圖，下載回來看畫面長得對不對。
final class FlowUITests: RadishUITestCase {
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

    /// 畫面最下面那幾層（講的那一列、分頁列）最上緣在哪
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
        tapClear("days-5")
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

    func test02一站與跟AI講() {
        startTrip()
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "stop-row-"))
        let row = scrollToSee(rows, "行程裡的一站")
        var tries = 0
        while row.frame.maxY > coverTop() - 16 && tries < 4 {
            scrollDown()
            tries += 1
        }
        row.tap()
        requireVisible(idQuery("stop-move"), "一站推進頁的移到別的時段", timeout: 10)
        shot("一站")
        scrollShots("一站", count: 2)
        tapClear("stop-move")
        seeText("關閉")
        shot("移到別的時段")
        tapButton("關閉")
        goBack()

        // 這一天最下面講的那一列：點第一個說法，升起剛剛那一則
        scrollUp()
        scrollUp()
        shot("這一天最下面的講")
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

        tapClear("open-map")
        seeText("路線")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        shot("這天的路線")
        scrollShots("這天的路線", count: 1)
        tapButton("關閉")

        // 更多在右上角，捲回最上面才看得到
        scrollUp()
        scrollUp()
        scrollUp()
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
