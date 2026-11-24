// 自己加一站。只問一件事：一定要去，還是順路有空再去。
// 對應 mobile/src/sheets/AddSheet.tsx。
import SwiftUI

struct AddSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    @State private var name: String = ""
    @State private var error: String?

    /// 名稱最多幾個字（TS 的 maxLength）
    private static let maxName: Int = 30

    init() {}

    private var n: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SheetScaffold("自己加一站", onClose: { sheets.close() }) {
            DomyTextField(
                "想去哪",
                text: $name,
                placeholder: "店名或地方",
                helper: "這一版還不會幫你查它在哪，加進來之後地圖上不會有它。",
                error: error
            )
            .accessibilityIdentifier("add-name")
            .onChange(of: name) { _, next in
                if next.count > AddSheet.maxName {
                    name = String(next.prefix(AddSheet.maxName))
                }
                error = nil
            }
            DomyButton("一定要去，幫我排進去", fullWidth: true) {
                addToTrip()
            }
            .accessibilityIdentifier("add-go")
            DomyButton("順路有空再去", variant: .secondary, fullWidth: true) {
                addToPool()
            }
            .accessibilityIdentifier("add-later")
        }
    }

    private func need() -> Bool {
        if !n.isEmpty { return true }
        error = "先打店名或地方的名字。"
        return false
    }

    /// 旅途中的現在；出發前、回來後是 nil
    private var now: TripNow? {
        guard let phase = store.phase else { return nil }
        return tripNow(chatClock(phase))
    }

    /// 從「更多」的第幾天進來的。跟這趟分頁現在看的那一天是同一天（TripScreen 的 shownDay）
    private func shownDay(_ trip: Trip) -> Int {
        let today: Int? = now?.day
        let day: Int = nav.tripDay ?? today ?? 1
        return max(1, min(day, trip.days))
    }

    private func addToTrip() {
        guard need() else { return }
        let place: String = n
        let clock: TripNow? = now
        let day: Int? = store.s.trip.map { (t: Trip) -> Int in shownDay(t) }
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            var seeds: [Seed] = d.seeds
            let message: String = addOwn(&trip, &seeds, place, day, clock)
            d.trip = trip
            d.seeds = seeds
            return message
        }
        sheets.close()
    }

    private func addToPool() {
        guard need() else { return }
        let place: String = n
        store.act(undoable: true) { (d: inout AppState) -> String? in
            d.pool.append(place)
            return "「\(place)」放進順路可去，不排時間。"
        }
        sheets.close()
    }
}
