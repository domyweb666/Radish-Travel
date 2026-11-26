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
            for id in ["tab-trip"] {
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

    /// 這趟分頁黏在上面的那一塊（這天的地圖到天數分頁）上下緣。不在這趟分頁就是 nil。
    /// 捲到那一塊底下的東西 isHittable 還是對的，點下去會點到地圖
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

    /// 這趟分頁捲回最上面：右上角的更多點得到為止。旅途中一打開會先捲到今天
    private func toTop() {
        for _ in 0..<10 {
            let more: XCUIElement = byId("open-more")
            if more.exists && placed(more.frame) && more.frame.minY >= 44 && more.isHittable { return }
            drag(0.25, 0.8)
        }
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
            let band: (top: CGFloat, bottom: CGFloat)? = inSheet || inPin(id) ? nil : pinBand()
            // 狀態列底下那一條有遮底，藏在裡面的點不到；黏在上面的地圖和分頁底下也點不到
            if before.minY < 64 {
                drag(0.3, 0.62)
            } else if let band, before.minY < band.bottom, before.maxY > band.top {
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

    /// 跟 AI 講只在問 AI 分頁（QC-0013 #95）：這趟分頁和一站頁最下面都沒有講的那一列了。
    /// 問 AI 分頁送出後不升半頁，回覆、復原、再送一次、同意都接在對話裡
    private func openAsk() {
        XCTAssertFalse(byId("talk-input").exists, "這趟分頁最下面不該再有講的那一列")
        openTab("ask")
        see("chat-input")
        pause()
    }

    func test08沒網路講一句() {
        openScene("plan", ["-uitest-dest", "bridge", "-uitest-agreed", "-uitest-offline"])
        openAsk()
        see("chat-hold")
        shot("沒網路")
        typeAndCheck("chat-input", "第二天多排一間咖啡廳", "沒網路-打了一句")
    }

    func test09句數用完() {
        openScene("quota", ["-uitest-dest", "endpoint", "-uitest-agreed"])
        openAsk()
        see("chat-hold")
        pause()
        shot("句數用完")
    }

    func test10沒回好() {
        openScene("plan", ["-uitest-dest", "endpoint", "-uitest-agreed", "-uitest-ai", "fail"])
        openAsk()
        see("chat-hint-1").tap()
        see("chat-retry")
        pause()
        shot("沒回好")
    }

    func test11AI改了行程的那一則() {
        openScene("plan", ["-uitest-dest", "key", "-uitest-agreed", "-uitest-ai", "ok"])
        openAsk()
        see("chat-hint-1").tap()
        let undo: XCUIElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "chat-undo-")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 15), "AI 改了行程，對話裡沒有復原")
        pause()
        shot("AI改了")
    }

    /// 三種送去的地方，說明裡的字不一樣
    private func consent(_ dest: String, _ title: String) {
        openScene("plan", ["-uitest-dest", dest, "-uitest-ai", "fail"])
        openAsk()
        see("chat-hint-1").tap()
        see("chat-consent-where")
        pause()
        shot(title)
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
        pause()
        // 這天的地圖黏在上面，跟著標到的那一天換。點地圖開這一天的路線
        XCTAssertTrue(byId("day-tab-2").isSelected, "點了第 2 天，分頁沒有標到第 2 天")
        byId("open-map").tap()
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

    /* ---------- 這趟：每一天連續排、地圖和分頁黏在上面（QC-0013 #98、#107） ---------- */

    /// 天數分頁那一排的下緣
    private func tabsBottom() -> CGFloat {
        return byId("day-tab-1").frame.maxY
    }

    /// 現在標到第幾天。都沒標到是 nil
    private func selectedDay(_ days: Int) -> Int? {
        for d in 1...days where byId("day-tab-\(d)").isSelected {
            return d
        }
        return nil
    }

    func test42這趟往下捲換天() {
        openScene("plan")
        see("open-map")
        see("day-head-1")
        pause(2)
        shot("最上面-地圖與天數分頁")
        XCTAssertFalse(byId("talk-input").exists, "這趟分頁最下面不該再有講的那一列")
        XCTAssertLessThan(byId("open-map").frame.maxY, tabsBottom(), "地圖要在天數分頁上面")
        XCTAssertEqual(selectedDay(5), 1, "一打開要標第 1 天")
        // 往下捲：地圖和分頁停在上面，一天接一天，捲到哪天標到哪天
        var seen: Set<Int> = []
        for index in 1...6 {
            drag(0.75, 0.3)
            pause()
            shot("往下捲\(index)")
            if let d = selectedDay(5) { seen.insert(d) }
            XCTAssertGreaterThanOrEqual(byId("open-map").frame.minY, 44, "往下捲之後地圖沒有黏在上面")
        }
        XCTAssertTrue(seen.contains { (d: Int) -> Bool in d > 1 }, "往下捲了六次，分頁還停在第 1 天")
        // 點分頁：捲到那一天，那天的第一行接在分頁下面
        byId("day-tab-4").tap()
        pause(2)
        shot("點了第4天")
        XCTAssertEqual(selectedDay(5), 4, "點了第 4 天，分頁沒有標到第 4 天")
        let head: CGFloat = byId("day-head-4").frame.minY
        XCTAssertGreaterThanOrEqual(head, tabsBottom() - 2, "第 4 天那一行被黏在上面的那一塊蓋住")
        XCTAssertLessThan(head, tabsBottom() + 72, "點了第 4 天，第 4 天沒有接在分頁下面")
        // 分頁列把第 4 天捲到中間，第 1 天在畫面左邊外面：先往右滑分頁列，跟手指一樣
        let first: XCUIElement = byId("day-tab-1")
        for _ in 0..<3 where !(placed(first.frame) && first.frame.minX >= 0 && first.isHittable) {
            byId("day-tab-4").swipeRight()
            pause()
        }
        first.tap()
        pause(2)
        shot("點回第1天")
        XCTAssertEqual(selectedDay(5), 1, "點了第 1 天，分頁沒有標回第 1 天")
    }

    func test43旅途中打開捲到今天() {
        openScene("trip")
        see("next-pull")
        pause(2)
        shot("旅途中-打開就是今天")
        XCTAssertEqual(selectedDay(8), 2, "旅途中第 2 天打開，分頁要標第 2 天")
        let head: CGFloat = byId("day-head-2").frame.minY
        XCTAssertGreaterThanOrEqual(head, tabsBottom() - 2, "今天那一行被黏在上面的那一塊蓋住")
        XCTAssertLessThan(head, tabsBottom() + 72, "旅途中打開沒有捲到今天")
        XCTAssertGreaterThan(byId("next-pull").frame.minY, head, "下一站要接在今天那一行下面")
        // 點地圖開這一天的路線
        byId("open-map").tap()
        see("route-total")
        pause()
        shot("旅途中-點地圖開今天的路線")
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
        // 回來那天直接點月曆（QC-0013 #104）：去 5 天
        let end: String = dayISO(7)
        if !byId("cal-\(end)").waitForExistence(timeout: 3) {
            tapId("cal-next")
        }
        tapId("cal-\(end)")
        // 想怎麼玩在月曆上面，點完日期要往回捲才點得到
        fillWish()
        for id in ["arrive-am", "leave-pm", "people-2", "base-C"] {
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
        toTop()
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

    /* ---------- 更多裡的順路清單 ---------- */

    func test24順路清單與拿掉() {
        openScene("pool")
        toTop()
        see("open-more").tap()
        bring("pool-remove-2", inSheet: true)
        pause()
        shot("順路清單")
        tapId("pool-remove-0", inSheet: true)
        // 半頁開著超過 0.8 秒，提示條才在半頁裡出現
        pause(2)
        shot("順路清單-拿掉之後的提示條")
        XCTAssertFalse(byId("pool-remove-2").exists, "拿掉一個，清單沒有變短")
        see("notice-undo").tap()
        see("pool-remove-2")
        pause()
        shot("順路清單-復原之後")
    }

    /* ---------- 核對過的資料（資料在，那幾塊一定要出現） ---------- */

    /// 等一下，看那個識別碼在不在。不在不算錯
    private func has(_ id: String, _ seconds: TimeInterval = 4) -> Bool {
        return byId(id).waitForExistence(timeout: seconds)
    }

    /// 開第 2 天的景福宮那一頁
    private func openPalace() {
        tapId("day-tab-2")
        pause()
        tapId("stop-row-p0")
        see("stop-show")
        pause()
    }

    func test25這天休館() {
        openScene("closed")
        tapId("day-tab-2")
        see("day-closed-2")
        bring("day-closed-2")
        pause()
        shot("這天休館-這趟")
        tapId("stop-row-p0")
        see("stop-show")
        pause()
        shot("這天休館-一站")
        see("stop-closed")
        bring("stop-open")
        shot("這天休館-一站-開放")
    }

    func test26核對過的一站與來源() {
        openScene("checked")
        openPalace()
        shot("核對過的一站")
        XCTAssertFalse(byId("stop-closed").exists, "有開的日子，不該寫休館")
        see("stop-open")
        bring("stop-source")
        shot("核對過的一站-開放")
        byId("stop-source").tap()
        pause()
        shot("核對過的一站-來源")
        tapButton("關閉")
        pause()
        tapId("stop-show")
        see("driver-close")
        pause()
        shot("給司機看-有沒有地址")
    }

    func test27要先訂的一站() {
        openScene("checked")
        tapId("day-tab-2")
        pause()
        tapId("stop-row-p6")
        see("stop-book")
        bring("stop-book-more")
        pause()
        shot("要先訂的一站-怎麼訂")
        tapId("stop-book-more")
        pause()
        shot("要先訂的一站-訂之前要知道的")
    }

    func test28深色大字的這天休館() {
        let size: [String] = [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM", "-uitest-dark",
        ]
        openScene("closed", size)
        tapId("day-tab-2")
        pause()
        bring("day-closed-2")
        shot("深色大字-這天休館")
        tapId("stop-row-p0")
        see("stop-show")
        pause()
        shot("深色大字-一站")
        for index in 1...3 {
            drag(0.55, 0.15)
            shot("深色大字-一站-往下捲\(index)")
        }
        tapId("stop-show")
        see("driver-close")
        pause()
        shot("深色大字-給司機看")
    }

    /// 從這趟推進檢查這趟，一頁一頁截
    private func checkShots(_ title: String, _ count: Int) {
        see("open-check").tap()
        pause()
        shot(title)
        for index in 1...count {
            drag(0.75, 0.3)
            shot(title + "-往下捲\(index)")
        }
    }

    func test29檢查這趟要先訂的() {
        openScene("book")
        checkShots("檢查這趟-要先訂的", 5)
        bring("check-c2")
        pause()
        shot("檢查這趟-KETA在期限內")
    }

    func test30期限後的KETA與塔不開() {
        openScene("late")
        tapId("day-tab-2")
        pause()
        shot("期限後-這趟")
        let rowText: String = see("stop-row-p11").label
        XCTAssertTrue(rowText.contains("這天要注意"), "N 首爾塔那一列沒有寫這天要注意")
        tapId("stop-row-p11")
        see("stop-move")
        pause()
        // 那陣子展望台限制使用，寫在標題下面，進來就看得到
        XCTAssertTrue(has("stop-caution"), "N 首爾塔沒有寫這天要注意")
        shot("期限後-N首爾塔")
        bring("stop-open")
        shot("期限後-N首爾塔-開放")
        goBack()
        // 每一天都排在同一頁，第 2 天離最上面比較遠
        toTop()
        see("open-check").tap()
        pause()
        bring("check-c2")
        pause()
        shot("檢查這趟-KETA期限後")
    }

    func test31須知按天() {
        openScene("book")
        see("open-notes").tap()
        pause()
        tapButton("按天")
        tapId("day-tab-2")
        pause()
        shot("須知-按天")
        drag(0.75, 0.3)
        shot("須知-按天-往下捲")
    }

    func test32移到休館那天() {
        openScene("closed")
        tapId("day-tab-2")
        pause()
        tapId("stop-row-p0")
        openMove()
        pickCell("move-2-eve")
        see("move-closed")
        shot("移站-休館那天")
        drag(0.68, 0.4)
        pause()
        shot("移站-休館那天-往下捲")
    }

    func test33要先訂的一站往下捲() {
        openScene("checked")
        tapId("day-tab-2")
        pause()
        tapId("stop-row-p6")
        see("stop-move")
        pause()
        // 起點要在講的那一列上面，不然捲不動
        for index in 1...5 {
            shot("後苑-\(index)")
            drag(0.66, 0.2)
        }
    }

    /// 一站頁的移到別的時段：整顆露出來才按
    private func openMove() {
        see("stop-move")
        // 字放大時講的那一列比較高，起點放高一點才捲得動
        for _ in 0..<8 where byId("stop-move").frame.maxY > bottomLimit(false) {
            drag(0.55, 0.25)
        }
        let button: XCUIElement = bring("stop-move")
        XCTAssertGreaterThanOrEqual(button.frame.minY, 64, "移到別的時段被上面蓋住")
        XCTAssertLessThanOrEqual(button.frame.maxY, bottomLimit(false) + 8, "移到別的時段沒有整顆露出來")
        button.tap()
        see("move-go")
        pause()
    }

    /// 還沒選的時候點一格：格子在中間那塊捲，要整格在下面那塊字的上面才按
    private func pickCell(_ id: String) {
        let cell: XCUIElement = see(id)
        let floor: CGFloat = see("move-summary").frame.minY
        for _ in 0..<6 {
            if cell.frame.maxY <= floor { break }
            drag(0.6, 0.48)
        }
        XCTAssertLessThanOrEqual(cell.frame.maxY, floor, "\(id) 沒有整格露出來")
        cell.tap()
        pause()
    }

    func test35這個時段不開() {
        openScene("part")
        tapId("day-tab-2")
        pause()
        let rowText: String = bring("stop-row-p30c").label
        XCTAssertTrue(rowText.contains("才開"), "古都食那一列沒有寫幾點才開：\(rowText)")
        shot("時段不開-這趟")
        tapId("stop-row-p30c")
        see("stop-part-closed")
        pause()
        shot("時段不開-一站")
        openMove()
        shot("時段不開-移站")
        pickCell("move-3-am")
        see("move-part-closed")
        shot("時段不開-移站-選了也不開的時段")
    }

    func test36下一站卡的時段不開() {
        openScene("part-next")
        bring("next-part-closed")
        pause()
        shot("下一站卡-時段不開")
        // 卡上講過了，下面那一列不再講一次
        let rowText: String = see("stop-row-p30c").label
        XCTAssertFalse(rowText.contains("才開"), "下一站卡講過，下面那一列又講一次：\(rowText)")
        bring("stop-row-p30c")
        shot("下一站卡-時段不開-清單")
    }

    func test37下一站卡的這天要注意() {
        openScene("late-next")
        bring("next-caution")
        pause()
        shot("下一站卡-要注意")
        let rowText: String = see("stop-row-p11").label
        XCTAssertFalse(rowText.contains("要注意"), "下一站卡講過，下面那一列又講一次：\(rowText)")
    }

    func test38附近不開的不能按與看那站() {
        openScene("nearby-shut")
        tapId("next-nearby")
        see("nearby-origin")
        pause()
        let add: XCUIElement = bring("nearby-add-0", inSheet: true)
        pause()
        shot("附近-能排的時段都不開")
        XCTAssertFalse(add.isEnabled, "晚上不開的地方，還是可以排進晚上")
        XCTAssertTrue(add.label.contains("都不開"), "不能按的那顆沒有寫為什麼：\(add.label)")
        tapId("nearby-open-0", inSheet: true)
        see("stop-show")
        pause()
        shot("不在這趟裡的地方")
        // 跟這趟裡的站一樣：要按的在前，核對資料在後
        let show: CGFloat = byId("stop-show").frame.minY
        for id in ["stop-open", "stop-book", "stop-source"] {
            XCTAssertGreaterThan(see(id).frame.minY, show, "\(id) 排在要按的前面")
        }
        bring("stop-source")
        shot("不在這趟裡的地方-往下捲")
    }

    func test41整天在路上的附近() {
        openScene("nearby-road")
        see("next-nearby")
        pause()
        shot("整天在路上-這趟")
        tapId("next-nearby")
        let add: XCUIElement = see("nearby-add-0")
        pause()
        shot("整天在路上-附近")
        XCTAssertFalse(add.isEnabled, "整天在路上，還是可以排進來")
        XCTAssertTrue(add.label.contains("在路上"), "不能按的那顆沒有寫在路上：\(add.label)")
    }

    func test39要先訂但沒有核對資料() {
        openScene("nobook")
        tapId("day-tab-2")
        pause()
        tapId("stop-row-uitest-nobook")
        see("stop-move")
        pause()
        shot("沒有核對資料的要先訂")
        let lines: XCUIElementQuery = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "怎麼訂"))
        XCTAssertEqual(lines.count, 1, "怎麼訂應該只留一句")
        for id in ["stop-open", "stop-book", "stop-source"] {
            XCTAssertFalse(byId(id).exists, "沒有核對資料，不該出現 \(id)")
        }
        bring("stop-show")
        shot("沒有核對資料的要先訂-往下捲")
    }

    func test40輔助大字的移站() {
        openScene(
            "part", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        tapId("day-tab-2")
        pause()
        tapId("stop-row-p30c")
        see("stop-part-closed")
        openMove()
        shot("輔助大字-移站")
        for index in 1...3 {
            drag(0.6, 0.35)
            shot("輔助大字-移站-往下捲\(index)")
        }
    }

    func test34大字的檢查這趟() {
        openScene(
            "book", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        checkShots("大字-檢查這趟", 3)
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
