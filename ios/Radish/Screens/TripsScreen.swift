// 「旅行」分頁（S19，線框 .uiux/03-線框/線框/A15-Trips.dc.html）：每一趟是一個資料夾。
// 我的旅行：現在這趟、其他排好的、開新的一趟、去過的旅行；可以同時排好幾趟，點一下就切過去。
// 「下次再來」是這幾趟拿掉、排不進去的地方。這一頁沒有跟 AI 講的那一列。
// 去過的那一趟是推進頁（VisitedScreen），從這裡的「去過的 N 站」和去過的旅行進去。
// 對應 mobile/src/screens/TripsScreen.tsx。
import SwiftUI

private enum TripsTab: Hashable {
    case trips, later
}

/// 一組：小標題、白卡。線框的小標題是小灰字，不是 DomySection 的大標題
private struct TripsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyText(title, .footnote, tone: .secondary)
                .padding(.horizontal, T.Space.s1)
                .accessibilityAddTraits(.isHeader)
            DomySection(footer: footer) {
                content
            }
        }
    }
}

/// 一組裡還沒有東西時的那一行
private struct NoneRow: View {
    let text: String

    var body: some View {
        DomyText(text, .subheadline, tone: .secondary)
            .padding(.vertical, T.Space.s3)
            .frame(maxWidth: .infinity, minHeight: T.Size.row, alignment: .leading)
    }
}

/// 一趟一列：有封面照就放在左邊，右邊是箭頭
private struct TripRow: View {
    let title: String
    let meta: String
    let cover: String?
    let testId: String
    let action: () -> Void

    private var row: some View {
        HStack(spacing: T.Space.s3) {
            if let cover {
                TripCover(ref: cover)
            }
            VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
                DomyText(title, .headline, lines: 2)
                DomyText(meta, .footnote, tone: .secondary)
            }
            .fillLeading()
            Chevron()
        }
        .padding(.vertical, T.Space.s3)
        .frame(minHeight: T.Size.row)
        .padding(.horizontal, T.Space.s4)
        .contentShape(Rectangle())
    }

    var body: some View {
        Button(action: action) { row }
            .buttonStyle(RowPressStyle())
            .padding(.horizontal, -T.Space.s4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(meta)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(testId)
    }
}

/// 封面照：方的一小張。檔案讀不到時顯示灰底，不讓版面跳掉
private struct TripCover: View {
    let ref: String

    var body: some View {
        // 線框 A15 的封面是 80 點的方塊：一列高 52 加 24 加 4
        let edge: CGFloat = T.Size.row + T.Space.s6 + T.Space.s1
        let shape = RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
        PhotoImage(ref: ref, edge: edge)
            .frame(width: edge, height: edge)
            .background(C.surfaceMuted)
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}

struct TripsScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    @State private var tab: TripsTab = .trips
    private let goTrip: () -> Void

    init(goTrip: @escaping () -> Void) {
        self.goTrip = goTrip
    }

    private var curPulled: Int {
        guard let cur = store.s.trip else { return 0 }
        return visitedOf(cur).count
    }

    private func range(_ start: String, _ days: Int) -> String {
        return "\(fmtDay(start)) – \(fmtDay(addDays(start, days - 1)))"
    }

    private func when(_ t: Trip, _ debugDay: Int?) -> String {
        let p: Phase = phaseOf(t.start, t.days, store.today, debugDay)
        switch p {
        case .plan(let daysToGo):
            return "還有 \(daysToGo) 天"
        case .trip(let day):
            return "旅途中，第 \(day) 天"
        case .done:
            return "已經回來了"
        }
    }

    private var empty: Bool {
        return store.s.trip == nil && store.s.shelf.isEmpty && store.s.baskets.isEmpty
    }

    var body: some View {
        Screen("旅行", actions: { TopActions() }) {
            Segmented(
                value: tab,
                options: [(TripsTab.trips, "我的旅行"), (TripsTab.later, "下次再來")]
            ) { (next: TripsTab) in
                tab = next
            }
            if tab == .trips {
                tripsTab
            } else {
                laterTab
            }
        }
    }

    /* ---------- 我的旅行 ---------- */

    @ViewBuilder private var tripsTab: some View {
        if empty {
            DomyEmptyState(
                icon: IconPaths.tabTrips,
                title: "還沒有旅行",
                message: "每排一趟，這裡就多一個資料夾。去過的地方、寫的那一句、照片都收在那一趟裡面。",
                actionTitle: "去排一趟"
            ) {
                goTrip()
            }
        } else {
            if let cur = store.s.trip {
                currentSection(cur)
            }
            shelfSection
            newTripButton
            basketsSection
        }
    }

    private func currentSection(_ cur: Trip) -> some View {
        let pulled: Int = curPulled
        return TripsGroup("現在這趟") {
            TripRow(
                title: tripTitle(cur),
                meta: "\(range(cur.start, cur.days))・\(when(cur, store.s.debugDay))",
                cover: cur.cover,
                testId: "trip-card-current"
            ) {
                goTrip()
            }
            if pulled > 0 {
                DomyListRow(meta: "這趟到目前為止", title: "去過的 \(pulled) 站") {
                    nav.push(.visited(.current))
                }
                .accessibilityIdentifier("trips-album-current")
            }
        }
    }

    private var shelfSection: some View {
        let shelf: [Shelved] = store.s.shelf
        return TripsGroup(
            "其他排好的", footer: shelf.isEmpty ? nil : "點一下切到那一趟。現在這趟會原樣留著，不會不見。"
        ) {
            if shelf.isEmpty {
                NoneRow(text: "還沒有。")
            } else {
                ForEach(shelf, id: \.id) { (x: Shelved) in
                    TripRow(
                        title: tripTitle(x.trip),
                        meta: "\(range(x.trip.start, x.trip.days))・\(when(x.trip, x.debugDay))",
                        cover: x.trip.cover,
                        testId: "trip-card-\(x.id)"
                    ) {
                        let id: String = x.id
                        store.act { (d: inout AppState) -> String? in
                            return openShelved(&d, id)
                        }
                        goTrip()
                    }
                }
            }
        }
    }

    /// 線框 A15：有這趟時是次要按鈕（主要的是現在這趟），沒有這趟時是主要按鈕
    @ViewBuilder private var newTripButton: some View {
        let hasCur: Bool = store.s.trip != nil
        DomyButton("開新的一趟", variant: hasCur ? .secondary : .primary, fullWidth: true) {
            // 現在這趟先放到其他排好的。不走復原：復原只還原行程，放一邊的那份會多一份
            if store.s.trip != nil {
                store.mutate { (d: inout AppState) in
                    shelveCurrent(&d)
                }
            }
            goTrip()
        }
        .accessibilityIdentifier("trips-new")
        if hasCur {
            DomyText("現在這趟會留在「其他排好的」，隨時可以切回來。", .footnote, tone: .secondary, align: .center)
                .frame(maxWidth: .infinity)
                .padding(.top, -T.Space.s4)
        }
    }

    private func basketMeta(_ b: Basket) -> String {
        var head: String = ""
        if let start = b.start, !start.isEmpty, let days = b.days, days != 0 {
            head = range(start, days) + "・"
        }
        return "\(head)去了 \(b.items.count) 個地方"
    }

    private var basketsSection: some View {
        let baskets: [Basket] = store.s.baskets
        return TripsGroup("去過的旅行") {
            if baskets.isEmpty {
                NoneRow(text: "還沒有。這趟收起來之後，會放在這裡。")
            } else {
                ForEach(baskets, id: \.id) { (b: Basket) in
                    TripRow(
                        title: b.title,
                        meta: basketMeta(b),
                        cover: b.cover,
                        testId: "basket-card-\(b.id)"
                    ) {
                        nav.push(.visited(.basket(id: b.id)))
                    }
                }
            }
        }
    }

    /* ---------- 下次再來 ---------- */

    @ViewBuilder private var laterTab: some View {
        if !store.s.seeds.isEmpty {
            DomySection(footer: "排不進去、或你說先不要的地方都在這裡，不會不見。") {
                ForEach(store.s.seeds, id: \.id) { (seed: Seed) in
                    seedRow(seed)
                }
            }
        } else {
            DomyEmptyState(
                icon: IconPaths.sprout,
                title: "這裡現在是空的",
                message: "拿掉的、排不進去的地方會放在這裡，之後可以排回來。"
            )
        }
    }

    private func seedRow(_ seed: Seed) -> some View {
        HStack(spacing: T.Space.s3) {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                DomyText(seed.n, .body)
                DomyText("\(seed.a)・\(seed.why)", .footnote, tone: .secondary)
            }
            .fillLeading()
            if store.s.trip != nil {
                DomyButton("排回這趟", variant: .secondary, size: .compact) {
                    restore(seed.id)
                }
                .accessibilityIdentifier("seed-restore-\(seed.id)")
            }
        }
        .padding(.vertical, T.Space.s3)
        .frame(minHeight: T.Size.row)
    }

    private func restore(_ seedId: String) {
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            var seeds: [Seed] = d.seeds
            let message: String = restoreSeed(&trip, &seeds, seedId)
            d.trip = trip
            d.seeds = seeds
            return message
        }
    }
}
