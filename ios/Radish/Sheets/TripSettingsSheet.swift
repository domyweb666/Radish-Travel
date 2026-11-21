// 行程設定：排好之後回來改這趟的基本資料。
// 只改名稱、封面、出發日、人數、住宿名稱，行程原樣留著。
// 改天數、到離時間、住哪一帶、這趟有什麼不一樣要整趟重排；已經有去過的站時不讓重排，免得去過的紀錄被排掉。
// 對應 mobile/src/sheets/TripSettingsSheet.tsx。
import SwiftUI

/// TS 的 [...tweaks].sort().join()：排好再比，順序不一樣不算改過
private func sortedTweakKeys(_ list: [Tweak]) -> [String] {
    let keys: [String] = list.map { (k: Tweak) -> String in k.rawValue }
    return keys.sorted()
}

struct TripSettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    /// 正在改的草稿。還沒動過是 nil，這時顯示的是這趟現在的樣子
    @State private var draft: TripFormValue?

    init() {}

    private func formNow(_ trip: Trip) -> TripFormValue {
        return draft ?? formOf(trip)
    }

    /// 改到這幾樣要整趟重排
    private func regenOf(_ form: TripFormValue, _ trip: Trip) -> Bool {
        if form.days != trip.days { return true }
        if form.arrive != trip.arrive { return true }
        if form.leave != trip.leave { return true }
        if form.base != trip.base { return true }
        return sortedTweakKeys(form.tweaks) != sortedTweakKeys(trip.tweaks ?? [])
    }

    /// 這趟有沒有已經去過的站
    private func hasVisited(_ trip: Trip) -> Bool {
        return allItems(trip).contains { (x: Found) -> Bool in x.it.status == .pulled }
    }

    private func save(_ form: TripFormValue, _ regen: Bool) {
        guard let start = form.start, !start.isEmpty,
            let days = form.days, days != 0,
            let arrive = form.arrive,
            let leave = form.leave,
            let people = form.people, people != 0
        else { return }
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            if regen {
                var next: TripDraft = draftOf(trip)
                next.tweaks = form.cleanTweaks
                next.start = start
                next.days = days
                next.arrive = arrive
                next.leave = leave
                next.people = people
                next.base = form.base
                next.stayName = form.cleanStayName
                next.name = form.cleanName
                next.cover = form.cover
                var made: Trip = generate(next, d.settings)
                // 重排不該弄丟的：機票、花費紀錄、匯率
                let own: (flight: Double, spend: [Spend]?, rate: Double?) = ownOf(trip)
                made.flight = own.flight
                made.spend = own.spend
                made.rate = own.rate
                d.trip = made
                d.settingsDirty = false
                return "行程設定改了，整趟重排了。手動改過的地方也一起重排了。"
            }
            trip.tweaks = form.cleanTweaks
            trip.start = start
            trip.days = days
            trip.arrive = arrive
            trip.leave = leave
            trip.people = people
            trip.base = form.base
            trip.stayName = form.cleanStayName
            trip.name = form.cleanName
            trip.cover = form.cover
            d.trip = trip
            return "行程設定改好了。"
        }
        sheets.close()
    }

    var body: some View {
        if let trip = store.s.trip {
            content(trip)
        }
    }

    private func content(_ trip: Trip) -> some View {
        let form: TripFormValue = formNow(trip)
        let missing: [String] = missingOf(form)
        let regen: Bool = regenOf(form, trip)
        let blocked: Bool = regen && hasVisited(trip)
        let binding: Binding<TripFormValue> = Binding<TripFormValue>(
            get: { draft ?? formOf(trip) },
            set: { (v: TripFormValue) in draft = v }
        )
        let minStart: String = trip.start < store.today ? trip.start : store.today
        return SheetScaffold("行程設定", onClose: { sheets.close() }) {
            TripForm(value: binding, minStart: minStart, fallbackBase: store.s.settings.base)
            notice(regen, blocked)
            if !missing.isEmpty {
                DomyText("還沒填：\(missing.joined(separator: "、"))", .footnote, tone: .secondary)
            }
            DomyButton(
                regen && !blocked ? "存起來，整趟重排" : "存起來",
                disabled: !missing.isEmpty || blocked,
                fullWidth: true
            ) {
                save(form, regen)
            }
            .accessibilityIdentifier("settings-save")
        }
    }

    @ViewBuilder
    private func notice(_ regen: Bool, _ blocked: Bool) -> some View {
        if blocked {
            Banner("這趟已經有去過的站。天數、到離時間、住哪一帶、這趟有什麼不一樣現在不能改，改了會整趟重排，去過的紀錄會不見。其他欄位可以改。")
                .accessibilityIdentifier("settings-blocked")
        } else if regen {
            Banner("你改了天數、到離時間、住哪一帶，或這趟有什麼不一樣。存了會整趟重排，手動改過的地方也會重排。存完可以復原。")
                .accessibilityIdentifier("settings-regen")
        }
    }
}
