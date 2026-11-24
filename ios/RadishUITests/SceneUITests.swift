import XCTest

/// 一個畫面一條短測試：用場景（Radish/App/UITestScenes.swift）直接開到那個狀態，截圖就結束，互相不依賴。
/// 主流程在 FlowUITests；這裡補它走不到的畫面。找元件一律用識別碼的 firstMatch，比用字找快。
final class SceneUITests: RadishUITestCase {
    /// 每條測試的檔名不一樣，流水號相同也不會互蓋。name 是 -[SceneUITests test01給司機看]
    override var shotPrefix: String {
        let last: String = name.components(separatedBy: " ").last ?? name
        var method: String = last.replacingOccurrences(of: "]", with: "")
        if method.hasPrefix("test") {
            method = String(method.dropFirst(4))
        }
        return "Scene-" + method
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

    /// 位置讀得到。捲出畫面的輸入框，位置會是空的或無限大
    private func placed(_ frame: CGRect) -> Bool {
        return !frame.isEmpty && !frame.isInfinite && frame.minY.isFinite && frame.maxY.isFinite
    }

    /// 捲到整個看得到。在上面就往回捲，在下面就往下捲；捲不動了就停。
    /// 位置讀不到的（捲出畫面的輸入框）先往下找，找不到再往回找
    @discardableResult
    private func bring(
        _ id: String, inSheet: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
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
            // 狀態列底下那一條有遮底，藏在裡面的點不到
            if before.minY < 64 {
                drag(0.3, 0.62)
            } else if before.maxY > bottomLimit(inSheet) {
                drag(0.66, 0.3)
            } else {
                break
            }
            if element.frame == before { break }
        }
        return element
    }

    /// 識別碼可能掛在整格（小標加輸入框）上，先找真的輸入框
    private func fieldById(_ id: String) -> XCUIElement {
        for query in [app.textFields, app.textViews] {
            let hit: XCUIElement = query.matching(identifier: id).firstMatch
            if hit.exists { return hit }
        }
        return byId(id)
    }

    /// 捲到真的點得到的輸入框。捲過頭就一小步一小步往回捲
    private func bringField(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        // 講的那一列釘在最下面，不用捲
        let pinned: Bool = id.hasSuffix("-input")
        see(id, file: file, line: line)
        if !pinned { bring(id, file: file, line: line) }
        for _ in 0..<10 {
            let field: XCUIElement = fieldById(id)
            let box: CGRect = field.frame
            if placed(box) && box.minY >= 64 {
                if !pinned && box.maxY > bottomLimit(false) {
                    drag(0.55, 0.4)
                    continue
                }
                if field.isHittable { return field }
            }
            drag(0.4, 0.55)
        }
        let last: XCUIElement = fieldById(id)
        let ok: Bool = placed(last.frame) && last.isHittable
        XCTAssertTrue(ok, "捲不到輸入框 \(id)", file: file, line: line)
        return last
    }

    /// 打開鍵盤，截圖，確認分頁列收起來了、輸入框整個在鍵盤上面
    private func typeAndCheck(_ id: String, _ text: String, _ title: String) {
        let field: XCUIElement = bringField(id)
        field.tap()
        let keyboard: XCUIElement = app.keyboards.firstMatch
        let up: Bool = keyboard.waitForExistence(timeout: 8)
        XCTAssertTrue(up, "點了 \(id)，鍵盤沒有出來")
        field.typeText(text)
        pause()
        shot(title)
        XCTAssertFalse(byId("tab-trip").exists, "鍵盤出來了，分頁列還在")
        let box: CGRect = fieldById(id).frame
        if placed(box) && placed(keyboard.frame) {
            XCTAssertLessThanOrEqual(box.maxY, keyboard.frame.minY + 1, "\(id) 被鍵盤蓋到")
        }
    }

    private func tapId(
        _ id: String, inSheet: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) {
        bring(id, inSheet: inSheet, file: file, line: line).tap()
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
        typeAndCheck("talk-input", "第二天多排一間咖啡廳", "沒網路-打了一句")
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
        // 想怎麼玩在月曆上面，點完日期要往回捲才點得到
        fillWish()
        for id in ["days-5", "arrive-am", "leave-pm", "people-2", "base-C"] {
            tapId(id)
        }
        tapId("start-go")
        // 沒接 AI：行程排好，升起半頁講那句還沒送
        see("reply-wish-held", timeout: 20)
        pause()
        shot("排好了-那句還沒送")
        byId("reply-done").tap()
        see("day-tab-1", timeout: 20)
        pause()
        shot("沒接AI排出來的")
        if byId("planned-drop").exists {
            bring("planned-drop")
            shot("沒接AI排出來的-剛排好那張卡")
        }
    }

    /// 打想怎麼玩那一格，按收鍵盤。中文打不進去就改打英文
    private func fillWish() {
        let field: XCUIElement = bringField("start-wish")
        shot("想怎麼玩-空的")
        field.tap()
        let keyboard: XCUIElement = app.keyboards.firstMatch
        let up: Bool = keyboard.waitForExistence(timeout: 8)
        XCTAssertTrue(up, "點了想怎麼玩，鍵盤沒有出來")
        field.typeText("想慢慢逛，多吃在地小館")
        let typed: String = (fieldById("start-wish").value as? String) ?? ""
        if !typed.contains("慢慢逛") {
            fieldById("start-wish").typeText("slow walks, small local restaurants")
        }
        pause()
        shot("想怎麼玩-打了字")
        XCTAssertFalse(byId("tab-trip").exists, "鍵盤出來了，分頁列還在")
        see("start-wish-done").tap()
        let gone: Bool = waitUntil(timeout: 8) { !self.app.keyboards.firstMatch.exists }
        XCTAssertTrue(gone, "按了收鍵盤，鍵盤還在")
        see("tab-trip")
    }

    /* ---------- 鍵盤出來時，分頁列不蓋輸入框 ---------- */

    func test21問AI打字() {
        openScene("plan")
        openTab("ask")
        typeAndCheck("chat-input", "hello", "問AI-鍵盤出來")
    }

    func test22花費打字() {
        openScene("trip")
        see("open-more").tap()
        tapId("more-cost", inSheet: true)
        typeAndCheck("spend-krw", "12000", "花費-鍵盤出來")
    }

    func test23一站寫一句() {
        openScene("done")
        let rows: XCUIElementQuery = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "stop-row-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "清單裡沒有站")
        tapId(rows.firstMatch.identifier)
        typeAndCheck("visit-say", "hello", "一站-鍵盤出來")
    }

    /* ---------- 深色、大字 ---------- */

    func test19深色的三個分頁() {
        openScene("trips", ["-uitest-dark"])
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
