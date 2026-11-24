import XCTest

/// 一個畫面一條短測試：用場景（Radish/App/UITestScenes.swift）直接開到那個狀態，截圖就結束，互相不依賴。
/// 主流程在 FlowUITests；這裡補它走不到的畫面。找元件一律用識別碼的 firstMatch，比用字找快。
final class SceneUITests: RadishUITestCase {
    private var changedAppearance: Bool = false

    /// 每條測試的檔名不一樣，流水號相同也不會互蓋。name 是 -[SceneUITests test01給司機看]
    override var shotPrefix: String {
        let last: String = name.components(separatedBy: " ").last ?? name
        var method: String = last.replacingOccurrences(of: "]", with: "")
        if method.hasPrefix("test") {
            method = String(method.dropFirst(4))
        }
        return "Scene-" + method
    }

    override func tearDownWithError() throws {
        if changedAppearance {
            XCUIDevice.shared.appearance = .light
        }
        try super.tearDownWithError()
    }

    /* ---------- 找、捲、點 ---------- */

    /// 從空白開 app，停在那個場景
    private func openScene(_ scene: String, _ extra: [String] = []) {
        let args: [String] = ["-uitest-scene", scene] + extra
        launch(reset: true, args)
        see("tab-trip", timeout: 40)
    }

    private func byId(_ id: String) -> XCUIElement {
        return idQuery(id).firstMatch
    }

    /// 等那個識別碼出現（不管有沒有被捲到畫面外）
    @discardableResult
    private func see(
        _ id: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let element: XCUIElement = byId(id)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "沒看到識別碼 \(id)", file: file, line: line)
        return element
    }

    /// 讓動畫跑完
    private func pause(_ seconds: TimeInterval = 1) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// 捲半個螢幕左右。起點放在中間，不會拖到最下面講的那一列
    private func drag(_ from: CGFloat, _ to: CGFloat) {
        let a: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let b: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: 0.2)
    }

    /// 看得到、不會被蓋住的最下緣。半頁裡沒有分頁列，只看螢幕和鍵盤
    private func bottomLimit(_ inSheet: Bool) -> CGFloat {
        var limit: CGFloat = app.frame.maxY - 34
        if !inSheet {
            for id in ["tab-trip", "talk-hint-0", "talk-input"] {
                let element: XCUIElement = byId(id)
                if element.exists && !element.frame.isEmpty {
                    limit = min(limit, element.frame.minY - 8)
                }
            }
        }
        let keyboard: XCUIElement = app.keyboards.firstMatch
        if keyboard.exists && !keyboard.frame.isEmpty {
            limit = min(limit, keyboard.frame.minY - 8)
        }
        return limit
    }

    /// 捲到整個看得到。在上面就往回捲，在下面就往下捲；捲不動了就停
    @discardableResult
    private func bring(
        _ id: String, inSheet: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let element: XCUIElement = see(id, file: file, line: line)
        for _ in 0..<10 {
            let before: CGRect = element.frame
            if !before.isEmpty && before.minY < 56 {
                drag(0.3, 0.62)
            } else if before.isEmpty || before.maxY > bottomLimit(inSheet) {
                drag(0.66, 0.3)
            } else {
                break
            }
            if element.frame == before && !before.isEmpty { break }
        }
        return element
    }

    private func tapId(
        _ id: String, inSheet: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) {
        bring(id, inSheet: inSheet, file: file, line: line).tap()
    }

    /// 有鍵盤才打字：鍵盤沒出來就不打，不讓打字害截圖截不到
    private func typeIfPossible(_ id: String, _ text: String) {
        var field: XCUIElement = byId(id)
        // 識別碼可能掛在整格（小標加輸入框）上，先找真的輸入框
        for query in [app.textFields, app.textViews] {
            let hit: XCUIElement = query.matching(identifier: id).firstMatch
            if hit.exists {
                field = hit
                break
            }
        }
        field.tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            app.typeText(text)
        }
    }

    /// 今天往後幾天，YYYY-MM-DD
    private func dayISO(_ offset: Int) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date().addingTimeInterval(Double(offset) * 86400))
    }

    /* ---------- 旅途中 ---------- */

    func test01給司機看與拔蘿蔔() {
        openScene("trip")
        tapId("next-driver")
        see("driver-close")
        pause()
        shot("給司機看")
        byId("driver-close").tap()
        pause()
        tapId("next-pull")
        see("pull-moment", timeout: 8)
        shot("拔蘿蔔")
    }

    func test02過敏告知卡() {
        openScene("trip")
        tapId("next-detail")
        tapId("stop-allergy")
        see("allergy-copy")
        pause()
        shot("過敏告知卡")
    }

    func test03附近還有什麼往下捲() {
        openScene("trip")
        tapId("next-nearby")
        see("nearby-origin")
        pause()
        shot("附近")
        for index in 1...2 {
            drag(0.75, 0.3)
            shot("附近-往下捲\(index)")
        }
    }

    func test04移到別的時段往下捲() {
        openScene("trip")
        tapId("next-detail")
        tapId("stop-move")
        see("move-go")
        pause()
        shot("移到別的時段")
        for index in 1...2 {
            drag(0.68, 0.4)
            shot("移到別的時段-往下捲\(index)")
        }
    }

    /* ---------- 剛排好、回來後、旅行 ---------- */

    func test05剛排好那張卡() {
        openScene("plan")
        bring("planned-drop")
        pause()
        shot("剛排好那張卡")
    }

    func test06回來後那張卡() {
        openScene("done")
        see("done-visited")
        pause()
        shot("回來後那張卡")
    }

    func test07旅行分頁與去過的那一趟() {
        openScene("trips")
        openTab("trips")
        see("trip-card-current")
        pause()
        shot("旅行-其他排好的")
        bring("basket-card-uitest")
        shot("旅行-往下捲")
        byId("basket-card-uitest").tap()
        see("album-share")
        pause()
        shot("去過的那一趟")
        for index in 1...3 {
            drag(0.68, 0.22)
            shot("去過的那一趟-往下捲\(index)")
        }
    }

    /* ---------- 跟 AI 講 ---------- */

    func test08沒網路講一句() {
        openScene("plan", ["-uitest-dest", "bridge", "-uitest-agreed", "-uitest-offline"])
        see("talk-hold")
        shot("沒網路")
        see("talk-input")
        typeIfPossible("talk-input", "第二天多排一間咖啡廳")
        pause()
        shot("沒網路-打了一句")
    }

    func test09句數用完() {
        openScene("quota", ["-uitest-dest", "endpoint", "-uitest-agreed"])
        see("talk-hold")
        pause()
        shot("句數用完")
    }

    func test10沒回好() {
        openScene("plan", ["-uitest-dest", "endpoint", "-uitest-agreed", "-uitest-ai", "fail"])
        see("talk-hint-1").tap()
        see("reply-retry")
        pause()
        shot("沒回好")
    }

    func test11AI改了行程的剛剛那一則() {
        openScene("plan", ["-uitest-dest", "key", "-uitest-agreed", "-uitest-ai", "ok"])
        tapId("day-tab-2")
        see("talk-hint-1").tap()
        see("reply-undo")
        pause()
        shot("剛剛那一則-AI改了")
        drag(0.75, 0.3)
        pause()
        shot("剛剛那一則-拉高")
    }

    /// 三種送去的地方，說明裡的字不一樣
    private func consent(_ dest: String, _ title: String) {
        openScene("plan", ["-uitest-dest", dest, "-uitest-ai", "fail"])
        see("talk-hint-1").tap()
        see("chat-consent-where")
        pause()
        shot(title)
        drag(0.75, 0.3)
        pause()
        shot(title + "-拉高")
    }

    func test12第一次同意電腦CLI() {
        consent("bridge", "同意-電腦CLI")
    }

    func test13第一次同意金鑰() {
        consent("key", "同意-金鑰")
    }

    func test14第一次同意後端() {
        consent("endpoint", "同意-後端")
    }

    /* ---------- 路線 ---------- */

    func test15路線這次會改與半頁提示條() {
        openScene("route")
        tapId("day-tab-2")
        tapId("open-map")
        see("route-ask")
        pause(2)
        byId("route-ask").tap()
        see("route-apply")
        pause()
        shot("路線-這次會改")
        byId("route-apply").tap()
        // 半頁開著超過 0.8 秒，提示條才在半頁裡出現
        pause(2)
        shot("路線-照這樣改之後的提示條")
    }

    /* ---------- 平常的我 ---------- */

    func test16金鑰頁() {
        openScene("plan")
        see("open-me").tap()
        tapId("me-row-claude")
        see("me-claude-input")
        pause()
        shot("金鑰頁")
    }

    func test17連電腦頁() {
        openScene("plan", ["-uitest-dest", "bridge"])
        see("open-me").tap()
        tapId("me-row-bridge")
        see("me-bridge-input")
        pause()
        shot("連電腦頁-連著")
    }

    /* ---------- 開一趟 ---------- */

    func test18開一趟填想怎麼玩() {
        openScene("start")
        let iso: String = dayISO(3)
        if !byId("cal-\(iso)").waitForExistence(timeout: 5) {
            // 三天後是下個月
            tapId("cal-next")
        }
        tapId("cal-\(iso)")
        for id in ["days-5", "arrive-am", "leave-pm", "people-2", "base-C"] {
            tapId(id)
        }
        // 想怎麼玩那一格還沒做進來的話就跳過，後面照樣排
        if byId("start-wish").waitForExistence(timeout: 3) {
            bring("start-wish")
            shot("想怎麼玩-空的")
            typeIfPossible("start-wish", "想慢慢逛，多吃在地小館")
            pause()
            shot("想怎麼玩-打了字")
            // 往下拖把鍵盤收起來
            for _ in 0..<3 where app.keyboards.firstMatch.exists {
                drag(0.3, 0.9)
            }
        } else {
            shot("沒有想怎麼玩那一格")
        }
        tapId("start-go")
        see("day-tab-1", timeout: 20)
        pause()
        shot("沒接AI排出來的")
        if byId("planned-drop").exists {
            bring("planned-drop")
            shot("沒接AI排出來的-剛排好那張卡")
        }
    }

    /* ---------- 深色、大字 ---------- */

    func test19深色的三個分頁() {
        changedAppearance = true
        XCUIDevice.shared.appearance = .dark
        openScene("trips")
        see("day-tab-1")
        pause()
        shot("深色-這趟")
        openTab("ask")
        see("chat-input")
        pause()
        shot("深色-問AI")
        openTab("trips")
        see("trip-card-current")
        pause()
        shot("深色-旅行")
    }

    func test20大字級的這趟() {
        openScene(
            "trip", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        see("day-tab-1")
        pause()
        shot("大字-這趟")
        for index in 1...2 {
            drag(0.55, 0.15)
            shot("大字-這趟-往下捲\(index)")
        }
    }
}
