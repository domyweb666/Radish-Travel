// 「這趟」分頁（S01，線框 A1、A2、A4、A9）。沒有行程時是開一趟。
// 右上角是更多和平常的我；標題下面一行日期，再來兩個常駐入口：檢查這趟、須知（推進），再來是提醒條。
// QC-0013（參照去趣）：每一天連續排下去，一直往下滑就換到下一天，每天前面一行「第 N 天・日期」。
// 這一天的地圖和天數分頁一起黏在上面（往下捲時停在頂端）；捲到哪一天，分頁標到哪一天、地圖換成那天的點；
// 點分頁捲到那一天，點地圖開這一天的路線。旅途中打開先捲到今天，「下一站」接在今天那一行下面。
// 最下面跟 AI 講的那一列拿掉了（#95：問 AI 有自己的分頁，手機螢幕放不下），一站頁的還在。
// 第一趟排好後的三步操作說明拿掉了（02-流程 1-4、❓38 建議刪，方向說明 A17「跟著 1-4 刪操作說明」）。
// 對應 mobile/src/screens/TripScreen.tsx。子元件（每天的分頁、地圖、一站的列、下一站）在 TripScreenParts.swift，
// 剛排好那張卡、回來後那張卡在 Components/TripCards.swift。
import SwiftUI

/// 點分頁捲過去用的代號
private func dayKey(_ d: Int) -> String {
    return "trip-day-\(d)"
}

struct TripScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    @Environment(Sheets.self) private var sheets
    /// 這一天每一站在畫面上的位置。原本給操作說明照亮第一站用，說明拿掉了，TripDayCard 還要這個參數
    @State private var frames: SpotFrames = SpotFrames()
    /// 每一天捲到哪裡。不是畫面狀態，捲動時改它不會讓畫面重畫
    @State private var scroll: DayScroll = DayScroll()
    /// 黏在上面那一塊（地圖加天數分頁）多高。點分頁捲過去時，那一天要接在這一塊下面
    @State private var pinH: CGFloat = 0
    /// 捲動區看得到的那一段多高（扣掉狀態列和下緣安全區）。點分頁捲過去時用來算落點
    @State private var visibleH: CGFloat = 0
    /// 捲過去之後量到的「比例點換算成多高」。第一次照 visibleH 估，落點差太多就用量到的改，之後都用這個
    @State private var landW: CGFloat = 0

    init() {}

    /// 旅途中的今天是第幾天。不在旅途中就是 nil
    private var today: Int? {
        if case .trip(let d)? = store.phase { return d }
        return nil
    }

    var body: some View {
        Group {
            if let trip = store.s.trip, let phase = store.phase {
                tripBody(trip, phase)
            } else {
                StartTrip(goSettings: { nav.push(.me) })
            }
        }
        .pushPages(store.s.trip.map(tripTitle) ?? "開一趟")
    }

    /// 現在看的是第幾天：捲到哪一天、點了哪一天（記在 Nav，切分頁回來還在，問 AI 也照這個）；
    /// 還沒換過就跟著今天（旅途中）或第 1 天
    private func shownDay(_ trip: Trip) -> Int {
        return max(1, min(nav.tripDay ?? today ?? 1, trip.days))
    }

    private func tripBody(_ trip: Trip, _ phase: Phase) -> some View {
        let shown: Int = shownDay(trip)
        return Screen(
            tripTitle(trip),
            onScrollPhase: { (p: ScrollPhase) in
                scrolled(p, trip)
            },
            onVisibleHeight: { (h: CGFloat) in
                visibleH = h
            },
            actions: {
                TopActions(more: { sheets.open(.more(day: shown)) })
            }
        ) {
            header(trip, phase)
            if phase == Phase.done {
                DoneCard(trip: trip)
            }
            banners(trip, phase)
            days(trip, phase)
        }
    }

    /// 這趟還有幾站沒核對。都核對過、已經回來就不講
    @ViewBuilder
    private func uncheckedNote(_ trip: Trip, _ phase: Phase) -> some View {
        if phase != Phase.done, let line = uncheckedLine(trip) {
            DomyText(line, .footnote, tone: .secondary, align: .center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("trip-unchecked")
        }
    }

    /* ---------- 每一天連續排下去 ---------- */

    /// 地圖和天數分頁黏在上面（section header），下面是每一天。整段只有一格，裡面的天不是懶載入，
    /// 點分頁捲到還沒看過的那一天也找得到
    private func days(_ trip: Trip, _ phase: Phase) -> some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    dayList(trip, phase)
                } header: {
                    pinned(trip, proxy)
                }
            }
            .onAppear {
                arrive(trip, proxy)
            }
            .onChange(of: pinH) { (old: CGFloat, _: CGFloat) in
                if old <= 0 {
                    arrive(trip, proxy)
                }
            }
            .onChange(of: visibleH) { (old: CGFloat, _: CGFloat) in
                if old <= 0 {
                    arrive(trip, proxy)
                }
            }
            .onChange(of: nav.tripDay) { (_: Int?, _: Int?) in
                moved(trip, proxy)
            }
        }
    }

    /// 黏在上面那一塊：這一天的地圖，下面是天數分頁。底色鋪滿整個寬，捲上來的站不會從旁邊透出來
    private func pinned(_ trip: Trip, _ proxy: ScrollViewProxy) -> some View {
        let shown: Int = shownDay(trip)
        return VStack(alignment: .leading, spacing: T.Space.s3) {
            TripDayMap(trip: trip, day: shown)
            TripDayTabs(trip: trip, value: shown, today: today) { (d: Int) in
                pick(d, proxy)
            }
        }
        .padding(.top, T.Space.s2)
        .padding(.bottom, T.Space.s3)
        .padding(.horizontal, T.Size.screenMargin)
        .background(C.canvas)
        .padding(.horizontal, -T.Size.screenMargin)
        .onGeometryChange(for: CGFloat.self) { (g: GeometryProxy) -> CGFloat in
            return g.size.height
        } action: { (h: CGFloat) in
            pinH = h
        }
        .onGeometryChange(for: CGFloat.self) { (g: GeometryProxy) -> CGFloat in
            return g.frame(in: .global).maxY
        } action: { (y: CGFloat) in
            scroll.line = y
            if scroll.byHand { follow(trip) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-pinned")
    }

    /// 剛排好那張卡（A4，自己決定要不要顯示）或回來後那一行小字（A9）只在第一天上面放一次，
    /// 再來每一天，最後是還沒核對的
    private func dayList(_ trip: Trip, _ phase: Phase) -> some View {
        let list: [Int] = Array(1...max(1, trip.days))
        return VStack(alignment: .leading, spacing: T.Space.s8) {
            if phase == Phase.done {
                DomyText("有去過但沒按到的，點那一站可以補。", .footnote, tone: .secondary)
            } else {
                PlannedCard(trip: trip)
            }
            ForEach(list, id: \.self) { (d: Int) in
                // 落點是這一天上緣一條沒有高度的線，捲過去時停在黏頂那一塊下面（見 landing）
                VStack(alignment: .leading, spacing: 0) {
                    dayAnchor(d)
                    dayBlock(trip, d)
                }
            }
            uncheckedNote(trip, phase)
        }
        .padding(.top, T.Space.s3)
        .background(alignment: .bottom) {
            endMark
        }
    }

    /// 一天：第 N 天・日期，旅途中的今天多一張下一站，再來這天休館的那一條、這一天的清單
    private func dayBlock(_ trip: Trip, _ d: Int) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            TripDayHead(trip: trip, day: d, today: today)
            if d == today {
                TripNextStop(trip: trip, day: d)
            }
            DayShutBanner(trip: trip, day: d)
            TripDayCard(trip: trip, day: d, frames: frames)
        }
        .onGeometryChange(for: CGFloat.self) { (g: GeometryProxy) -> CGFloat in
            return g.frame(in: .global).minY
        } action: { (y: CGFloat) in
            scroll.tops[d] = y
            if scroll.byHand { follow(trip) }
        }
        .onDisappear {
            scroll.tops[d] = nil
        }
    }

    /// 點分頁捲過去時，這一天上緣要停在看得到那一段的哪裡：黏頂那一塊（地圖加分頁）下面再空一點。
    /// scrollTo 的 anchor 是「這一站的那個比例點對齊捲動區的同一個比例點」，落點是沒有高度的線，
    /// 所以比例 = 想停的高度 ÷ 看得到那一段的高度。
    /// 以前用一塊黏頂高的透明落點、負的上邊距收回去（或 alignmentGuide 往上推），
    /// CI 實測 scrollTo 都不認那個位移，這一天會被捲到最上面、蓋在地圖底下（QC-0013 CI run 45739291921）
    private var landing: UnitPoint {
        let stop: CGFloat = pinH + T.Space.s2
        let w: CGFloat = landW > 0 ? landW : visibleH
        guard pinH > 0, w > stop else { return .top }
        return UnitPoint(x: 0.5, y: stop / w) // domy-ignore: 比例點，不是版面數值
    }

    private func dayAnchor(_ d: Int) -> some View {
        Color.clear
            .frame(height: 0)
            .id(dayKey(d))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 整段的最下緣。看得到就是捲到底了：最後一天太短、上緣碰不到分頁下面，也算看到最後一天
    private var endMark: some View {
        Color.clear
            .frame(height: T.Size.hairline)
            .onScrollVisibilityChange { (on: Bool) in
                scroll.atEnd = on
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /* ---------- 捲動和分頁 ---------- */

    /// 手指捲的時候，捲到哪一天分頁就標到哪一天。點分頁、程式捲的不跟，免得點了第 4 天又跳回別天
    private func scrolled(_ p: ScrollPhase, _ trip: Trip) {
        switch p {
        case .tracking, .interacting, .decelerating:
            scroll.byHand = true
            follow(trip)
        case .idle:
            if scroll.byHand { follow(trip) }
            scroll.byHand = false
        default:
            scroll.byHand = false
        }
    }

    /// 照現在捲到的位置，記下看的是第幾天
    private func follow(_ trip: Trip) {
        guard let found = scroll.dayNow() else { return }
        let d: Int = max(1, min(found, trip.days))
        scroll.at = d
        if d != shownDay(trip) {
            nav.tripDay = d
        }
    }

    /// 點了分頁：記下這一天，捲過去
    private func pick(_ d: Int, _ proxy: ScrollViewProxy) {
        scroll.at = d
        nav.tripDay = d
        land(d, proxy, animated: true)
    }

    /// 別的地方換了天（問 AI 的「看這一天」、跨了一天、換了一趟）：捲到那一天。手指捲出來的不用再捲
    private func moved(_ trip: Trip, _ proxy: ScrollViewProxy) {
        let d: Int = shownDay(trip)
        if scroll.at == d { return }
        scroll.at = d
        land(d, proxy, animated: true)
    }

    /// 打開這一頁：旅途中先捲到今天（或在看的那一天）；出發前、回來後看第 1 天就從最上面看起。
    /// 要等量到黏在上面那一塊多高、看得到那一段多高，落點才對
    private func arrive(_ trip: Trip, _ proxy: ScrollViewProxy) {
        if pinH <= 0 || visibleH <= 0 { return }
        let d: Int = shownDay(trip)
        if scroll.at == d { return }
        scroll.at = d
        if d == 1 && today == nil { return }
        // 等這一輪排版做完再捲，剛出現的時候捲動範圍還沒算好
        Task { @MainActor in
            land(d, proxy, animated: false)
        }
    }

    /// 捲到第 d 天，停穩之後量一次落點：那一天的上緣該在黏頂那一塊下面再空一點，
    /// 差太多就用量到的換算高度（landW）再捲一次。scrollTo 比例點對到哪個高度，CI 實測跟算的差一截，
    /// 所以不猜，量了改（QC-0013 CI run 45747093606：多了 32 點）
    private func land(_ d: Int, _ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(Motion.transition) {
                proxy.scrollTo(dayKey(d), anchor: landing)
            }
        } else {
            proxy.scrollTo(dayKey(d), anchor: landing)
        }
        settleLater(d, proxy, tries: 2)
    }

    private func settleLater(_ d: Int, _ proxy: ScrollViewProxy, tries: Int) {
        if tries <= 0 { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600)) // domy-ignore: 等捲動動畫停穩
            settle(d, proxy, tries: tries)
        }
    }

    /// 量落點、差太多就修。手指在捲、已經換看別天、捲到底了（本來就到不了）都不修
    private func settle(_ d: Int, _ proxy: ScrollViewProxy, tries: Int) {
        guard scroll.at == d, !scroll.byHand, !scroll.atEnd, pinH > 0 else { return }
        guard let top = scroll.tops[d] else { return }
        let want: CGFloat = scroll.line + T.Space.s2
        if abs(top - want) <= T.Size.hairline { return }
        let f: CGFloat = landing.y
        guard f > 0 else { return }
        // 黏頂那一塊的上緣就是看得到那一段的上緣；這一天停在它下面 top - pinTop，對應比例 f
        let pinTop: CGFloat = scroll.line - pinH
        let w: CGFloat = (top - pinTop) / f
        guard w > pinH else { return }
        landW = w
        proxy.scrollTo(dayKey(d), anchor: landing)
        settleLater(d, proxy, tries: tries - 1)
    }

    /// 標題下面一行（線框 A1、A2、A9）：
    /// 出發前「12/16（三）出發・還有 24 天・住明洞一帶」、旅途中「今天第 2 天・12/17（四）・住明洞一帶」、
    /// 回來後「12/16（三）– 12/20（日）・已經回來」。住宿名字、這趟的調整在更多的「行程設定」
    private func subtitle(_ trip: Trip, _ phase: Phase) -> String {
        let hotel: HotelPt = HOTEL[need: baseOf(trip, store.s.settings)]
        let stay: String = "住\(hotel.n)一帶"
        switch phase {
        case .plan(let daysToGo):
            return "\(fmtDay(trip.start))出發・還有 \(daysToGo) 天・\(stay)"
        case .trip(let d):
            return "今天第 \(d) 天・\(tripDayLabel(trip, d))・\(stay)"
        case .done:
            let end: String = addDays(trip.start, trip.days - 1)
            return "\(fmtDay(trip.start))– \(fmtDay(end))・已經回來"
        }
    }

    /// 標題下面：日期那一行，再來是檢查這趟、須知兩個常駐入口（每一天都在，不靠提醒條才出現）
    @ViewBuilder
    private func header(_ trip: Trip, _ phase: Phase) -> some View {
        DomyText(subtitle(trip, phase), .subheadline, tone: .secondary)
            .padding(.top, -T.Space.s4)
            .id("trip-top")
        HStack(spacing: T.Space.s2) {
            EntryChip("檢查這趟", icon: IconPaths.check) {
                nav.push(.check)
            }
            .accessibilityIdentifier("open-check")
            EntryChip("須知", icon: IconPaths.notes) {
                nav.push(.notes)
            }
            .accessibilityIdentifier("open-notes")
        }
        .padding(.top, -T.Space.s2)
    }

    /// 要先訂、還沒在「檢查這趟」打勾的站。全部勾完這一條就不見
    private func unbookedText(_ trip: Trip, _ phase: Phase) -> String? {
        if phase == Phase.done { return nil }
        let unbooked: [Stop] = unbookedOf(trip, store.s.checks)
        if unbooked.isEmpty { return nil }
        var lead: String = ""
        if case .plan(let daysToGo) = phase, daysToGo <= 7 {
            lead = "還有 \(daysToGo) 天出發。"
        }
        let names: [String] = unbooked.map { (x: Stop) -> String in x.n }
        return "\(lead)這趟有 \(unbooked.count) 站要先訂，還沒打勾：\(names.joined(separator: "、"))。"
    }

    /// 要先訂、平常的我改過了：放在地圖上面。旅途中一打開就捲到今天，這幾條在上面，往回捲看得到
    @ViewBuilder
    private func banners(_ trip: Trip, _ phase: Phase) -> some View {
        if let text = unbookedText(trip, phase) {
            Banner(text, actionTitle: "看要先訂的") {
                nav.push(.check)
            }
        }
        if store.s.settingsDirty && tripVisited(trip) {
            // 有去過的站不整趟重排，跟行程設定一樣擋
            Banner(
                "「平常的我」改過了，這趟還是照舊的排。已經有去過的站，整趟重排會把去過的紀錄洗掉，所以不重排。想改哪一天，直接說。",
                actionTitle: "知道了"
            ) {
                store.mutate { (d: inout AppState) -> Void in
                    d.settingsDirty = false
                }
            }
        } else if store.s.settingsDirty {
            Banner("「平常的我」改過了，這趟還是照舊的排。", actionTitle: "照新的設定重排") {
                replan()
            }
        }
    }

    /// 有去過的站就不重排，只講原因，不多一步復原
    private func replan() {
        guard let trip = store.s.trip else { return }
        if tripVisited(trip) {
            store.say(NO_REGEN_VISITED)
            return
        }
        store.act(undoable: true) { (d: inout AppState) -> String? in
            return replanCurrent(&d)
        }
    }
}
