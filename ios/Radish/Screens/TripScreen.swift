// 「這趟」分頁。沒有行程時是開一趟；有行程時上面一排是每一天的分頁，一次只看一天。
// 旅途中最上面多一張「下一站」。不常用的動作收在「更多」。
// 對應 mobile/src/screens/TripScreen.tsx。子元件（每天的分頁、一站的列、行程卡、下一站）在 TripScreenParts.swift。
import SwiftUI

/// 操作說明的三步，順序對應：第一站、用講的改行程、每天的分頁
private let GUIDE: [String] = [
    "每一站都可以點。點進去有韓文名稱、大概花多少、怎麼去，也可以移到別的時段、換一個，或這次不去。",
    "想改行程，用講的就可以。例如「第二天輕鬆一點」。改了不滿意，按提示上的「復原」就回到原本的樣子。",
    "一次只看一天。要看別天，點上面這一排。",
]

/// 操作說明要照亮的那幾塊的名字（也是捲動用的 id）
private enum SpotKey {
    static let top: String = "trip-top"
    static let talk: String = "spot-talk"
    static let tabs: String = "spot-tabs"
    /// 這天沒有排站的時候，第一步用這個不存在的名字，說明會自己跳過那一步
    static let none: String = "spot-none"
}

struct TripScreen: View {
    let goSettings: () -> Void
    let goPrep: (PrepStage) -> Void

    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    /// 使用者點了哪一天。還沒點過就跟著今天（旅途中）或第 1 天
    @State private var day: Int? = nil
    // 操作說明要用的：要捲到哪一塊、要照亮的三塊現在在哪、說明是不是開著
    @State private var scrollTarget: String? = nil
    @State private var frames: SpotFrames = SpotFrames()
    @State private var guideOn: Bool = false

    init(goSettings: @escaping () -> Void, goPrep: @escaping (PrepStage) -> Void) {
        self.goSettings = goSettings
        self.goPrep = goPrep
    }

    /// 旅途中的今天是第幾天。不在旅途中就是 nil
    private var today: Int? {
        if case .trip(let d)? = store.phase { return d }
        return nil
    }

    // 第一趟排好之後帶一次，只帶一次。回來之後的畫面沒有這三塊，不帶
    private var guide: Bool {
        guard store.s.trip != nil, let phase = store.phase else { return false }
        return !store.s.guideSeen && phase != Phase.done
    }

    var body: some View {
        Group {
            if let trip = store.s.trip, let phase = store.phase {
                tripBody(trip, phase)
            } else {
                StartTrip(goSettings: goSettings)
            }
        }
        .onChange(of: today) { _, now in
            if let now {
                day = now
            }
        }
        .onChange(of: guide, initial: true) { _, on in
            setGuide(on)
        }
        .fullScreenCover(isPresented: $guideOn) {
            Spotlight(
                steps: guideSteps,
                frames: frames,
                onScroll: { (key: String?) in scrollTarget = key },
                onDone: { guideDone() }
            )
            .presentationBackground(Color.clear)
        }
    }

    /// 說明自己淡入淡出，所以開和關都不要系統的滑入動畫
    private func setGuide(_ on: Bool) {
        if on {
            scrollTarget = nil
        }
        var quiet: Transaction = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            guideOn = on
        }
    }

    private func guideDone() {
        store.mutate { (d: inout AppState) in
            d.guideSeen = true
        }
        scrollTarget = SpotKey.top
    }

    private var guideSteps: [SpotStep] {
        var first: String = SpotKey.none
        if let trip = store.s.trip {
            let stops: [Found] = dayStops(trip, shownDay(trip))
            if let x = stops.first {
                first = "stop-row-\(x.it.id)"
            }
        }
        let keys: [String] = [first, SpotKey.talk, SpotKey.tabs]
        var out: [SpotStep] = []
        for i in 0..<GUIDE.count {
            out.append(SpotStep(key: i < keys.count ? keys[i] : SpotKey.none, text: GUIDE[i]))
        }
        return out
    }

    /// 現在看的是第幾天
    private func shownDay(_ trip: Trip) -> Int {
        return max(1, min(day ?? today ?? 1, trip.days))
    }

    private func tripBody(_ trip: Trip, _ phase: Phase) -> some View {
        let shown: Int = shownDay(trip)
        return Screen(tripTitle(trip), scrollTo: scrollTarget) {
            header(trip, phase)
            if phase == Phase.done {
                doneCard(trip)
            }
            if let now = today {
                TripNextStop(trip: trip, day: now)
                DomyButton("換算、記一筆花費", variant: .secondary, fullWidth: true) {
                    goPrep(.cost)
                }
                .accessibilityIdentifier("open-cost")
            }
            banners(trip, phase)
            VStack(alignment: .leading, spacing: T.Space.s3) {
                TripDayTabs(trip: trip, value: shown, today: today) { (d: Int) in
                    day = d
                }
                .spotTarget(SpotKey.tabs, in: frames)
                TripDayCard(trip: trip, day: shown, frames: frames)
            }
            if phase != Phase.done {
                talkButtons(shown)
            }
            DomyText("這一版的地點是範例資料，還沒核對過。營業時間、休館日、票價要自己查。", .footnote, tone: .secondary, align: .center)
                .frame(maxWidth: .infinity)
        }
    }

    /// 標題下面那幾行：日期、現在在哪個階段、住哪、這趟的調整
    private func subtitle(_ trip: Trip, _ phase: Phase) -> String {
        let end: String = addDays(trip.start, trip.days - 1)
        var text: String = "\(fmtDay(trip.start))–\(fmtDay(end))"
        switch phase {
        case .plan(let daysToGo):
            text += "・還有 \(daysToGo) 天出發"
        case .trip(let d):
            text += "・今天是第 \(d) 天"
        case .done:
            text += "・已經回來了"
        }
        let hotel: HotelPt = HOTEL[need: baseOf(trip, store.s.settings)]
        text += "\n住\(hotel.n)一帶"
        if let stay = trip.stayName, !stay.isEmpty {
            text += "・" + stay
        }
        if let tweaks = trip.tweaks, !tweaks.isEmpty {
            text += "\n這趟：\(tweakSummary(trip))"
        }
        return text
    }

    @ViewBuilder
    private func header(_ trip: Trip, _ phase: Phase) -> some View {
        DomyText(subtitle(trip, phase), .subheadline, tone: .secondary)
            .padding(.top, -T.Space.s4)
            .id(SpotKey.top)
        DomyButton("改日期、住哪、這趟的調整", variant: .plain, size: .compact) {
            sheets.open(.settings)
        }
        .accessibilityIdentifier("trip-edit")
        .padding(.top, -T.Space.s3)
    }

    private func doneCard(_ trip: Trip) -> some View {
        let all: [Found] = allItems(trip)
        let pulled: Int = all.filter { (x: Found) -> Bool in x.it.status == .pulled }.count
        return Card {
            HStack(spacing: T.Space.s3) {
                VStack(alignment: .leading, spacing: T.Space.s1) {
                    DomyText("這趟走完了", .title2)
                    DomyText(
                        "這趟去了 \(pulled) 個地方。有去過但沒按到的，點那一站可以補。在「旅行」可以把它做成地圖網頁，傳給沒去的人看。",
                        .body, tone: .secondary)
                }
                .fillLeading()
                RadishBuddy(action: .bow)
            }
            DomyButton("收起來，開新的一趟", fullWidth: true) {
                store.act(undoable: true) { (d: inout AppState) -> String? in
                    return archiveTrip(&d)
                }
            }
            .accessibilityIdentifier("trip-archive")
        }
    }

    /// 要先訂、還沒在「行前」打勾的站。全部勾完這一條就不見
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

    @ViewBuilder
    private func banners(_ trip: Trip, _ phase: Phase) -> some View {
        if let text = unbookedText(trip, phase) {
            Banner(text, actionTitle: "看要先訂的") {
                goPrep(.before)
            }
        }
        if store.s.settingsDirty {
            Banner("「我」裡的設定改過了，這趟還是照舊的排。", actionTitle: "照新的設定重排") {
                replan()
            }
        }
    }

    private func replan() {
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard let old = d.trip else { return nil }
            let own: (flight: Double, spend: [Spend]?, rate: Double?) = ownOf(old)
            var next: Trip = generate(draftOf(old), d.settings)
            next.flight = own.flight
            next.spend = own.spend
            next.rate = own.rate
            d.trip = next
            d.settingsDirty = false
            return "照新的設定重排了。手動改過的地方也一起重排了。"
        }
    }

    private func talkButtons(_ shown: Int) -> some View {
        VStack(spacing: T.Space.s2) {
            DomyButton("用講的改行程", variant: today != nil ? .secondary : .primary, fullWidth: true) {
                sheets.open(.chat)
            }
            .accessibilityIdentifier("open-chat")
            .spotTarget(SpotKey.talk, in: frames)
            DomyButton("更多", variant: .plain, fullWidth: true) {
                sheets.open(.more(day: shown))
            }
            .accessibilityIdentifier("open-more")
        }
    }
}
