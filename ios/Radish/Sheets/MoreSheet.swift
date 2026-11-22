// 「更多」：不常用的動作收在這裡，從這趟右上角打開（線框 A7）。
// 這一天：復原上一步、上午和下午對調、自己加一站；這趟：花費、行程設定、傳給旅伴看；「這趟不排了」單獨放最下面。
// 對應 mobile/src/sheets/MoreSheet.tsx。TS 的 onAdd、onSettings 改成 sheets.open(.add)、sheets.open(.settings)。
import SwiftUI

struct MoreSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    @State private var share: ShareItem?
    private let day: Int

    init(day: Int) {
        self.day = day
    }

    var body: some View {
        if let trip = store.s.trip {
            page(trip)
        } else {
            gone
        }
    }

    /// 沒有行程（剛收起來）：TS 是什麼都不顯示。這裡留一張空白的卡，還開著就關掉
    private var gone: some View {
        C.canvas
            .ignoresSafeArea()
            .onAppear {
                if sheets.req == SheetReq.more(day: day) {
                    sheets.close()
                }
            }
    }

    private func page(_ trip: Trip) -> some View {
        SheetScaffold("更多", onClose: { sheets.close() }) {
            daySection(trip)
            tripSection(trip)
            poolSection
            archiveSection
        }
        .sheet(item: $share) { (item: ShareItem) in
            ShareSheet(items: item.items)
        }
    }

    /// 今天還沒去的第一個主要景點（旅途中才有）
    private func bigStop(_ trip: Trip) -> Stop? {
        guard let phase = store.phase else { return nil }
        guard case .trip(let today) = phase else { return nil }
        let stops: [Found] = dayStops(trip, today)
        let hit: Found? = stops.first { (x: Found) -> Bool in
            x.it.status == .kept && x.it.s == .L
        }
        return hit?.it
    }

    private func daySection(_ trip: Trip) -> some View {
        let canSwap: Bool = slotAt(trip, day, .am) != nil && slotAt(trip, day, .pm) != nil
        let big: Stop? = bigStop(trip)
        return DomySection("第 \(day) 天") {
            if store.canUndo {
                SettingsRow("復原上一步") {
                    sheets.close()
                    store.undo()
                }
                .accessibilityIdentifier("more-undo")
            }
            if canSwap {
                SettingsRow("上午和下午對調") {
                    swapHalves()
                }
                .accessibilityIdentifier("more-swap")
            }
            if let big {
                SettingsRow("今天排輕一點", value: "先不去\(big.n)") {
                    lighten(big)
                }
                .accessibilityIdentifier("more-light")
            }
            SettingsRow("自己加一站") {
                sheets.open(.add)
            }
            .accessibilityIdentifier("more-add")
        }
    }

    private func tripSection(_ trip: Trip) -> some View {
        DomySection("這趟") {
            SettingsRow("花費", value: "每人大概花多少（估）") {
                sheets.close()
                nav.push(.cost)
            }
            .accessibilityIdentifier("more-cost")
            SettingsRow("行程設定", value: "日期、住哪、名稱、封面") {
                sheets.open(.settings)
            }
            .accessibilityIdentifier("more-settings")
            SettingsRow("傳給旅伴看") {
                share = ShareItem(items: [shareText(trip)])
            }
            .accessibilityIdentifier("more-share")
        }
    }

    /// 收起來單獨一塊放最下面，不跟常用的擠在一起。可以復原
    private var archiveSection: some View {
        DomySection {
            SettingsRow("這趟不排了，收起來", destructive: true) {
                store.act(undoable: true) { (d: inout AppState) -> String? in
                    archiveTrip(&d)
                }
                sheets.close()
            }
            .accessibilityIdentifier("more-archive")
        }
    }

    @ViewBuilder
    private var poolSection: some View {
        let pool: [String] = store.s.pool
        if !pool.isEmpty {
            DomySection("你加的、順路有空再去") {
                ForEach(Array(pool.enumerated()), id: \.offset) { pair in
                    TextRow(pair.element)
                }
            }
        }
    }

    private func swapHalves() {
        let which: Int = day
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            let err: String? = swapParts(&trip, which, .am, .pm)
            d.trip = trip
            return err ?? "第 \(which) 天上午和下午對調了。"
        }
        sheets.close()
    }

    private func lighten(_ big: Stop) {
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            var seeds: [Seed] = d.seeds
            _ = seedOut(&trip, &seeds, big.id, "那天想排輕一點")
            d.trip = trip
            d.seeds = seeds
            return "今天的主要景點「\(big.n)」先放到下次再來。"
        }
        sheets.close()
    }
}
