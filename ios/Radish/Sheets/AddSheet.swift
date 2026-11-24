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
            .onChange(of: store.s.trip?.id) { (_: String?, _: String?) in
                tripChanged()
            }
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
                addLater()
            }
            .accessibilityIdentifier("add-later")
        }
    }

    private func need() -> Bool {
        if !n.isEmpty { return true }
        error = "先打店名或地方的名字。"
        return false
    }

    /// 半頁開著的時候按復原換了一趟：打的字留著，先講清楚會排進哪一趟
    private func tripChanged() {
        if let trip = store.s.trip {
            error = "現在換成「\(tripTitle(trip))」這趟了，按下去會加進這一趟。"
        } else {
            error = "現在沒有這趟，還不能加。"
        }
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
        if store.s.trip == nil {
            tripChanged()
            return
        }
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

    /// 放進這趟的順路清單。已經有同一個名字就不重複加，半頁留著、講清楚
    private func addLater() {
        guard need() else { return }
        guard let trip = store.s.trip else {
            tripChanged()
            return
        }
        let place: String = n
        if poolHas(trip, place) {
            error = "「\(place)」已經在這趟的順路清單裡，沒有再加一次。"
            return
        }
        store.act(undoable: true) { (d: inout AppState) -> String? in
            return addToPool(&d, place)
        }
        sheets.close()
    }
}
