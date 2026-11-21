// 「行前」的第一段，出發前：要先訂的、要辦的事、行李要帶的、不能帶進韓國的。
// 對應 mobile/src/screens/PrepScreen.tsx 的 Before。
import SwiftUI

/// 出發前：要先訂的、要辦的事、行李要帶的、不能帶進韓國的
struct PrepBefore: View {
    @Environment(AppStore.self) private var store

    private var trip: Trip? {
        return store.s.trip
    }

    // 提醒：還有沒訂的、而且還來得及提醒，才給這顆按鈕
    private var left: Int {
        guard let trip else { return 0 }
        return unbookedOf(trip, store.s.checks).count
    }

    private var remindDay: String? {
        guard let trip else { return nil }
        return remindOn(trip.start, store.today)
    }

    private var books: [Found] {
        guard let trip else { return [] }
        return allItems(trip).filter { (x: Found) -> Bool in x.it.b == true }
    }

    /// 七天內要出發才有值：還有幾天
    private var soonDays: Int? {
        guard let phase = store.phase else { return nil }
        if case .plan(let daysToGo) = phase, daysToGo <= 7 {
            return daysToGo
        }
        return nil
    }

    private var recheck: [Found] {
        guard let trip else { return [] }
        return allItems(trip).filter { (x: Found) -> Bool in
            if x.it.b == true { return true }
            let tip: String = x.it.tip ?? ""
            return tip.contains("休館") || tip.contains("班次") || tip.contains("名額")
        }
    }

    private var allFacts: [Fact] {
        let list: [Fact] = CHECKLIST.map { (r: CheckItem) -> Fact in prepFact(r) }
        return list + NO_BRING
    }

    private func isChecked(_ k: String) -> Bool {
        return store.s.checks[k] == true
    }

    private func toggle(_ k: String) {
        store.mutate { (d: inout AppState) -> Void in
            let now: Bool = d.checks[k] ?? false
            d.checks[k] = !now
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s6) {
            recheckBanner
            booksSection
            remindSection
            checklist("要辦的事", .todo)
            checklist("行李要帶的", .pack)
            PrepFactList(title: "不能帶進韓國的", facts: NO_BRING, footer: "規定會改。出發前到韓國檢疫機關的官方頁再看一次。")
            PrepSourcesButton(title: "出發前這一段的來源", facts: allFacts)
        }
    }

    @ViewBuilder private var recheckBanner: some View {
        let list: [Found] = recheck
        if let days = soonDays, !list.isEmpty {
            let names: [String] = list.map { (x: Found) -> String in x.it.n }
            Banner("還有 \(days) 天出發。這 \(list.count) 站有訂位、休館日或班次，再查一次：\(names.joined(separator: "、"))。")
        }
    }

    @ViewBuilder private var booksSection: some View {
        let list: [Found] = books
        if let trip, !list.isEmpty {
            DomySection("這趟要先訂的", footer: "訂好了就打勾。怎麼訂、外國人訂不訂得到，這一版還不知道，要自己查。") {
                ForEach(list, id: \.it.id) { (x: Found) in
                    CheckRow(checked: isChecked("b_" + x.it.id), title: x.it.n, note: bookNote(trip, x.s)) {
                        toggle("b_" + x.it.id)
                    }
                    .accessibilityIdentifier("check-b_\(x.it.id)")
                }
            }
        }
    }

    private func bookNote(_ trip: Trip, _ sl: Slot) -> String {
        let date: String = fmtDay(addDays(trip.start, sl.day - 1))
        return "第 \(sl.day) 天 \(date) \(PART[need: sl.part])"
    }

    @ViewBuilder private var remindSection: some View {
        if let on = remindDay, left > 0 {
            if store.s.remind {
                DomyText("\(fmtDay(on))早上 9 點會通知你還有哪幾站沒訂。在那之前全部勾完就不通知。", .footnote, tone: .secondary)
                DomyButton("不用提醒了", variant: .plain, fullWidth: true) {
                    store.mutate { (d: inout AppState) -> Void in
                        d.remind = false
                    }
                }
                .accessibilityIdentifier("prep-remind-off")
            } else {
                DomyButton("\(fmtDay(on))提醒我還沒訂的", variant: .secondary, fullWidth: true) {
                    askRemind(on)
                }
                .accessibilityIdentifier("prep-remind")
            }
        }
    }

    /// 按了才問通知權限
    private func askRemind(_ on: String) {
        Task { @MainActor in
            let r: AskResult = await askReminders()
            if r == .granted {
                store.act { (d: inout AppState) -> String? in
                    d.remind = true
                    return "好，\(fmtDay(on))早上 9 點提醒你。"
                }
            } else {
                store.say("通知沒有開。到 iPhone 的「設定」打開蘿蔔旅行的通知，再回來按一次。")
            }
        }
    }

    @ViewBuilder private func checklist(_ title: String, _ group: CheckGroup) -> some View {
        let rows: [CheckItem] = CHECKLIST.filter { (r: CheckItem) -> Bool in r.group == group }
        let done: Int = rows.filter { (r: CheckItem) -> Bool in isChecked(r.id) }.count
        DomySection("\(title)　\(done)／\(rows.count)") {
            ForEach(rows, id: \.id) { (r: CheckItem) in
                CheckRow(checked: isChecked(r.id), title: r.text, note: prepNote(prepFactShort(prepFact(r)))) {
                    toggle(r.id)
                }
                .accessibilityIdentifier("check-\(r.id)")
            }
        }
    }
}
