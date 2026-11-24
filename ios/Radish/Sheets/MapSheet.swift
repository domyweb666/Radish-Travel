// 這一天的路線（S12，線框 A8）：地圖、每一段怎麼去，下緣釘著路上大約幾分鐘（估）和「請 AI 提一個改法」。
// 半頁，可以拉到全高。下緣那一塊不跟著捲，半頁一打開就看得到；兩面都一樣，「這次會改」那一面釘的是改完幾分鐘和兩顆鈕。
// 分鐘數照 Plan.swift 的 dayLegs，總數含從住的地方出發和回去（跟這一天清單加總的方式一樣）。
// 按「請 AI 提一個改法」之後，同一張換成「這次會改」那一面：哪幾站換時段、改完路上大約幾分鐘（估）、少幾分鐘（估），
// 「照這樣改」（可以復原）或「不用改」都回到路線那一面。能送 AI 就問 AI（只准同一天換時段），不能送就手機自己算；
// 規則、提示詞、試套都在 RadishCore/RouteSuggest.swift。
// 原本對應 mobile/src/sheets/MapSheet.tsx（看這天的地圖），2026-11-23 照 A 版線框改。
import SwiftUI

/// legs[i]，超出範圍就當成不明
private func mapLegAt(_ legs: [Leg?], _ i: Int) -> Leg? {
    guard i >= 0 && i < legs.count else { return nil }
    return legs[i]
}

/// 路線的一段：從哪到哪、怎麼去
private struct RouteLeg: Identifiable {
    let id: Int
    let title: String
    let note: String
}

/// 住的地方 → 1 → 2 → … → 住的地方。號碼跟地圖上的標記一樣
private func routeLegs(_ h: HotelPt, _ stops: [Stop], _ legs: [Leg?]) -> [RouteLeg] {
    let home: String = "\(h.n)（住的地方）"
    var out: [RouteLeg] = []
    for i in 0...stops.count {
        let from: String = i == 0 ? home : "\(i) \(stops[i - 1].n)"
        let to: String = i == stops.count ? home : "\(i + 1) \(stops[i].n)"
        out.append(RouteLeg(id: i, title: "\(from) → \(to)", note: legText(mapLegAt(legs, i))))
    }
    return out
}

/// 路上大約幾分鐘（估）。釘在半頁下緣，寫短一點；「含從住的地方出發和回去」寫在每一段下面的小字。
/// 距離不明的那幾段沒算進去，要講出來
private func routeTotal(_ legs: [Leg?]) -> String {
    var total: Int = 0
    var unknown: Int = 0
    for l in legs {
        if let l {
            total += l.min
        } else {
            unknown += 1
        }
    }
    var out: String = "\(legs.count) 段・路上大約 \(total) 分鐘（估）"
    if unknown > 0 {
        out += "。有 \(unknown) 段距離不明，沒算進去"
    }
    return out
}

/// 沒拿出改法時，路線那一面寫的一句。detail 是小字（錯誤代碼、為什麼這次是手機算的）
private struct RouteNote: Identifiable {
    /// 每一句都不一樣，連寫兩次一樣的話也要捲回最上面
    let id: UUID = UUID()
    var text: String
    var detail: String?
}

/// 捲回最上面用的代號
private let ROUTE_TOP: String = "route-top"

struct MapSheet: View {
    let day: Int
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    /// 有值就是「這次會改」那一面
    @State private var plan: RoutePlan?
    /// 手機算的時候，為什麼沒有問 AI（沒網路、句數用完、還沒同意）。問 AI 的是 nil
    @State private var planWhy: String?
    /// 在等 AI：按鈕變「AI 在想…」不能再按
    @State private var asking: Bool = false
    @State private var note: RouteNote?

    init(day: Int) {
        self.day = day
    }

    var body: some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            SheetScaffold("第 \(day) 天的路線", onClose: { sheets.close() }) {
                VStack(alignment: .leading, spacing: T.Space.s4) {
                    faces
                }
                .id(ROUTE_TOP)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
            // 按鈕釘在下緣，按的時候可能正捲在下面：寫了一句話、換了一面，都捲回最上面才看得到
            .onChange(of: note?.id) { (_: UUID?, now: UUID?) in
                if now != nil {
                    toTop(proxy)
                }
            }
            .onChange(of: plan != nil) { (_: Bool, _: Bool) in
                toTop(proxy)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var faces: some View {
        if let trip = store.s.trip {
            if let plan {
                suggestFace(plan)
            } else {
                content(trip)
            }
        } else {
            DomyText("現在沒有這趟。", .body, tone: .secondary)
        }
    }

    /// 釘在半頁下緣的那一塊。沒有這趟、這天沒有站就不出現
    @ViewBuilder
    private var footer: some View {
        if let trip = store.s.trip {
            if let plan {
                footerBox {
                    suggestFooter(plan)
                }
            } else if !stopsOf(trip).isEmpty {
                footerBox {
                    routeFooter(trip)
                }
            }
        }
    }

    private func footerBox<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: T.Space.s3) {
                inner()
            }
            .padding(.top, T.Space.s3)
            .padding(.horizontal, T.Size.screenMargin)
            .padding(.bottom, T.Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.canvas.ignoresSafeArea(edges: .bottom))
    }

    private func toTop(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.transition) {
            proxy.scrollTo(ROUTE_TOP, anchor: .top)
        }
    }

    private func stopsOf(_ trip: Trip) -> [Stop] {
        return dayStops(trip, day).map { (x: Found) -> Stop in x.it }
    }

    /// 地圖上的點：住的地方，再來是有座標的站。號碼照這天第幾站，沒座標的站跳過但號碼不重排
    private func pointsOf(_ h: HotelPt, _ stops: [Stop]) -> [MapPoint] {
        var out: [MapPoint] = [
            MapPoint(key: "home", title: "住的地方（\(h.n)）", subtitle: h.kr, lat: h.lat, lng: h.lng, home: true)
        ]
        for (i, it) in stops.enumerated() {
            if let lat = it.lat, let lng = it.lng {
                out.append(MapPoint(key: it.id, title: it.n, subtitle: it.kr, lat: lat, lng: lng, num: i + 1))
            }
        }
        return out
    }

    /* ---------- 路線那一面 ---------- */

    @ViewBuilder
    private func content(_ trip: Trip) -> some View {
        let h: HotelPt = hotelPt(store.s.settings, trip)
        let stops: [Stop] = stopsOf(trip)
        let legs: [Leg?] = dayLegs(trip, store.s.settings, day)
        DomyText("\(fmtDay(addDays(trip.start, day - 1)))・從\(h.n)出發，回到\(h.n)", .footnote, tone: .secondary)
        if stops.isEmpty {
            DomyText("這天沒有排站。", .body, tone: .secondary)
        } else {
            if let note {
                noteCard(note)
            }
            VStack(alignment: .leading, spacing: T.Space.s2) {
                DayMap(points: pointsOf(h, stops), compact: true)
                DomyText("底圖要網路，沒網路時地圖上只剩點，下面每一段照樣看得到。", .caption, tone: .secondary)
            }
            legSection(routeLegs(h, stops, legs))
        }
    }

    @ViewBuilder
    private func routeFooter(_ trip: Trip) -> some View {
        DomyText(routeTotal(dayLegs(trip, store.s.settings, day)), .subheadline, weight: .semibold, numeric: true)
            .accessibilityIdentifier("route-total")
        askButton
    }

    private func legSection(_ rows: [RouteLeg]) -> some View {
        DomySection(footer: "總分鐘含從住的地方出發和回去。手機算的，沒有問 AI：照直線距離加三成估，沒有查路線。真的要走的時候，從每一站跳去 Naver 地圖。") {
            ForEach(rows) { (row: RouteLeg) in
                TextRow(row.title, note: row.note)
            }
        }
    }

    private func noteCard(_ n: RouteNote) -> some View {
        Card(tone: .tint) {
            DomyText(n.text, .subheadline)
            if let detail = n.detail, !detail.isEmpty {
                DomyText(detail, .caption, tone: .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("route-note")
    }

    private var askButton: some View {
        DomyButton(asking ? "AI 在想…" : "請 AI 提一個改法", variant: .secondary, disabled: asking, fullWidth: true) {
            ask()
        }
        .accessibilityIdentifier("route-ask")
    }

    /* ---------- 這次會改那一面 ---------- */

    private func suggestFace(_ p: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s4) {
            Card(tone: .tint) {
                Tag(p.by == .ai ? "AI 提的" : "手機算的，沒有問 AI", tone: p.by == .ai ? .accent : .neutral)
                DomyText("這次會改", .headline)
                if !p.reply.isEmpty {
                    DomyText(p.reply, .subheadline, tone: .secondary)
                }
                if let why = planWhy, !why.isEmpty {
                    DomyText(why, .caption, tone: .secondary)
                }
            }
            DomySection(footer: "只在這天裡換時段，站沒有增減。分鐘數照直線距離加三成估，沒有查路線。") {
                ForEach(p.moves, id: \.self) { (m: RouteMove) in
                    TextRow(routeMoveLine(m))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-suggest")
    }

    @ViewBuilder
    private func suggestFooter(_ p: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s1) {
            DomyText("改完路上大約 \(p.after) 分鐘（估）", .subheadline, weight: .semibold, numeric: true)
            DomyText("比原本少 \(p.saved) 分鐘（估）。原本大約 \(p.before) 分鐘（估）。", .footnote, tone: .secondary, numeric: true)
        }
        .accessibilityElement(children: .combine)
        HStack(spacing: T.Space.s2) {
            DomyButton("照這樣改", fullWidth: true) {
                apply(p)
            }
            .accessibilityIdentifier("route-apply")
            DomyButton("不用改", variant: .secondary, fullWidth: true) {
                back()
            }
            .accessibilityIdentifier("route-skip")
        }
    }

    /* ---------- 動作 ---------- */

    /// 按下那一刻的「現在」。旅途中過去的時段、拔起來的站都不動
    private var clock: ChatClock? {
        return store.phase.map { (p: Phase) -> ChatClock in chatClock(p) }
    }

    /// 為什麼這次是手機算的。根本沒接 AI 就不多講
    private var phoneWhy: String? {
        if !store.aiOn { return nil }
        if let hold = store.talkHold {
            return hold == .offline ? "現在沒網路，這次先用手機算。" : "這趟問 AI 的句數用完了，這次先用手機算。"
        }
        if !store.s.aiConsent { return ROUTE_NEED_CONSENT }
        return nil
    }

    /// 能送 AI 就問 AI；沒接 AI、沒網路、句數用完、還沒同意送資料，就手機自己算
    private func ask() {
        guard let trip = store.s.trip, !asking else { return }
        let settings: Settings = store.s.settings
        let at: ChatClock? = clock
        let now: TripNow? = tripNow(at)
        let d: Int = day
        withAnimation(Motion.change) {
            note = nil
        }
        let canAI: Bool = store.aiOn && store.talkHold == nil && store.s.aiConsent
        if !canAI {
            show(routePhone(trip, settings, d, now), by: .phone, why: phoneWhy)
            return
        }
        let prompt: String = routePrompt(trip, settings, d, at)
        let app: AppStore = store
        asking = true
        Task { @MainActor in
            do {
                let out: BrainOut = try await askAI(prompt)
                app.countAISentence(trip.id)
                asking = false
                // 等的時候這趟可能變了（例：別的地方改了），照現在的行程試套
                guard let current = app.s.trip else { return }
                show(routeTry(current, app.s.settings, d, out.ops, now, by: .ai, reply: out.reply), by: .ai, why: nil)
            } catch {
                asking = false
                Haptic.notify(.error)
                withAnimation(Motion.change) {
                    note = RouteNote(text: ROUTE_ASK_FAILED, detail: (error as? AskError)?.description)
                }
            }
        }
    }

    /// 有改法就換到「這次會改」那一面，沒有就在路線那一面寫一句
    private func show(_ v: RouteVerdict, by: RouteBy, why: String?) {
        if case .plan(let p) = v {
            withAnimation(Motion.transition) {
                planWhy = why
                plan = p
            }
            return
        }
        withAnimation(Motion.change) {
            note = RouteNote(text: routeVerdictText(v, by), detail: why)
        }
    }

    /// 照這樣改：先照現在的行程再試一次（看的這段時間可能變了），還套得上才改，提示條帶復原
    private func apply(_ p: RoutePlan) {
        let d: Int = day
        let settings: Settings = store.s.settings
        let now: TripNow? = tripNow(clock)
        guard let trip = store.s.trip,
            case .plan(let fresh) = routeTry(trip, settings, d, p.ops, now, by: p.by, reply: p.reply)
        else {
            Haptic.notify(.error)
            back()
            withAnimation(Motion.change) {
                note = RouteNote(text: "行程剛剛變了，這個改法套不上，這天先不動。", detail: nil)
            }
            return
        }
        store.act(undoable: true) { (s: inout AppState) -> String? in
            guard var t = s.trip else { return nil }
            var seeds: [Seed] = s.seeds
            applyOps(&t, &seeds, fresh.ops, now, true)
            s.trip = t
            s.seeds = seeds
            return "第 \(d) 天照這樣改了，路上大約 \(fresh.after) 分鐘（估）。"
        }
        back()
    }

    /// 回到路線那一面
    private func back() {
        withAnimation(Motion.transition) {
            plan = nil
            planWhy = nil
        }
    }
}
