// 核對資料（RadishCore/SeoulFacts.swift）給畫面用的部分：那天開不開、這趟還有幾站沒核對，
// 和一站頁上「開放」「怎麼訂」「來源」三塊。沒有資料的站這三塊不出現。
// SwiftUI 版才有，mobile/ 沒有對應的檔。
import SwiftUI

/* ---------- 不開和價錢怎麼講 ---------- */

/// 不開、價錢、最後時間這幾個字
struct KindWords: Hashable {
    /// 固定哪天休的小標
    let off: String
    /// 接在「這天」「今天」後面
    let shut: String
    let price: String
    let last: String
}

/// 照這一站是哪一種：看的地方才講休館，吃的和咖啡不講票價、入場。跟 RadishCore 的 closedWord 同一套
func kindWords(_ c: Cat) -> KindWords {
    let hall: Bool = closedWord(c) == "休館"
    let food: Bool = c == .eat || c == .cafe
    return KindWords(
        off: hall ? "休館" : "公休", shut: hall ? "休館" : "不開",
        price: food ? "價錢" : "票價", last: food ? "最後點餐" : "最後入場")
}

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

/// 這一站排的時段不開，短短一句：「上午：還沒開，16:00 才開」。那天整天不開的只講那天不開，這裡是 nil
func stopPartShut(_ trip: Trip, _ it: Stop, _ slot: Slot, _ phase: Phase?) -> String? {
    if it.status == .pulled || dayPassed(phase, slot.day) { return nil }
    return tripPartShut(trip, it.id, slot.day, slot.part)
}

/// 排在第 day 天的這個時段，開不開。移站的時候也用
func tripPartShut(_ trip: Trip, _ id: String, _ day: Int, _ part: Part) -> String? {
    if trip.start.isEmpty || closedOnDay(trip, id, day) != nil { return nil }
    guard let why = partClosedWhy(id, addDays(trip.start, day - 1), part) else { return nil }
    return "\(PART[need: part])：\(why)"
}

/// 那天有要注意的，但不算不開（例如展望台限制使用）。整天不開的就不用再講
func stopCaution(_ trip: Trip, _ it: Stop, _ day: Int, _ phase: Phase?) -> String? {
    if it.status == .pulled || dayPassed(phase, day) || trip.start.isEmpty { return nil }
    if closedOnDay(trip, it.id, day) != nil { return nil }
    return cautionWhy(it.id, addDays(trip.start, day - 1))
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

/// 旅途中看今天，上面有下一站卡：那一站不開、要注意的都寫在卡上，下面的清單不再講一次。沒有是 nil
func toldOnNext(_ trip: Trip, _ day: Int, _ phase: Phase?) -> String? {
    guard case .trip(let now)? = phase, now == day else { return nil }
    let next: Found? = dayStops(trip, day).first { (x: Found) -> Bool in x.it.status == .kept }
    return next?.it.id
}

/// 一句話講完：「景福宮這天休館：每週二休。」好幾站就併成一句。more 是別的地方已經先講了一站
func dayShutText(_ list: [DayShut], more: Bool = false) -> String {
    if list.count == 1, let one = list.first {
        let words: KindWords = kindWords(one.it.c)
        let lead: String = one.shut.gone ? "「\(one.it.n)」現在去不了：" : "\(one.it.n)這天\(words.shut)："
        return lead + fullStop(one.shut.why)
    }
    let names: [String] = list.map { (x: DayShut) -> String in "\(x.it.n)（\(x.shut.why)）" }
    return "這天\(more ? "還有" : "有") \(list.count) 站不開：\(names.joined(separator: "、"))。"
}

/// 句尾補句號。已經有的不重複補
func fullStop(_ text: String) -> String {
    let ends: [String] = ["。", "！", "？"]
    for end in ends {
        if text.hasSuffix(end) { return text }
    }
    return text + "。"
}

/// 這趟那一天的清單上面那一條。一天最多一條，都開就不出現。下一站卡講過的那一站不再講
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
        let all: [DayShut] = dayShuts(trip, day, store.phase)
        let skip: String? = toldOnNext(trip, day, store.phase)
        let list: [DayShut] = all.filter { (x: DayShut) -> Bool in x.it.id != skip }
        if let x = target(list) {
            Banner(dayShutText(list, more: list.count < all.count), actionTitle: actionTitle(x, list.count)) {
                act(x)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("day-closed")
        }
    }
}

/* ---------- 還有幾站沒核對 ---------- */

/// 這趟還沒去的站裡，有幾站沒核對：沒有資料的、沒查到的。二手資料算核對過，自己加的不算
func uncheckedCount(_ trip: Trip) -> Int {
    var n: Int = 0
    for x in allItems(trip) {
        if x.it.mine == true || x.it.status == .pulled { continue }
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
    var partly: Int = 0
    for it in stops {
        guard let tip = tipOf(it) else { continue }
        total += 1
        if tip.status == FactStatus.none { blank += 1 }
        if tip.status == FactStatus.second { second += 1 }
        if tip.status != FactStatus.none && tip.extra != nil { partly += 1 }
    }
    if total == 0 { return nil }
    if blank == total { return "這幾站的須知都還沒核對過，去之前再查一下。" }
    let left: Int = blank + partly
    if left > 0 { return "有 \(left) 站的須知還有沒核對過的，去之前再查一下。" }
    if second > 0 { return "有 \(second) 站的須知是二手資料，去之前再查一下。" }
    return "這幾站的須知都看過官方頁。"
}

/* ---------- 一站頁：開放、怎麼訂、來源 ---------- */

/// 卡片裡的一列：小標和內容
struct FactLine: Identifiable, Hashable {
    let label: String
    let text: String
    var muted: Bool = false

    var id: String { return label }
}

/// 有寫才加一列
private func addLine(_ out: inout [FactLine], _ label: String, _ text: String?) {
    guard let text, !text.isEmpty else { return }
    out.append(FactLine(label: label, text: text))
}

/// 「開放」那組有哪幾列，只放有的。那天不開、那天要注意的寫在標題下面，票價在花費，地址在給司機看，這裡都不再寫一次
func openLines(_ f: PlaceFact?, _ c: Cat, _ shut: StopShut?) -> [FactLine] {
    var out: [FactLine] = []
    // 歇業了，開放時間沒有意義
    if let shut, shut.gone { return out }
    guard let f else { return out }
    let words: KindWords = kindWords(c)
    addLine(&out, words.off, closedText(f))
    addLine(&out, "開放時間", f.hours)
    let last: String = f.last ?? ""
    addLine(&out, lastLabel(last, words), last)
    return out
}

/// 最後時間那一列的小標，照寫的內容：講的不是幾點前要進去、幾點前要點餐，就不掛「最後入場」「最後點餐」
private func lastLabel(_ text: String, _ words: KindWords) -> String {
    if text.contains("末班") { return "末班" }
    let marks: [String] = ["入場", "進場", "末場", "關門", "閉館", "閉園", "點餐", "點到"]
    for mark in marks {
        if text.contains(mark) { return words.last }
    }
    return text.contains("賣") || text.contains("售票") ? "售票" : "最後時間"
}

/// 上面那組底下不用再補一句「營業時間自己查」：有「開放」那組的、歇業了的
func opensKnown(_ f: PlaceFact?, _ c: Cat, _ shut: StopShut?) -> Bool {
    if let shut, shut.gone { return true }
    return !openLines(f, c, shut).isEmpty
}

/// 開賣時間那一句，換成台灣時間（Book.swift）。不在這趟裡、不知道哪天去的，講規則
private func openSaleText(_ b: BookInfo, _ visit: String?, _ today: String, _ now: Date) -> String? {
    guard let visit else { return saleRuleText(b) }
    if let until = bookOnlineUntil(b, visit), until < today {
        return bookOnlineText(b, visit, today)
    }
    // 去的當天還買不買得到，資料沒寫就不講
    if today >= visit { return nil }
    guard let sale = bookOpen(b, visit) else { return nil }
    if let at = sale.at, let minutes = bookMinutes(at), let taiwan = koreaToTaiwan(sale.on, at) {
        if koreaSeconds(sale.on, minutes) <= now.timeIntervalSince1970 { return "已經開賣" }
        return "\(fmtDay(taiwan.on))\(taiwan.at)（台灣時間）"
    }
    // 沒寫幾點：過了那天才算已經開賣
    if sale.on < today { return "已經開賣" }
    return "\(fmtDay(sale.on))，幾點還不知道"
}

/// 「，9:00（台灣時間）」。韓國時間換成台灣的，跨到前一天的就照韓國時間寫
private func saleClockText(_ at: String?) -> String {
    guard let at else { return "" }
    let ref: String = "2026-01-02"
    guard let taiwan = koreaToTaiwan(ref, at) else { return "" }
    if taiwan.on != ref { return "，\(at)（韓國時間）" }
    return "，\(taiwan.at)（台灣時間）"
}

private func saleRuleText(_ b: BookInfo) -> String? {
    let tail: String = saleClockText(b.opensAt)
    if let days = b.opensDays {
        return "去的那天往前 \(days) 天" + tail
    }
    if b.opensEvenMonth == true, let day = b.opensDay {
        return "雙數月的 \(day) 號，開後面兩個月" + tail
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

/// 要先訂，但沒查到怎麼訂。「怎麼訂」那組不出現，在上面那組底下講一次就好
func bookUnknown(_ it: Stop, _ shut: StopShut?) -> Bool {
    if !needsBook(it) || it.status == .pulled { return false }
    if let shut, shut.gone { return false }
    return factOf(it.id)?.book == nil
}

/// 「怎麼訂」那組直接看得到的：怎麼訂、開賣時間
func bookLines(_ book: BookInfo?, _ visit: String?, _ today: String, _ now: Date) -> [FactLine] {
    var out: [FactLine] = []
    if let b = book {
        addLine(&out, "方法", b.how)
        addLine(&out, "開賣時間", openSaleText(b, visit, today, now))
    }
    if out.isEmpty && webURL(book?.url) == nil {
        out.append(FactLine(label: "方法", text: "還沒查到怎麼訂，要自己查。", muted: true))
    }
    return out
}

/// 收在「訂之前要知道的」裡的幾列
func bookMoreLines(_ book: BookInfo?, _ visit: String?, _ today: String) -> [FactLine] {
    var out: [FactLine] = []
    guard let b = book else { return out }
    addLine(&out, "外國人訂不訂得到", b.foreigner)
    addLine(&out, "最晚哪天決定", decideText(b, visit, today))
    addLine(&out, "取消規則", b.cancel)
    return out
}

/// 瀏覽器開得了的網址。空的、不是網頁的都是 nil
func webURL(_ text: String?) -> URL? {
    guard let text, bookHost(text) != nil else { return nil }
    return URL(string: text)
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
        return openLines(fact, it.c, shut)
    }

    /// 去過了、歇業了就不用再講怎麼訂
    private var showBook: Bool {
        if it.status == .pulled { return false }
        if let shut, shut.gone { return false }
        return fact?.book != nil
    }

    private var openFooter: String? {
        if let f = fact, f.status == FactStatus.second { return "二手資料，去之前再查一下。" }
        return nil
    }

    var body: some View {
        if !lines.isEmpty {
            DomySection("開放", footer: openFooter) {
                ForEach(lines) { (line: FactLine) in
                    StopInfoRow(label: line.label, text: line.text)
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

/// 怎麼訂：直接看得到的只有方法和開賣時間，其餘收進「訂之前要知道的」，最下面打開訂票頁（外開，沒有網址就沒有這顆）
private struct StopBookSection: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    @Environment(\.openURL) private var openURL
    let book: BookInfo?
    let visit: String?
    @State private var showing: Bool = false

    var body: some View {
        let lines: [FactLine] = bookLines(book, visit, store.today, Date())
        let more: [FactLine] = bookMoreLines(book, visit, store.today)
        let url: URL? = webURL(book?.url)
        DomySection("怎麼訂") {
            ForEach(lines) { (line: FactLine) in
                StopInfoRow(label: line.label, text: line.text, muted: line.muted)
            }
            if !more.isEmpty {
                SettingsRow("訂之前要知道的") {
                    showing = true
                }
                .accessibilityIdentifier("stop-book-more")
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
        .sheet(isPresented: $showing) {
            StopBookPane(lines: more, onClose: { showing = false })
                .environment(store)
                .environment(sheets)
                .environment(nav)
                .tint(C.accent)
        }
    }
}

/// 訂之前要知道的（半頁）：外國人訂不訂得到、最晚哪天決定、取消規則，只放查到的
private struct StopBookPane: View {
    let lines: [FactLine]
    let onClose: () -> Void

    var body: some View {
        SheetScaffold("訂之前要知道的", onClose: onClose) {
            DomySection {
                ForEach(lines) { (line: FactLine) in
                    StopInfoRow(label: line.label, text: line.text)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
