import XCTest

/// 主流程：從空白開一趟 → 看排好的行程 → 拔一站 → 逛四個分頁 → 關掉重開資料還在。
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

    /// 第一次排好之後的操作說明會蓋住整個畫面，有出現就關掉。
    private func skipGuideIfShown() {
        let skip = idQuery("guide-skip")
        if waitUntil(timeout: 15, { self.visibleElement(in: skip) != nil }) {
            shot("操作說明第一步")
            visibleElement(in: skip)?.tap()
            // 不回頭問那顆按鈕還在不在：它正在消失時去問，XCUITest 會記一條失敗
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        }
    }

    private func startTrip() {
        launch()
        seeText("開一趟", timeout: 40)
        shot("開一趟-空白")
        tapId("cal-\(todayISO())")
        tapId("days-5")
        tapId("arrive-am")
        tapId("leave-pm")
        tapId("people-2")
        tapId("base-C")
        shot("開一趟-填到住哪")
        tapId("start-go")
        // 第一次排好會先跳操作說明，蓋住整個畫面；先關掉它才看得到每天的分頁
        skipGuideIfShown()
        scrollUp()
        scrollUp()
        requireVisible(idQuery("day-tab-1"), "第 1 天的分頁", timeout: 20)
    }

    func test01從空白開一趟到拔第一站() {
        startTrip()
        shot("這趟-排好了")
        scrollShots("這趟", count: 2)
        scrollUp()
        scrollUp()

        // 今天出發，所以是旅途中，「下一站」卡上可以拔
        let pull = idQuery("next-pull")
        if visibleElement(in: pull) != nil || waitUntil(timeout: 5, { self.visibleElement(in: pull) != nil }) {
            visibleElement(in: pull)?.tap()
            requireVisible(idQuery("pull-moment"), "拔蘿蔔動畫", timeout: 8)
            shot("拔蘿蔔")
            // 動畫播完會自己關，等它關掉就好
            RunLoop.current.run(until: Date().addingTimeInterval(5))
            XCTAssertFalse(idQuery("pull-moment").firstMatch.exists, "拔蘿蔔動畫沒有自己關掉")
            shot("拔完之後")
        } else {
            XCTFail("今天出發的行程，沒看到「去過了，拔起來」")
        }
    }

    func test02單站的卡與用講的改行程() {
        startTrip()
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "stop-row-"))
        scrollToSee(rows, "行程裡的一站").tap()
        seeText("關閉")
        shot("單站的卡")
        scrollShots("單站的卡", count: 1)
        tapButton("關閉")

        tapId("open-chat")
        requireVisible(idQuery("chat-input"), "對話輸入框")
        shot("用講的改行程")
        tapId("chat-hint-0")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("用講的改行程-講完一句")
        tapButton("關閉")

        tapId("open-map")
        seeText("關閉")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        shot("這天的地圖")
        tapButton("關閉")

        tapId("open-more")
        seeText("關閉")
        shot("更多")
        tapButton("關閉")
    }

    func test03四個分頁與重開留存() {
        startTrip()
        openTab("prep")
        seeText("行前")
        shot("行前")
        for stage in ["出發前", "在當地", "回程", "花費"] {
            tapButton(stage)
            shot("行前-\(stage)")
            scrollShots("行前-\(stage)", count: 1)
            scrollUp()
        }
        openTab("trips")
        seeText("旅行")
        shot("旅行")
        openTab("me")
        shot("我")
        scrollShots("我", count: 2)

        // 關掉重開：行程還在
        app.terminate()
        launch(reset: false)
        requireVisible(idQuery("day-tab-1"), "重開之後第 1 天的分頁", timeout: 40)
        shot("重開之後行程還在")
    }
}
