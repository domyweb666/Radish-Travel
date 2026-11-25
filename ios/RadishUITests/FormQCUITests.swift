import XCTest

/// QC-0013 #104、#105：開一趟在月曆上點出發日和回來那天、平常的我多一列住宿偏好。
/// 每一步截一張圖。寫法照 FlowUITests 開頭：從空白開，捲到看得到再點。
final class FormQCUITests: RadishUITestCase {
    /// 每條測試的檔名不一樣，流水號相同也不會互蓋
    override var shotPrefix: String {
        let last: String = name.components(separatedBy: " ").last ?? name
        var method: String = last.replacingOccurrences(of: "]", with: "")
        if method.hasPrefix("test") {
            method = String(method.dropFirst(4))
        }
        return "FormQC-" + method
    }

    /// 今天往後第幾天的 'YYYY-MM-DD'（西元、模擬器當地時區，跟 app 的 todayISO 一樣）
    private func dayISO(_ offset: Int) -> String {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let date: Date = cal.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

    /// 往下捲到看得到、不被最下面那幾層蓋住再點
    private func tapClear(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = scrollToSee(idQuery(identifier), "識別碼 \(identifier)", file: file, line: line)
        var tries = 0
        while element.frame.maxY > coverTop() - 16 && tries < 4 {
            scrollDown()
            tries += 1
        }
        element.tap()
    }

    /// 月曆上點某一天。那天不在現在這個月就翻一頁（先往後，不對再往前）
    private func tapDay(_ iso: String, file: StaticString = #filePath, line: UInt = #line) {
        let id: String = "cal-\(iso)"
        if !idQuery(id).firstMatch.waitForExistence(timeout: 2) {
            // 翻頁的箭頭在月曆最上面，剛剛點下面幾排時可能被捲到畫面外
            if visibleElement(in: idQuery("cal-next")) == nil { scrollUp() }
            tapClear("cal-next", file: file, line: line)
            if !idQuery(id).firstMatch.waitForExistence(timeout: 2) {
                tapClear("cal-prev", file: file, line: line)
                tapClear("cal-prev", file: file, line: line)
            }
        }
        tapClear(id, file: file, line: line)
    }

    /// 月曆上面那一行現在寫什麼
    private func rangeText() -> String {
        let el: XCUIElement = idQuery("trip-range").firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 5), "沒看到月曆上面那一行")
        return el.label
    }

    func test01月曆點兩下選出發和回來() {
        launch()
        seeText("開一趟", timeout: 40)
        XCTAssertFalse(idQuery("days-5").firstMatch.exists, "去幾天那排按鈕應該拿掉了")
        XCTAssertTrue(rangeText().contains("點出發那天"), rangeText())

        tapDay(dayISO(0))
        XCTAssertTrue(rangeText().contains("再點回來那天"), rangeText())
        shot("點了出發日")

        tapDay(dayISO(7))
        let picked: String = rangeText()
        XCTAssertTrue(picked.contains("共 8 天"), picked)
        XCTAssertTrue(picked.contains("回來"), picked)
        shot("點了回來那天-共8天")

        // 再點一下就從出發日重選；太近的回來那天不收，講原因
        tapDay(dayISO(1))
        XCTAssertTrue(rangeText().contains("再點回來那天"), rangeText())
        tapDay(dayISO(2))
        let note: XCUIElement = idQuery("trip-range-note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("最少去 3 天"), note.label)
        XCTAssertTrue(rangeText().contains("再點回來那天"), "太近的不該選上：\(rangeText())")
        shot("回來那天太近")

        tapDay(dayISO(4))
        XCTAssertTrue(rangeText().contains("共 4 天"), rangeText())
        shot("重選之後-共4天")
    }

    func test02平常的我有住宿偏好() {
        launch(reset: true, ["-uitest-scene", "plan"])
        let me: XCUIElement = idQuery("open-me").firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 40), "沒看到平常的我的入口")
        me.tap()
        let row: XCUIElement = scrollToSee(idQuery("me-row-stay"), "住宿偏好那一列")
        XCTAssertTrue(hasText("住宿偏好"), "那一列的字不是住宿偏好")
        shot("平常的我-住宿偏好")
        row.tap()
        seeText("五星級飯店")
        seeText("便宜就好（青旅、民宿）")
        shot("住宿偏好-選項")
    }
}
