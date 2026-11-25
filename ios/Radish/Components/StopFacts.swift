// 核對資料（RadishCore/SeoulFacts.swift）給畫面用的部分：那天開不開、這趟還有幾站沒核對，
// 和一站頁上「開放」「怎麼訂」「來源」三塊。沒有資料的站這三塊不出現（要先訂的站會說還沒查到怎麼訂）。
// SwiftUI 版才有，mobile/ 沒有對應的檔。
import SwiftUI

/* ---------- 那天開不開 ---------- */

/// 這一站那天去不了
struct StopShut: Hashable {
    /// true 是歇業、搬走、長期不開；false 是只有那天休館
    let gone: Bool
    /// 原因，例如「每週二休」
    let why: String
}

/// 那一天裡去不了的一站
struct DayShut: Hashable {
    let it: Stop
    let shut: StopShut
}

/// 那一天已經過了，不用再講開不開
private func dayPassed(_ phase: Phase?, _ day: Int) -> Bool {
    guard let phase else { return false }
    switch phase {
    case .plan: return false
    case .trip(let now): return day < now
    case .done: return true
    }
}

/// 這一站第 day 天去不去得了。去過的、已經過的天、沒有資料的都是 nil
func stopShut(_ trip: Trip, _ it: Stop, _ day: Int, _ phase: Phase?) -> StopShut? {
    if it.status == .pulled || dayPassed(phase, day) { return nil }
    guard let why = closedOnDay(trip, it.id, day) else { return nil }
    let gone: Bool = factOf(it.id)?.gone != nil
    return StopShut(gone: gone, why: why)
}

/// 不在這趟裡的地方沒有日期，只看得出是不是歇業了
func placeShut(_ id: String) -> StopShut? {
    guard let why = factOf(id)?.gone else { return nil }
    return StopShut(gone: true, why: why)
}

/// 這一天去不了的站，照清單的順序
func dayShuts(_ trip: Trip, _ day: Int, _ phase: Phase?) -> [DayShut] {
    var out: [DayShut] = []
    for x in dayStops(trip, day) {
        if let shut = stopShut(trip, x.it, day, phase) {
            out.append(DayShut(it: x.it, shut: shut))
        }
    }
    return out
}

/// 一句話講完：「景福宮這天休館：每週二休。」好幾站就併成一句
func dayShutText(_ list: [DayShut]) -> String {
    if list.count == 1, let one = list.first {
        let lead: String = one.shut.gone ? "「\(one.it.n)」現在去不了：" : "\(one.it.n)這天休館："
        return lead + fullStop(one.shut.why)
    }
    let names: [String] = list.map { (x: DayShut) -> String in "\(x.it.n)（\(x.shut.why)）" }
    return "這天有 \(list.count) 站不開：\(names.joined(separator: "、"))。"
}

/// 句尾補句號。已經有的不重複補
func fullStop(_ text: String) -> String {
    let ends: [String] = ["。", "！", "？"]
    for end in ends {
        if text.hasSuffix(end) { return text }
    }
    return text + "。"
}

/// 這趟那一天的清單上面那一條。一天最多一條，都開就不出現
struct DayShutBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    let trip: Trip
    let day: Int

    /// 按鈕對哪一站：先挑移到別天就好的，都是歇業的才看第一個
    private func target(_ list: [DayShut]) -> DayShut? {
        let movable: DayShut? = list.first { (x: DayShut) -> Bool in !x.shut.gone }
        return movable ?? list.first
    }

    private func actionTitle(_ x: DayShut, _ count: Int) -> String {
        if x.shut.gone { return count == 1 ? "看這一站" : "看\(x.it.n)" }
        return count == 1 ? "移到別的時段" : "先移\(x.it.n)"
    }

    private func act(_ x: DayShut) {
        if x.shut.gone {
            nav.push(.stop(id: x.it.id))
        } else {
            sheets.open(.move(id: x.it.id))
        }
    }

    var body: some View {
        let list: [DayShut] = dayShuts(trip, day, store.phase)
        if let x = target(list) {
            Banner(dayShutText(list), actionTitle: actionTitle(x, list.count)) {
                act(x)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("day-closed")
        }
    }
}

/* ---------- 還有幾站沒核對 ---------- */

/// 這趟有幾站還沒核對：沒有資料的、沒查到的。二手資料算核對過，自己加的不算
func uncheckedCount(_ trip: Trip) -> Int {
    var n: Int = 0
    for x in allItems(trip) {
        if x.it.mine == true { continue }
        let status: FactStatus = factOf(x.it.id)?.status ?? FactStatus.none
        if status == FactStatus.none { n += 1 }
    }
    return n
}

/// 這趟最下面那行小字。都核對過就沒有
func uncheckedLine(_ trip: Trip) -> String? {
    let n: Int = uncheckedCount(trip)
    if n == 0 { return nil }
    return "這趟有 \(n) 站還沒核對，營業時間要自己查。"
}

/// 按天的須知下面那行：這幾站的須知核對到哪裡。都沒有須知就沒有這行
func tipsFooter(_ stops: [Stop]) -> String? {
    var total: Int = 0
    var blank: Int = 0
    var second: Int = 0
    for it in stops {
        guard let tip = tipOf(it) else { continue }
        total += 1
        if tip.status == FactStatus.none { blank += 1 }
        if tip.status == FactStatus.second { second += 1 }
    }
    if total == 0 { return nil }
    if blank == total { return "這幾站的須知都還沒核對過，去之前再查一下。" }
    if blank > 0 { return "有 \(blank) 站的須知還沒核對過，去之前再查一下。" }
    if second > 0 { return "有 \(second) 站的須知是二手資料，去之前再查一下。" }
    return "這幾站的須知都看過官方頁。"
}

/* ---------- 一站頁：開放、怎麼訂、來源 ---------- */

/// 卡片裡的一列：小標和內容
struct FactLine: Identifiable, Hashable {
    let label: String
    let text: String
    var warn: Bool = false
    var muted: Bool = false

    var id: String { return label }
}

/// 有寫才加一列
private func addLine(_ out: inout [FactLine], _ label: String, _ text: String?) {
    guard let text, !text.isEmpty else { return }
    out.append(FactLine(label: label, text: text))
}

/// 「開放」那組有哪幾列，只放有的。票價在上面的花費那列，這裡不再寫一次
func openLines(_ f: PlaceFact?, _ shut: StopShut?) -> [FactLine] {
    var out: [FactLine] = []
    if let shut {
        out.append(FactLine(label: shut.gone ? "現在的狀況" : "這天休館", text: shut.why, warn: true))
        // 歇業了，開放時間沒有意義
        if shut.gone { return out }
    }
    guard let f else { return out }
    addLine(&out, "休館", closedText(f))
    addLine(&out, "開放時間", f.hours)
    let last: String = f.last ?? ""
    addLine(&out, last.contains("末班") ? "末班" : "最後入場", last)
    addLine(&out, "韓文地址", f.addr)
    return out
}

/// 開賣時間那一句，換成台灣時間（Book.swift）。不在這趟裡、不知道哪天去的，講規則
private func openSaleText(_ b: BookInfo, _ visit: String?, _ today: String, _ now: Date) -> String? {
    guard let visit else { return saleRuleText(b) }
    guard let sale = bookOpen(b, visit) else { return nil }
    if let at = sale.at, let minutes = bookMinutes(at), let taiwan = koreaToTaiwan(sale.on, at) {
        if koreaSeconds(sale.on, minutes) <= now.timeIntervalSince1970 { return "已經開賣" }
        return "\(fmtDay(taiwan.on)) \(taiwan.at)（台灣時間）"
    }
    // 沒寫幾點：過了那天才算已經開賣
    if sale.on < today { return "已經開賣" }
    return "\(fmtDay(sale.on))，幾點還不知道"
}

private func saleRuleText(_ b: BookInfo) -> String? {
    let tail: String = b.opensAt.map { (x: String) -> String in "，韓國時間 \(x)" } ?? ""
    if let days = b.opensDays {
        return "去的那天往前 \(days) 天" + tail
    }
    guard let months = b.opensMonths, let day = b.opensDay else { return nil }
    let when: String = months == 0 ? "去的那個月" : "去的那個月往前 \(months) 個月"
    return "\(when)的 \(day) 號" + tail
}

/// 最晚哪天決定那一句
private func decideText(_ b: BookInfo, _ visit: String?, _ today: String) -> String? {
    if let visit {
        guard let on = bookDecide(b, visit) else { return nil }
        let tail: String = on >= today ? "，到這天還能免費取消" : "，免費取消的期限過了"
        return fmtDay(on) + tail
    }
    guard let days = b.decideDays, days >= 0 else { return nil }
    return (days == 0 ? "去的當天" : "去的 \(days) 天前") + "，到那天還能免費取消"
}

/// 「怎麼訂」那組有哪幾列。要先訂但沒查到就照實講
func bookLines(_ book: BookInfo?, _ visit: String?, _ today: String, _ now: Date) -> [FactLine] {
    guard let b = book else {
        return [FactLine(label: "方法", text: "還沒查到怎麼訂，要自己查。", muted: true)]
    }
    var out: [FactLine] = []
    addLine(&out, "方法", b.how)
    addLine(&out, "開賣時間", openSaleText(b, visit, today, now))
    addLine(&out, "外國人訂不訂得到", b.foreigner)
    addLine(&out, "最晚哪天決定", decideText(b, visit, today))
    addLine(&out, "取消規則", b.cancel)
    return out
}

/// 瀏覽器開得了的網址。空的、不是網頁的都是 nil
func webURL(_ text: String?) -> URL? {
    guard let text, let url = URL(string: text) else { return nil }
    let scheme: String = (url.scheme ?? "").lowercased()
    return scheme == "https" || scheme == "http" ? url : nil
}

/// 一站頁核對資料的三塊，這趟裡的站和不在這趟裡的地方共用。visit 是去的那天，不在這趟裡是 nil。
/// 一塊一塊直接放進外面那一欄，間距跟頁面上其他塊一樣；都沒有就不佔位置
struct StopFactBlocks: View {
    let it: Stop
    let shut: StopShut?
    let visit: String?

    private var fact: PlaceFact? {
        return factOf(it.id)
    }

    private var lines: [FactLine] {
        return openLines(fact, shut)
    }

    /// 去過了、歇業了就不用再講怎麼訂
    private var showBook: Bool {
        if it.status == .pulled { return false }
        if let shut, shut.gone { return false }
        return it.b == true || fact?.book != nil
    }

    private var openFooter: String? {
        if let f = fact, f.status == FactStatus.second { return "二手資料，去之前再查一下。" }
        return nil
    }

    var body: some View {
        if !lines.isEmpty {
            DomySection("開放", footer: openFooter) {
                ForEach(lines) { (line: FactLine) in
                    StopInfoRow(label: line.label, text: line.text, warn: line.warn)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stop-open")
        }
        if showBook {
            StopBookSection(book: fact?.book, visit: visit)
        }
        if let f = fact, !f.src.isEmpty {
            StopSourceEntry(fact: f)
        }
    }
}

/// 怎麼訂：只列查到的，最下面打開訂票頁（外開）
private struct StopBookSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let book: BookInfo?
    let visit: String?

    var body: some View {
        let lines: [FactLine] = bookLines(book, visit, store.today, Date())
        let url: URL? = webURL(book?.url)
        DomySection("怎麼訂") {
            ForEach(lines) { (line: FactLine) in
                StopInfoRow(label: line.label, text: line.text, muted: line.muted)
            }
            if let url {
                DomyButton("打開訂票頁", variant: .secondary, size: .compact, fullWidth: true) {
                    openURL(url)
                }
                .padding(.vertical, T.Space.s3)
                .accessibilityHint("會打開瀏覽器")
                .accessibilityIdentifier("stop-book-open")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stop-book")
    }
}

/// 一行「來源」：右邊是核對到哪裡，點了看網站名和網址
private struct StopSourceEntry: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    let fact: PlaceFact
    @State private var showing: Bool = false

    var body: some View {
        DomySection {
            SettingsRow("來源", value: factLabel(fact)) {
                showing = true
            }
            .accessibilityIdentifier("stop-source")
        }
        .sheet(isPresented: $showing) {
            StopSourcePane(fact: fact, onClose: { showing = false })
                .environment(store)
                .environment(sheets)
                .environment(nav)
                .tint(C.accent)
        }
    }
}

/// 來源（半頁）：看了哪些網站，點了外開
private struct StopSourcePane: View {
    let fact: PlaceFact
    let onClose: () -> Void

    private var note: String {
        let label: String = factLabel(fact)
        switch fact.status {
        case FactStatus.official:
            return "\(label)。時間和票價會變，去之前再看一次。"
        case FactStatus.second:
            return "\(label)，不是官方頁寫的，去之前再查一下。"
        case FactStatus.none:
            return "還沒核對，去之前自己查一下。"
        }
    }

    var body: some View {
        SheetScaffold("來源", onClose: onClose) {
            DomyText(note, .subheadline, tone: .secondary)
            DomySection {
                ForEach(Array(fact.src.enumerated()), id: \.offset) { (_: Int, s: FactSource) in
                    StopSourceRow(source: s)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 一個來源：網站名、網址。打不開的網址就只顯示
private struct StopSourceRow: View {
    @Environment(\.openURL) private var openURL
    let source: FactSource

    var body: some View {
        if let url = webURL(source.url) {
            Button {
                openURL(url)
            } label: {
                row
            }
            .buttonStyle(RowPressStyle())
            .padding(.horizontal, -T.Space.s4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(source.name)，打開網頁")
            .accessibilityAddTraits([.isButton, .isLink])
        } else {
            TextRow(source.name, note: source.url)
        }
    }

    private var row: some View {
        HStack(spacing: T.Space.s3) {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                DomyText(source.name, .body)
                DomyText(source.url, .footnote, tone: .secondary, lines: 2)
            }
            .fillLeading()
            Image(systemName: "arrow.up.right")
                .font(T.TypeScale.footnote.font.weight(.semibold))
                .foregroundStyle(C.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, T.Space.s3)
        .frame(minHeight: T.Size.row)
        .padding(.horizontal, T.Space.s4)
        .contentShape(Rectangle())
    }
}
