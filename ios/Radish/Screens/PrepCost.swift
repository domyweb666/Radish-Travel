// 「行前」的第四段，花費：每人粗估、機票自己填、韓元換算、一筆一筆記實際花的。
// 對應 mobile/src/screens/PrepScreen.tsx 的 Cost 和 Spent。
import SwiftUI

/// TS 的 String(number)：整數不帶小數點
private func plainNumber(_ n: Double) -> String {
    if n == n.rounded() && abs(n) < 1.0e15 {
        return String(Int(n))
    }
    return String(n)
}

/// TS 輸入框的 maxLength：超過就切掉。回 nil 是沒超過
private func overLimit(_ text: String, _ limit: Int) -> String? {
    return text.count > limit ? String(text.prefix(limit)) : nil
}

struct PrepCost: View {
    @Environment(AppStore.self) private var store
    /// 機票那一格正在打的字。打完才存一次，打的時候粗估先照打的算
    @State private var flight: String = ""
    /// 上次存的或放進框裡的字。跟框裡一樣就是沒改。nil 是還沒放進去
    @State private var flightBase: String? = nil

    // 出發之後常用的是記帳，放最上面；出發前先看粗估
    private var gone: Bool {
        guard let phase = store.phase else { return false }
        if case .plan = phase { return false }
        return true
    }

    var body: some View {
        if let saved = store.s.trip {
            let trip: Trip = shown(saved)
            VStack(alignment: .leading, spacing: T.Space.s6) {
                if gone {
                    PrepSpent()
                }
                estimateCard(trip)
                rowsSection(trip)
                flightField
                if !gone {
                    PrepSpent()
                }
            }
        }
    }

    /// 畫面上用的那一份：機票正在打、還沒存的，先照打的算
    private func shown(_ saved: Trip) -> Trip {
        guard let base = flightBase, flight != base else { return saved }
        var out: Trip = saved
        out.flight = parseFlight(flight)
        return out
    }

    private func estimateCard(_ trip: Trip) -> some View {
        let label: String = "每人粗估" + (trip.flight != 0 ? "" : "（不含機票）")
        return Card {
            DomyText(label, .footnote, tone: .secondary)
            DomyText(costRange(trip, store.s.settings), .title1, numeric: true)
        }
    }

    private func rowsSection(_ trip: Trip) -> some View {
        let c: (rows: [CostRow], total: Double, people: Int) = cost(trip, store.s.settings)
        let rows: [CostRow] = c.rows
        return DomySection(footer: "都是粗估，沒有核對過票價和匯率，只能看比例。購物不算在裡面。住宿和一天吃喝的預算在「平常的我」改。") {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                TextRow(r.name, note: prepNote(r.note)) {
                    DomyText(money(r.amount), .headline, numeric: true)
                }
            }
        }
    }

    private var flightField: some View {
        DomyTextField(
            "機票（每人，NT$）", text: $flight, placeholder: "例如 12000",
            helper: "自己填，會加進上面的粗估。", keyboard: .numberPad
        )
        .accessibilityIdentifier("spend-flight")
        .onAppear { fillFlight() }
        .onChange(of: flight) { (_: String, text: String) in
            if let cut = overLimit(text, 6) {
                flight = cut
            }
        }
        // 按了復原，框裡的字跟著變回去
        .onChange(of: store.s.trip?.flight ?? 0) { (_: Double, now: Double) in
            if parseFlight(flight) != now { fillFlight() }
        }
        .onFieldDone { saveFlight() }
    }

    /// 把存著的機票放進框裡
    private func fillFlight() {
        let n: Double = store.s.trip?.flight ?? 0
        let text: String = n != 0 ? plainNumber(n) : ""
        flight = text
        flightBase = text
    }

    /// 打完了存一次，可以復原。沒有變就不留一步
    private func saveFlight() {
        guard let base = flightBase, flight != base else { return }
        guard let trip = store.s.trip else { return }
        let n: Double = parseFlight(flight)
        let text: String = n != 0 ? plainNumber(n) : ""
        flight = text
        flightBase = text
        if trip.flight == n { return }
        store.act(undoable: true) { (d: inout AppState) -> String? in
            d.trip?.flight = n
            return n != 0 ? "機票改成每人 \(money(n))。" : "機票清掉了。"
        }
    }
}

/// 機票那一格的字變成數字，最多 20 萬
private func parseFlight(_ text: String) -> Double {
    let digits: String = text.filter { (ch: Character) -> Bool in ch.isASCII && ch.isNumber }
    let typed: Double = Double(Int(digits) ?? 0)
    return min(200000, max(0, typed))
}

/// 對照表列的幾個金額（韓元），看一眼就知道大概多少台幣
private let QUICK_KRW: [Double] = [1000, 5000, 10000, 50000]  // domy-ignore: 是韓元金額，不是版面數值

/// 換算＋實際花的：一筆一筆記韓元，用自己填的匯率換台幣。跟上面的粗估分開，不混在一起算
struct PrepSpent: View {
    @Environment(AppStore.self) private var store
    // 記完一筆要把兩格清空
    @State private var krw: String = ""
    @State private var note: String = ""
    /// 匯率那一格正在打的字。打完才存一次，打的時候換算先照打的算
    @State private var rate: String = ""
    /// 上次存的或放進框裡的字。跟框裡一樣就是沒改。nil 是還沒放進去
    @State private var rateBase: String? = nil

    private var tripDay: Int? {
        guard let phase = store.phase else { return nil }
        if case .trip(let day) = phase { return day }
        return nil
    }

    private func twdOf(_ n: Double, _ trip: Trip) -> String? {
        guard let t = toTwd(n, trip.rate) else { return nil }
        return "約 \(money(t))"
    }

    var body: some View {
        if let saved = store.s.trip {
            let trip: Trip = shown(saved)
            // 最上面那一格同時是換算器：邊打邊換。真的花了再按「記一筆」
            VStack(alignment: .leading, spacing: T.Space.s6) {
                krwField(trip)
                convertedCard(trip)
                noteField
                addButton
                rateField
                quickTable(trip)
                records(trip)
            }
        }
    }

    /// 畫面上用的那一份：匯率正在打、還沒存的，先照打的算
    private func shown(_ saved: Trip) -> Trip {
        guard let base = rateBase, rate != base else { return saved }
        var out: Trip = saved
        out.rate = parseRate(rate)
        return out
    }

    private func krwHelper(_ trip: Trip) -> String? {
        let typed: Double = parseKrw(krw)
        if typed == 0 { return "打金額就換算成台幣。真的花了再按「記一筆」。" }
        return twdOf(typed, trip) == nil ? "在下面填匯率，這裡就會換成台幣。" : nil
    }

    private func krwField(_ trip: Trip) -> some View {
        DomyTextField(
            "多少韓元", text: $krw, placeholder: "例如 12000",
            helper: krwHelper(trip), keyboard: .numberPad
        )
        .accessibilityIdentifier("spend-krw")
        .onChange(of: krw) { _, text in
            if let cut = overLimit(text, 9) {
                krw = cut
            }
        }
    }

    @ViewBuilder private func convertedCard(_ trip: Trip) -> some View {
        let typed: Double = parseKrw(krw)
        if typed != 0, let twd = twdOf(typed, trip) {
            Card {
                DomyText(twd, .title1)
                DomyText("\(krwText(typed))，照你填的匯率算", .footnote, tone: .secondary)
            }
        }
    }

    private var noteField: some View {
        DomyTextField("花在哪（可以不填）", text: $note, placeholder: "例如：廣藏市場綠豆煎餅")
            .accessibilityIdentifier("spend-note")
            .onChange(of: note) { _, text in
                if let cut = overLimit(text, 30) {
                    note = cut
                }
            }
    }

    private var addButton: some View {
        DomyButton("記一筆", disabled: parseKrw(krw) == 0, fullWidth: true) {
            addOne()
        }
        .accessibilityIdentifier("spend-add")
    }

    private func addOne() {
        Haptic.notify(.success)
        let amount: Double = parseKrw(krw)
        let memo: String = note
        let day: Int? = tripDay
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let x = addSpend(&trip, amount, memo, day) else { return nil }
            d.trip = trip
            return "記了 \(krwText(x.krw))。"
        }
        krw = ""
        note = ""
    }

    private var rateField: some View {
        DomyTextField(
            "1000 韓元換多少台幣", text: $rate, placeholder: "例如 23",
            helper: "自己填，照你實際換到的匯率。這個 app 不會去抓匯率。", keyboard: .decimalPad
        )
        .accessibilityIdentifier("spend-rate")
        .onAppear { fillRate() }
        .onChange(of: rate) { (_: String, text: String) in
            if let cut = overLimit(text, 6) {
                rate = cut
            }
        }
        // 按了復原，框裡的字跟著變回去
        .onChange(of: store.s.trip?.rate ?? 0) { (_: Double, now: Double) in
            let shownNow: Double = parseRate(rate) ?? 0
            if shownNow != now { fillRate() }
        }
        .onFieldDone { saveRate() }
    }

    /// 把存著的匯率放進框裡
    private func fillRate() {
        let r: Double = store.s.trip?.rate ?? 0
        let text: String = r != 0 ? plainNumber(r) : ""
        rate = text
        rateBase = text
    }

    /// 打完了存一次，可以復原。沒有變就不留一步
    private func saveRate() {
        guard let base = rateBase, rate != base else { return }
        guard let trip = store.s.trip else { return }
        let text: String = rate
        rateBase = text
        let r: Double? = parseRate(text)
        if trip.rate == r { return }
        store.act(undoable: true) { (d: inout AppState) -> String? in
            d.trip?.rate = r
            if let r { return "匯率改成 1000 韓元換 NT$ \(plainNumber(r))。" }
            return text.isEmpty ? "匯率清掉了。" : "這個匯率看不懂，先當成沒填。"
        }
    }

    @ViewBuilder private func quickTable(_ trip: Trip) -> some View {
        if let r = trip.rate, r != 0 {
            DomySection("對照表", footer: "照你填的匯率算，四捨五入到元。") {
                ForEach(QUICK_KRW, id: \.self) { (n: Double) in
                    TextRow(krwText(n)) {
                        DomyText(twdOf(n, trip) ?? "", .headline)
                    }
                }
            }
        }
    }

    private func recordsFooter(_ trip: Trip, _ list: [Spend]) -> String {
        if list.isEmpty { return "在當地花了錢就記一筆，存在手機裡，沒網路也能記。" }
        let sum: (count: Int, krw: Double, twd: Double?) = spendTotal(trip)
        let head: String = "\(sum.count) 筆，一共 \(krwText(sum.krw))"
        let mid: String =
            sum.twd == nil
            ? "。填了上面的匯率才會換成台幣"
            : "，\(twdOf(sum.krw, trip) ?? "")（照你填的匯率算）"
        return head + mid + "。點一筆可以刪掉，刪錯了按「復原」。"
    }

    private func records(_ trip: Trip) -> some View {
        let list: [Spend] = trip.spend ?? []
        return DomySection("實際花的", footer: recordsFooter(trip, list)) {
            if list.isEmpty {
                TextRow("還沒有記")
            } else {
                ForEach(list, id: \.id) { (x: Spend) in
                    PrepSpendRow(x: x, twd: twdOf(x.krw, trip)) {
                        removeOne(x.id)
                    }
                }
            }
        }
    }

    private func removeOne(_ id: String) {
        Haptic.impact(.light)
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let gone = removeSpend(&trip, id) else { return nil }
            d.trip = trip
            return "刪掉「\(gone.note ?? krwText(gone.krw))」這一筆了。"
        }
    }
}

/// 實際花的一筆：點一下刪掉
private struct PrepSpendRow: View {
    let x: Spend
    let twd: String?
    let onDelete: () -> Void

    private var title: String {
        return x.note ?? "沒寫花在哪"
    }

    private var dayNote: String? {
        guard let day = x.day, day != 0 else { return nil }
        return "第 \(day) 天"
    }

    var body: some View {
        Button(action: onDelete) {
            TextRow(title, note: dayNote) {
                VStack(alignment: .trailing, spacing: 0) {
                    DomyText(krwText(x.krw), .headline)
                    if let twd {
                        DomyText(twd, .footnote, tone: .secondary)
                    }
                }
            }
            .padding(.horizontal, T.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, -T.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(krwText(x.krw))，點一下刪掉")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("spend-row-\(x.id)")
    }
}
