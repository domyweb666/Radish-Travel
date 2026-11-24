// 「這趟」分頁（S01，線框 A1、A2、A4、A9）。沒有行程時是開一趟；有行程時上面一排是每一天的分頁，一次只看一天。
// 右上角是更多和平常的我；標題下面一行日期，再來兩個常駐入口：檢查這趟、須知（推進）。
// 旅途中最上面多一張「下一站」。最下面一直有一列跟 AI 講（TalkBar），左邊小標寫在看第幾天或今天。
// 第一趟排好後的三步操作說明拿掉了（02-流程 1-4、❓38 建議刪，方向說明 A17「跟著 1-4 刪操作說明」）。
// 對應 mobile/src/screens/TripScreen.tsx。子元件（每天的分頁、一站的列、下一站）在 TripScreenParts.swift，
// 剛排好那張卡、回來後那張卡在 Components/TripCards.swift。
import SwiftUI

struct TripScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    @Environment(Sheets.self) private var sheets
    /// 這一天每一站在畫面上的位置。原本給操作說明照亮第一站用，說明拿掉了，TripDayCard 還要這個參數
    @State private var frames: SpotFrames = SpotFrames()

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
        .onChange(of: today) { _, now in
            if let now {
                nav.tripDay = now
            }
        }
    }

    /// 現在看的是第幾天：使用者點了哪一天（記在 Nav，切分頁回來還在）；還沒點過就跟著今天（旅途中）或第 1 天
    private func shownDay(_ trip: Trip) -> Int {
        return max(1, min(nav.tripDay ?? today ?? 1, trip.days))
    }

    /// 講的那一列左邊的小標：旅途中看的是今天就寫「今天」
    private func talkLabel(_ day: Int) -> String {
        return day == today ? "今天" : "第 \(day) 天"
    }

    private func tripBody(_ trip: Trip, _ phase: Phase) -> some View {
        let shown: Int = shownDay(trip)
        return Screen(
            tripTitle(trip),
            actions: {
                TopActions(more: { sheets.open(.more(day: shown)) })
            }
        ) {
            header(trip, phase)
            if phase == Phase.done {
                DoneCard(trip: trip)
            }
            if let now = today {
                TripNextStop(trip: trip, day: now)
            }
            banners(trip, phase)
            dayBlock(trip, phase, shown)
            DomyText("這一版的地點是範例資料，還沒核對過。營業時間、休館日、票價要自己查。", .footnote, tone: .secondary, align: .center)
                .frame(maxWidth: .infinity)
        }
        .talkBar(talkLabel(shown), target: .day(shown))
    }

    /// 天數那一排、剛排好那張卡（A4，自己決定要不要顯示）、這一天的清單。回來後多一行小字（A9）
    private func dayBlock(_ trip: Trip, _ phase: Phase, _ shown: Int) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            TripDayTabs(trip: trip, value: shown, today: today) { (d: Int) in
                nav.tripDay = d
            }
            if phase == Phase.done {
                DomyText("有去過但沒按到的，點那一站可以補。", .footnote, tone: .secondary)
            } else {
                PlannedCard(trip: trip)
            }
            TripDayCard(trip: trip, day: shown, frames: frames)
        }
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

    @ViewBuilder
    private func banners(_ trip: Trip, _ phase: Phase) -> some View {
        if let text = unbookedText(trip, phase) {
            Banner(text, actionTitle: "看要先訂的") {
                nav.push(.check)
            }
        }
        if store.s.settingsDirty {
            Banner("「平常的我」改過了，這趟還是照舊的排。", actionTitle: "照新的設定重排") {
                replan()
            }
        }
    }

    private func replan() {
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard let old = d.trip else { return nil }
            d.trip = replanTrip(old, draftOf(old), d.settings)
            d.settingsDirty = false
            return "照新的設定重排了。手動改過的地方也一起重排了。"
        }
    }
}
