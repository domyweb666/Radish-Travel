// 「旅行」分頁：每一趟是一個資料夾。
// 上面是現在打開的這一趟，接著是其他排好還沒去的、已經去過的；可以同時排好幾趟，點一下就切過去。
// 「下次再來」是這幾趟拿掉、排不進去的地方。
// 對應 mobile/src/screens/TripsScreen.tsx。
import SwiftUI

private enum TripsTab: Hashable {
    case trips, later
}

/// 一趟一列：有封面照就放在右邊
private struct TripRow: View {
    let title: String
    let meta: String
    let cover: String?
    let testId: String
    let action: () -> Void

    private var row: some View {
        HStack(spacing: T.Space.s3) {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                DomyText(meta, .footnote, tone: .secondary)
                DomyText(title, .headline, lines: 2)
            }
            .fillLeading()
            if let cover {
                TripCover(ref: cover)
            }
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

/// 封面照：橫的一小張。檔案讀不到時顯示灰底，不讓版面跳掉
private struct TripCover: View {
    let ref: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
        PhotoImage(ref: ref, edge: max(T.Size.heroButton, T.Size.row))
            .frame(width: T.Size.heroButton, height: T.Size.row)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

struct TripsScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @State private var tab: TripsTab = .trips
    private let goTrip: () -> Void

    init(goTrip: @escaping () -> Void) {
        self.goTrip = goTrip
    }

    private var curPulled: Int {
        guard let cur = store.s.trip else { return 0 }
        let pulled: [Found] = allItems(cur).filter { (x: Found) -> Bool in x.it.status == .pulled }
        return pulled.count
    }

    private func range(_ start: String, _ days: Int) -> String {
        return "\(fmtDay(start))–\(fmtDay(addDays(start, days - 1)))"
    }

    private func when(_ t: Trip, _ debugDay: Int?) -> String {
        let p: Phase = phaseOf(t.start, t.days, store.today, debugDay)
        switch p {
        case .plan(let daysToGo):
            return "還有 \(daysToGo) 天出發"
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
        Screen("旅行") {
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
            if !store.s.shelf.isEmpty {
                shelfSection
            }
            newTripButton
            if !store.s.baskets.isEmpty {
                basketsSection
            }
        }
    }

    private var currentFooter: String? {
        if let phase = store.phase, case .plan = phase { return nil }
        return "旅途中去過的站會收在這一趟裡，可以寫一句、加照片。"
    }

    private func currentSection(_ cur: Trip) -> some View {
        let pulled: Int = curPulled
        return DomySection("現在這趟", footer: currentFooter) {
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
                    sheets.open(.album(.current))
                }
                .accessibilityIdentifier("trips-album-current")
            }
        }
    }

    private var shelfSection: some View {
        DomySection("其他排好的", footer: "點一下切到那一趟。現在這趟會原樣留著，不會不見。") {
            ForEach(store.s.shelf, id: \.id) { (x: Shelved) in
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

    @ViewBuilder private var newTripButton: some View {
        let hasCur: Bool = store.s.trip != nil
        DomyButton("開新的一趟", variant: hasCur ? .secondary : .primary, fullWidth: true) {
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
        DomySection("去過的旅行") {
            ForEach(store.s.baskets, id: \.id) { (b: Basket) in
                TripRow(
                    title: b.title,
                    meta: basketMeta(b),
                    cover: b.cover,
                    testId: "basket-card-\(b.id)"
                ) {
                    sheets.open(.album(.basket(id: b.id)))
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
