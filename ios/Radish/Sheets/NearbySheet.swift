// 附近還有什麼（S10，線框 A12）：從這一天的下一站（或起點）算，這趟還沒排的地方照距離排，一次三個。
// 「排進來」排進這一天（store.act(undoable: true)，可以復原）、「看那站」推進一站、「再看三個」、
// 「跟 AI 講條件」到問 AI 分頁。距離和怎麼去都是手機估的，規則在 Plan.swift 的 nearbyRanked。
// iOS 版才有，mobile/ 沒有對應的 TS（Expo 版的順路可去只有名字，見 Plan.swift 的 nearbyPool）。
import SwiftUI

struct NearbySheet: View {
    let day: Int
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    /// 第幾組三個。關掉再打開從頭開始（被打斷不還原）
    @State private var page: Int = 0

    init(day: Int) {
        self.day = day
    }

    var body: some View {
        SheetScaffold("附近還有什麼", onClose: { sheets.close() }) {
            if let trip = store.s.trip {
                content(trip)
            } else {
                DomyText("現在沒有這趟。", .body, tone: .secondary)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 旅途中的現在；出發前、回來後是 nil
    private var now: TripNow? {
        guard let phase = store.phase else { return nil }
        return tripNow(chatClock(phase))
    }

    /// 看的這一天是不是今天
    private var isToday: Bool {
        if case .trip(let d)? = store.phase { return d == day }
        return false
    }

    @ViewBuilder
    private func content(_ trip: Trip) -> some View {
        let origin: NearbyOrigin = nearbyOrigin(trip, store.s.settings, day)
        let ranked: [NearbyPick] = nearbyRanked(trip, store.s.settings, day)
        let part: Part? = nearbyPart(trip, day, origin, now)
        DomyText(originLine(origin), .footnote, tone: .secondary)
            .accessibilityIdentifier("nearby-origin")
        if !origin.known {
            unknownState(origin)
        } else if ranked.isEmpty {
            emptyState
        } else {
            picks(trip, nearbyPage(ranked, page), origin, part != nil)
            moreRow(ranked.count)
            DomyText(footnote(nearbyPage(ranked, page)), .footnote, tone: .secondary)
        }
    }

    /// 第一次打開就寫清楚從哪裡算
    private func originLine(_ o: NearbyOrigin) -> String {
        switch o.from {
        case .next:
            return "從\(o.name)算，這趟還沒排的，照距離排"
        case .pulled:
            return "這天的站都拔完了，從最後拔起來的\(o.name)算，這趟還沒排的，照距離排"
        case .home:
            return "這天還沒排站，從\(o.name)算，這趟還沒排的，照距離排"
        }
    }

    private func footnote(_ shown: [NearbyPick]) -> String {
        let hasTip: Bool = shown.contains { (x: NearbyPick) -> Bool in
            guard let tip = tipOf(planToStop(x.place, "")) else { return false }
            return tip.status == FactStatus.none || tip.extra != nil
        }
        let base: String = "手機算的，沒有問 AI：距離照直線加三成估，沒有查路線。"
        return hasTip ? base + "寫未核對的須知是資料包寫的。" : base
    }

    /// left 是這天還有沒有能排的時段。有的話，每個地方再各自避開它不開的時段
    private func picks(_ trip: Trip, _ shown: [NearbyPick], _ origin: NearbyOrigin, _ left: Bool) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            ForEach(Array(shown.enumerated()), id: \.element.place.id) { i, pick in
                let part: Part? = nearbyPart(trip, day, origin, now, place: pick.place)
                NearbyCard(
                    pick: pick, index: i, addTitle: addTitle(part, left), canAdd: part != nil,
                    onAdd: {
                        if let part { add(pick.place, part, origin) }
                    },
                    onOpen: { openStop(pick.place.id) })
            }
        }
    }

    /// 「排進今天下午」；不是今天就寫第幾天；這天的時段都過了、能排的時段它都不開，就不能按
    private func addTitle(_ part: Part?, _ left: Bool) -> String {
        guard let part else { return left ? "能排的時段它都不開" : "這天的時段都過了" }
        let when: String = isToday ? "今天" : "第 \(day) 天"
        return "排進\(when)\(PART[need: part])"
    }

    private func moreRow(_ count: Int) -> some View {
        // 字級放大時兩顆放不下，改成一顆一列
        PairLayout(spacing: T.Space.s2) {
            if count > NEARBY_PAGE {
                DomyButton("再看三個", variant: .plain, fullWidth: true) {
                    page += 1
                }
                .accessibilityIdentifier("nearby-more")
            }
            askButton
        }
    }

    private var askButton: some View {
        DomyButton("跟 AI 講條件", variant: .plain, fullWidth: true) {
            goAsk()
        }
        .accessibilityIdentifier("nearby-ask")
    }

    /// 起點不明：自己加的、AI 加的站沒有位置，手機算不出離它多遠
    private func unknownState(_ o: NearbyOrigin) -> some View {
        DomyEmptyState(
            icon: IconPaths.sprout, title: "算不出附近",
            message: "「\(o.name)」沒有位置資料，手機算不出離它多遠。可以跟 AI 講你在哪一帶。",
            actionTitle: "跟 AI 講條件"
        ) {
            goAsk()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby-unknown")
    }

    /// 空：附近都排過了，或這趟不排的
    private var emptyState: some View {
        DomyEmptyState(
            icon: IconPaths.sprout, title: "附近沒有還沒排的地方",
            message: "離這裡 \(Int(NEARBY_MAX_KM)) 公里內（估），資料包裡的地方都排進這趟了、這天不開，或是你說過不排的。",
            actionTitle: "跟 AI 講條件"
        ) {
            goAsk()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby-empty")
    }

    /// 排進這一天。跟起點同一個時段的話排在起點那一站後面。排好關掉這張，提示條上可以復原
    private func add(_ p: Place, _ part: Part, _ origin: NearbyOrigin) {
        let d0: Int = day
        let after: String? = origin.part == part ? origin.stopId : nil
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            if let err = addNearby(&trip, p, d0, part, after) { return err }
            d.trip = trip
            return "「\(p.n)」排進第 \(d0) 天\(PART[need: part])了"
        }
        sheets.close()
    }

    private func openStop(_ id: String) {
        sheets.close()
        nav.push(.stop(id: id))
    }

    private func goAsk() {
        sheets.close()
        nav.show(.ask)
    }
}

/// 附近的一個地方：名字、要先訂、怎麼去（估）、須知，下面排進來和看那站
private struct NearbyCard: View {
    let pick: NearbyPick
    let index: Int
    let addTitle: String
    let canAdd: Bool
    let onAdd: () -> Void
    let onOpen: () -> Void

    /// 須知照站查，先換成一站
    private var asStop: Stop {
        return planToStop(pick.place, "")
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                HStack(spacing: T.Space.s2) {
                    DomyText(pick.place.n, .headline)
                    if pick.place.b == true {
                        Tag("要先訂")
                    }
                }
                DomyText(legText(pick.leg), .footnote)
                if let tip = tipOf(asStop) {
                    DomyText("須知：\(tip.text)（\(tipSourceLabel(asStop))）", .footnote, tone: .secondary)
                    if let extra = tip.extra, !extra.isEmpty {
                        DomyText("\(extra)（未核對）", .footnote, tone: .secondary)
                    }
                }
            }
            buttons
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby-pick-\(index)")
    }

    private var buttons: some View {
        HStack(spacing: T.Space.s2) {
            DomyButton(addTitle, variant: .secondary, size: .compact, disabled: !canAdd, fullWidth: true, action: onAdd)
                .accessibilityIdentifier("nearby-add-\(index)")
            DomyButton("看那站", variant: .plain, size: .compact, action: onOpen)
                .accessibilityIdentifier("nearby-open-\(index)")
        }
    }
}
