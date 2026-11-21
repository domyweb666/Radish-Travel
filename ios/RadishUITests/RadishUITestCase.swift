import XCTest

/// UI 測試的共用底座：開 app、找元件、截圖。
///
/// 這台開發機是 Windows，沒有模擬器。畫面的機器自審靠這個：GitHub Actions 的 macOS 機器
/// 開模擬器跑這些測試，每個畫面截一張圖，下載回來看。
/// 截圖兩份：寫成 PNG 到環境變數 RADISH_SCREENSHOT_DIR 指的資料夾（xcodebuild 用
/// TEST_RUNNER_RADISH_SCREENSHOT_DIR 傳進來），也附進 .xcresult。
///
/// app 收到啟動參數 -uitest-reset 時會先刪掉存檔，從空白開始。
class RadishUITestCase: XCTestCase {
    var app: XCUIApplication!
    private var shotIndex = 0
    private var shotDir: URL?
    /// 正在截「失敗現場」。截圖自己出錯時不要再截一次。
    private var isShootingFailure = false

    /// 任何一個檢查沒過，先截一張「失敗現場」再照常記錄，看圖就知道當時畫面停在哪。
    override func record(_ issue: XCTIssue) {
        if !isShootingFailure {
            isShootingFailure = true
            shot("失敗現場")
            isShootingFailure = false
        }
        super.record(issue)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        if let dir = ProcessInfo.processInfo.environment["RADISH_SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            shotDir = url
        }
        // 萬一跳出系統對話框（通知、定位），按同意讓流程走下去
        addUIInterruptionMonitor(withDescription: "系統對話框") { alert in
            for title in ["允許", "使用 App 期間允許", "Allow", "Allow While Using App", "好", "OK"]
            where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    /// 開 app。reset 為 true 時從空白開始；重開看資料還在不在時傳 false。
    func launch(reset: Bool = true, _ extra: [String] = []) {
        app.launchArguments = (reset ? ["-uitest-reset"] : []) + ["-uitest"] + extra
        app.launch()
    }

    /// 截一張圖。檔名前面自動加流水號，照走的順序排。
    func shot(_ name: String) {
        shotIndex += 1
        let prefix = String(describing: type(of: self)).replacingOccurrences(of: "UITests", with: "")
        let fileName = String(format: "%@-%02d-%@", prefix, shotIndex, name)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let shotDir else { return }
        do {
            let url = shotDir.appendingPathComponent(fileName + ".png")
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("截圖寫不進 \(shotDir.path)：\(error)")
        }
    }
}

// MARK: 等待與尋找

extension RadishUITestCase {
    /// 等到條件成立，沒等到回 false。每隔一小段重看一次，不是固定睡幾秒。
    @discardableResult
    func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// 用 identifier 找元素，不管它是哪一種元件。
    func idQuery(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// label 含某段字的元素，不管哪一種元件（合併成一個元素的列、卡片用這個找）。
    func anyElements(containing part: String) -> XCUIElementQuery {
        let predicate = NSPredicate(format: "label CONTAINS %@", part)
        return app.descendants(matching: .any).matching(predicate)
    }

    /// label 或 identifier 剛好是這個字。
    func named(_ text: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR identifier == %@", text, text)
    }

    /// 查詢結果裡現在真的在畫面上、點得到的那一個。被表單蓋住的不算。
    func visibleElement(in query: XCUIElementQuery) -> XCUIElement? {
        query.allElementsBoundByIndex.first { element in
            guard element.exists else { return false }
            // 表單還在長出來的那一瞬間，元素的 frame 是空的；這時問 isHittable 會記一條失敗。
            let frame = element.frame
            guard !frame.isEmpty, frame.minX.isFinite, frame.minY.isFinite else { return false }
            return element.isHittable
        }
    }

    /// 等查詢裡有一個元素真的出現在畫面上，沒等到就 fail。
    @discardableResult
    func requireVisible(
        _ query: XCUIElementQuery, _ what: String, timeout: TimeInterval = 15,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        var found: XCUIElement?
        let isSeen = waitUntil(timeout: timeout) {
            found = visibleElement(in: query)
            return found != nil
        }
        XCTAssertTrue(isSeen, "畫面上沒看到\(what)", file: file, line: line)
        return found ?? query.firstMatch
    }

    /// 等含某段字的東西出現在畫面上。
    @discardableResult
    func seeText(
        _ part: String, timeout: TimeInterval = 15, file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        requireVisible(
            anyElements(containing: part), "「\(part)」", timeout: timeout, file: file, line: line)
    }

    /// 畫面上現在有沒有含這段字的東西（不等、不 fail）。
    func hasText(_ part: String) -> Bool {
        visibleElement(in: anyElements(containing: part)) != nil
    }

    /// 點畫面上看得到的那顆按鈕（label 或 identifier 剛好是這個字）。
    func tapButton(
        _ label: String, timeout: TimeInterval = 15, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let query = app.buttons.matching(named(label))
        requireVisible(query, "按鈕「\(label)」", timeout: timeout, file: file, line: line).tap()
    }

    /// 點 label 含某段字的按鈕。
    func tapButton(
        containing part: String, timeout: TimeInterval = 15, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "label CONTAINS %@", part)
        let query = app.buttons.matching(predicate)
        requireVisible(query, "含「\(part)」的按鈕", timeout: timeout, file: file, line: line).tap()
    }

    /// 點底部分頁列的那一格：prep 行前、trip 這趟、trips 旅行、me 我。
    func openTab(
        _ key: String, timeout: TimeInterval = 15, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let query = app.buttons.matching(identifier: "tab-\(key)")
        let tab = requireVisible(query, "分頁列的 \(key)", timeout: timeout, file: file, line: line)
        tab.tap()
        var isSelected = waitUntil(timeout: 5) { tab.isSelected }
        if !isSelected {
            // 模擬器很慢的時候，點一下會被當成按住，頁面沒換。再點一次。
            tab.tap()
            isSelected = waitUntil(timeout: 5) { tab.isSelected }
        }
        XCTAssertTrue(isSelected, "點了分頁列的 \(key)，它沒有變成選中", file: file, line: line)
    }
}

// MARK: 手勢與輸入

extension RadishUITestCase {
    private func drag(fromY: CGFloat, toY: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        from.press(
            forDuration: 0.05, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// 把現在這頁往下捲大約半個螢幕。慢慢拖、放開前停一下，不會滑過頭漏掉中間的內容。
    func scrollDown() {
        drag(fromY: 0.72, toY: 0.28)
    }

    /// 往回捲同樣的距離。
    func scrollUp() {
        drag(fromY: 0.28, toY: 0.72)
    }

    /// 往下捲幾次，每捲一次截一張。
    func scrollShots(_ name: String, count: Int) {
        for index in 1...count {
            scrollDown()
            shot("\(name)-往下捲\(index)")
        }
    }

    /// 一直往下捲到某個元素出現在畫面上。
    @discardableResult
    func scrollToSee(
        _ query: XCUIElementQuery, _ what: String, maxDrags: Int = 8,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        for _ in 0..<maxDrags where visibleElement(in: query) == nil {
            scrollDown()
        }
        return requireVisible(query, what, timeout: 5, file: file, line: line)
    }

    /// 往下捲到看得到那顆按鈕再點。
    func scrollAndTap(
        _ label: String, maxDrags: Int = 8, file: StaticString = #filePath, line: UInt = #line
    ) {
        let query = app.buttons.matching(named(label))
        scrollToSee(query, "按鈕「\(label)」", maxDrags: maxDrags, file: file, line: line).tap()
    }
}
