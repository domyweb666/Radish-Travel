// 「行前」的第一段，出發前：要先訂的、要辦的事、行李要帶的、不能帶進韓國的。
// 對應 mobile/src/screens/PrepScreen.tsx 的 Before。
import SwiftUI

/// 出發前：要先訂的、要辦的事、行李要帶的、不能帶進韓國的
struct PrepBefore: View {
    @Environment(AppStore.self) private var store

    private var trip: Trip? {
        return store.s.trip
    }

    /// 這趟的第一則提醒。這趟沒有要提醒的就是 nil，不給按鈕
    private var firstReminder: Reminder? {
        guard let trip else { return nil }
        var only: AppState = AppState()
        only.trip = trip
        only.checks = store.s.checks
        return remindersOf(only, store.today, now: Date()).first
    }

    private var books: [BookRow] {
        guard let trip else { return [] }
        return bookPlan(trip, store.s.checks, store.today, now: Date())
    }

    /// 七天內要出發才有值：還有幾天
    private var soonDays: Int? {
        guard let phase = store.phase else { return nil }
        if case .plan(let daysToGo) = phase, daysToGo <= 7 {
            return daysToGo
        }
        return nil
    }

    private var recheckLine: String? {
        guard let trip, let days = soonDays else { return nil }
        return recheckText(trip, days)
    }

    private var allFacts: [Fact] {
        let start: String? = trip?.start
        let list: [Fact] = CHECKLIST.map { (r: CheckItem) -> Fact in prepFact(r, start) }
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
        if let line = recheckLine {
            Banner(line)
        }
    }

    @ViewBuilder private var booksSection: some View {
        let list: [BookRow] = books
        if !list.isEmpty {
            DomySection("這趟要先訂的", footer: bookFooter(list)) {
                ForEach(list, id: \.id) { (r: BookRow) in
                    CheckRow(checked: r.checked, title: r.stop.n, note: bookNote(r, store.today)) {
                        toggle("b_" + r.stop.id)
                    }
                    .accessibilityIdentifier("check-b_\(r.stop.id)")
                    bookLink(r)
                }
            }
        }
    }

    /// 那一站下面的一列：外國人訂不訂得到、打開訂票頁。打勾了、去過了就不用再列
    @ViewBuilder private func bookLink(_ r: BookRow) -> some View {
        if !r.checked && r.stop.status == StopStatus.kept {
            if let link = r.url, let host = bookHost(link) {
                DomyListRow(
                    meta: prepNote(r.foreigner), title: "打開訂票頁　\(host)", label: bookSpoken(r, host)
                ) {
                    openWeb(link)
                }
                .accessibilityHint("會打開瀏覽器")
                .accessibilityIdentifier("book-open-\(r.stop.id)")
            } else if let text = prepNote(r.foreigner) {
                TextRow("外國人訂不訂得到", note: text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(r.stop.n)，外國人訂不訂得到：\(text)")
            }
        }
    }

    /// 開訂票網頁那一列念的：先念站名，免得好幾列聽起來一樣
    private func bookSpoken(_ r: BookRow, _ host: String) -> String {
        let head: String = "\(r.stop.n)，打開訂票頁，\(host)"
        guard let text = prepNote(r.foreigner) else { return head }
        return head + "，外國人訂不訂得到：" + text
    }

    @ViewBuilder private var remindSection: some View {
        if let first = firstReminder {
            let when: String = remindWhen(first)
            VStack(alignment: .leading, spacing: T.Space.s2) {
                if store.s.remind {
                    remindOnRows(when)
                } else {
                    DomyButton("提醒我去訂", variant: .secondary, fullWidth: true) {
                        askRemind(when)
                    }
                    .accessibilityIdentifier("prep-remind")
                    DomyText("第一則是 \(when)。", .footnote, tone: .secondary)
                }
            }
        }
    }

    @ViewBuilder private func remindOnRows(_ when: String) -> some View {
        DomyText("會提醒你去訂，這趟的第一則是 \(when)。打勾的不提醒。", .footnote, tone: .secondary)
        DomyButton("不用提醒了", variant: .plain, fullWidth: true) {
            store.mutate { (d: inout AppState) -> Void in
                d.remind = false
            }
        }
        .accessibilityIdentifier("prep-remind-off")
    }

    /// 按了才問通知權限
    private func askRemind(_ when: String) {
        Task { @MainActor in
            let r: AskResult = await askReminders()
            if r == .granted {
                store.act { (d: inout AppState) -> String? in
                    d.remind = true
                    return "好，第一則是 \(when)。"
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
                checkItem(r)
            }
        }
    }

    /// 一條檢查表。過了公告期限、要再查一次的用警告色，看得出比別條急
    private func checkItem(_ r: CheckItem) -> some View {
        let start: String? = trip?.start
        let fact: Fact = prepFact(r, start)
        let late: Bool = datedLate(r.id, start)
        return CheckRow(
            checked: isChecked(r.id), title: fact.text, note: prepNote(prepFactShort(fact)), warn: late
        ) {
            toggle(r.id)
        }
        .accessibilityIdentifier("check-\(r.id)")
    }
}
