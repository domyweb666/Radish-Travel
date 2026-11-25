// 要先訂的站：哪天開賣、最晚哪天決定、怎麼訂，還有出發前再查一次的那一句。
// 資料在 SeoulFacts.swift，時間都是韓國時間。給人看的一律換成台灣時間，並寫明是台灣時間。
// 每個函式查資料的那一個都能換掉（fact:），測試不靠真的資料。
import Foundation

private let DAY_MINUTES: Int = 1440
private let KOREA_ZONE: Int = 9
private let TAIWAN_ZONE: Int = 8

/* ---------- 時間 ---------- */

/// "10:00" → 從 0 點起第幾分鐘。寫得不對就是 nil
func bookMinutes(_ at: String) -> Int? {
    let bits: [String] = at.components(separatedBy: ":")
    guard bits.count == 2, let h = Int(bits[0]), let m = Int(bits[1]) else { return nil }
    guard h >= 0 && h < 24 && m >= 0 && m < 60 else { return nil }
    return h * 60 + m
}

/// 第幾分鐘 → "9:00"
func bookClock(_ minutes: Int) -> String {
    let m: Int = minutes % 60
    return "\(minutes / 60):" + (m < 10 ? "0\(m)" : "\(m)")
}

/// 韓國時間換成台灣時間：早一小時，過了半夜就是前一天。時間寫得不對就是 nil
func koreaToTaiwan(_ on: String, _ at: String) -> (on: String, at: String)? {
    guard let korea = bookMinutes(at) else { return nil }
    let taiwan: Int = korea - (KOREA_ZONE - TAIWAN_ZONE) * 60
    if taiwan < 0 { return (on: addDays(on, -1), at: bookClock(taiwan + DAY_MINUTES)) }
    return (on: on, at: bookClock(taiwan))
}

/// 某個時區的那一天那一分鐘，是 1970 起算第幾秒
private func secondsOf(_ on: String, _ minutes: Int, _ zone: Int) -> Double {
    let total: Int = diffDays("1970-01-01", on) * DAY_MINUTES + minutes - zone * 60
    return Double(total) * 60
}

/// 1970 起算第幾秒，是某個時區的哪一天第幾分鐘
private func localOf(_ seconds: Double, _ zone: Int) -> (on: String, minutes: Int) {
    let total: Int = Int((seconds / 60).rounded(.down)) + zone * 60
    var days: Int = total / DAY_MINUTES
    var rest: Int = total % DAY_MINUTES
    if rest < 0 {
        rest += DAY_MINUTES
        days -= 1
    }
    return (on: addDays("1970-01-01", days), minutes: rest)
}

func koreaSeconds(_ on: String, _ minutes: Int) -> Double {
    return secondsOf(on, minutes, KOREA_ZONE)
}

func taiwanSeconds(_ on: String, _ minutes: Int) -> Double {
    return secondsOf(on, minutes, TAIWAN_ZONE)
}

func koreaLocal(_ seconds: Double) -> (on: String, minutes: Int) {
    return localOf(seconds, KOREA_ZONE)
}

func taiwanLocal(_ seconds: Double) -> (on: String, minutes: Int) {
    return localOf(seconds, TAIWAN_ZONE)
}

/// 現在是第幾秒。沒給現在時刻就當成今天剛開始（台灣時間 0 點）
func bookNow(_ today: String, _ now: Date?) -> Double {
    if let now { return now.timeIntervalSince1970 }
    return taiwanSeconds(today, 0)
}

/* ---------- 哪天開賣、最晚哪天決定 ---------- */

/// 去的那天是 visit，哪一天開賣。at 是韓國時間，沒寫幾點是 nil。不知道哪天開賣就是 nil
func bookOpen(_ b: BookInfo, _ visit: String) -> (on: String, at: String?)? {
    var at: String? = nil
    if let text = b.opensAt, bookMinutes(text) != nil { at = text }
    if let n = b.opensDays {
        if n < 0 { return nil }
        return (on: addDays(visit, -n), at: at)
    }
    guard let months = b.opensMonths, let day = b.opensDay, months >= 0, day >= 1 else { return nil }
    let parts: [Int] = visit.components(separatedBy: "-").compactMap { (x: String) -> Int? in Int(x) }
    guard parts.count == 3 else { return nil }
    // 那個月沒有那一號就取最後一天
    let cells: [String?] = monthGrid(parts[0], parts[1] - months)
    let dates: [String] = cells.compactMap { (x: String?) -> String? in x }
    guard !dates.isEmpty else { return nil }
    return (on: dates[min(day, dates.count) - 1], at: at)
}

/// 最晚要決定的那天（還能免費取消的最後一天）。不知道是 nil
func bookDecide(_ b: BookInfo, _ visit: String) -> String? {
    guard let n = b.decideDays, n >= 0 else { return nil }
    return addDays(visit, -n)
}

/* ---------- 這趟要先訂的 ---------- */

enum BookStage: Hashable, Sendable {
    /// 還沒開賣
    case notYet
    /// 已經開賣
    case open
    /// 不知道什麼時候開賣
    case unknown
}

/// 一個要先訂的站。開賣的日期時間已經換成台灣的
struct BookRow: Identifiable, Hashable, Sendable {
    var stop: Stop
    var day: Int
    var part: Part
    var visit: String  // 哪天去
    var stage: BookStage
    var openOn: String?  // 開賣那天
    var openAt: String?  // 台灣時間 "9:00"。沒寫幾點是 nil
    var openSeconds: Double?  // 開賣的那一刻，1970 起算第幾秒。沒寫幾點是 nil
    var how: String?
    var url: String?
    var foreigner: String?
    var cancel: String?
    var decideOn: String?
    var status: FactStatus
    var checked: Bool  // 打勾了沒

    var id: String {
        return "\(day)-\(part.rawValue)-\(stop.id)"
    }
}

/// 這趟每一個要先訂的站，照行程順序。只有標了要先訂（b）的才在這裡
func bookPlan(
    _ trip: Trip, _ checks: [String: Bool], _ today: String, now: Date? = nil,
    fact: (String) -> PlaceFact? = factOf
) -> [BookRow] {
    let clock: Double = bookNow(today, now)
    var out: [BookRow] = []
    for x in allItems(trip) where x.it.b == true {
        let found: PlaceFact? = fact(x.it.id)
        let visit: String = addDays(trip.start, x.s.day - 1)
        var row: BookRow = BookRow(
            stop: x.it, day: x.s.day, part: x.s.part, visit: visit, stage: BookStage.unknown,
            openOn: nil, openAt: nil, openSeconds: nil, how: nil, url: nil, foreigner: nil,
            cancel: nil, decideOn: nil, status: FactStatus.none,
            checked: checks["b_" + x.it.id] == true)
        if let f = found, let b = f.book {
            row.status = f.status
            row.how = b.how
            row.url = b.url
            row.foreigner = b.foreigner
            row.cancel = b.cancel
            row.decideOn = bookDecide(b, visit)
            bookFillOpen(&row, b, today, clock)
        }
        out.append(row)
    }
    return out
}

private func bookFillOpen(_ row: inout BookRow, _ b: BookInfo, _ today: String, _ clock: Double) {
    guard let open = bookOpen(b, row.visit) else { return }
    if let at = open.at, let minutes = bookMinutes(at), let tw = koreaToTaiwan(open.on, at) {
        let seconds: Double = koreaSeconds(open.on, minutes)
        row.openOn = tw.on
        row.openAt = tw.at
        row.openSeconds = seconds
        row.stage = seconds <= clock ? BookStage.open : BookStage.notYet
        return
    }
    // 沒寫幾點：過了那天才算已經開賣
    row.openOn = open.on
    row.stage = open.on < today ? BookStage.open : BookStage.notYet
}

/* ---------- 給人看的字 ---------- */

/// 12/8，不帶星期
private func bookMonthDay(_ iso: String) -> String {
    return fmtDay(iso).components(separatedBy: "（").first ?? iso
}

/// 第 2 天 12/8（二）上午
func bookWhen(_ r: BookRow) -> String {
    return "第 \(r.day) 天 \(fmtDay(r.visit))\(PART[need: r.part])"
}

/// 開賣那一句
func bookOpenText(_ r: BookRow, _ today: String) -> String {
    if r.stage == BookStage.open { return "已經開賣" }
    guard r.stage == BookStage.notYet, let on = r.openOn else { return "開賣時間還不知道" }
    let date: String = on == today ? "今天" : fmtDay(on)
    guard let at = r.openAt else { return "\(date)開賣，幾點還不知道" }
    let gap: String = on == today ? " " : ""
    return "\(date)\(gap)\(at) 開賣（台灣時間）"
}

/// 免費取消那一句。不知道就是 nil
func bookDecideText(_ r: BookRow, _ today: String) -> String? {
    guard let on = r.decideOn else { return nil }
    return on >= today ? "免費取消到 \(bookMonthDay(on))" : "免費取消的期限過了"
}

/// 要先訂的那一列的說明，最多兩行。打勾了就不用再寫開賣
func bookNote(_ r: BookRow, _ today: String) -> String {
    var first: String = bookWhen(r)
    if let decide = bookDecideText(r, today) { first += "・" + decide }
    if r.checked { return first }
    return first + "\n" + bookOpenText(r, today)
}

/// 這一段下面那句：有查到的、沒查到的，照實講
func bookFooter(_ rows: [BookRow]) -> String {
    let known: Bool = rows.contains { (r: BookRow) -> Bool in r.how != nil }
    if known { return "訂好了就打勾。查到的規則會變，訂之前再看一次訂票網頁。沒寫的就是還沒查到，要自己查。" }
    return "訂好了就打勾。怎麼訂、外國人訂不訂得到，還沒查到，要自己查。"
}

/// 訂票網頁的網站名。不是網址就是 nil
func bookHost(_ url: String?) -> String? {
    guard let text = url, let parts = URLComponents(string: text) else { return nil }
    guard parts.scheme == "https" || parts.scheme == "http" else { return nil }
    guard let host = parts.host, !host.isEmpty else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

/// 接在提醒後面的那一句：怎麼訂。資料只寫了去哪裡（官網）就補成一句，沒寫怎麼訂就用網站名
func bookHowText(_ r: BookRow) -> String {
    let trim: CharacterSet = CharacterSet(charactersIn: " 。\n")
    let how: String = (r.how ?? "").trimmingCharacters(in: trim)
    if how.isEmpty {
        guard let host = bookHost(r.url) else { return "" }
        return "到 \(host) 訂。"
    }
    let verbs: [String] = ["訂", "約", "買", "票", "排"]
    let full: Bool = verbs.contains { (v: String) -> Bool in how.contains(v) }
    if full { return how + "。" }
    let ascii: Bool = how.first?.isASCII ?? false
    return ascii ? "到 \(how) 訂。" : "到\(how)訂。"
}

/* ---------- 出發前再查一次 ---------- */

/// 讀過官方頁或有二手資料
private func bookKnown(_ f: PlaceFact?) -> Bool {
    guard let x = f else { return false }
    return x.status != FactStatus.none
}

/// 查到休不休的資料了嗎。一欄都沒有就是沒查到
private func bookHasClosed(_ f: PlaceFact?) -> Bool {
    guard let x = f else { return false }
    return x.closed != nil || x.closedNth != nil || x.closedOn != nil || x.off != nil || x.gone != nil
}

/// 那天不開的站，一站一句：第 2 天景福宮那天休館（每週二休）。判斷跟 closedWhy 一樣，不另外看核對狀態
func closedLines(
    _ trip: Trip, fact: (String) -> PlaceFact? = factOf, _ c: SeoulChecked = SeoulChecked.shared
) -> [String] {
    var out: [String] = []
    for x in allItems(trip) where x.it.status == .kept {
        guard let f = fact(x.it.id) else { continue }
        let visit: String = addDays(trip.start, x.s.day - 1)
        guard let raw = closedWhy(f, visit, c) else { continue }
        let why: String = raw.trimmingCharacters(in: CharacterSet(charactersIn: " 。\n"))
        let name: String = "第 \(x.s.day) 天\(x.it.n)"
        out.append(f.gone != nil ? "\(name)去不了（\(why)）" : "\(name)那天休館（\(why)）")
    }
    return out
}

/// 還沒核對、有訂位休館班次要再查的站。核對過的不用再叫他查，除非須知寫了休館卻沒查到哪天休
func recheckStops(_ trip: Trip, fact: (String) -> PlaceFact? = factOf) -> [Stop] {
    var out: [Stop] = []
    for x in allItems(trip) {
        let tip: String = x.it.tip ?? ""
        let f: PlaceFact? = fact(x.it.id)
        if bookKnown(f) {
            if tip.contains("休館") && !bookHasClosed(f) { out.append(x.it) }
            continue
        }
        let risky: Bool = tip.contains("休館") || tip.contains("班次") || tip.contains("名額")
        if x.it.b == true || risky { out.append(x.it) }
    }
    return out
}

/// 出發前那幾天的橫幅：哪一站休館、哪幾站再查一次。都沒有就是 nil
func recheckText(
    _ trip: Trip, _ days: Int, fact: (String) -> PlaceFact? = factOf,
    _ c: SeoulChecked = SeoulChecked.shared
) -> String? {
    let closed: [String] = closedLines(trip, fact: fact, c)
    let left: [Stop] = recheckStops(trip, fact: fact)
    if closed.isEmpty && left.isEmpty { return nil }
    var text: String = "還有 \(days) 天出發。"
    for line in closed { text += line + "。" }
    if !left.isEmpty {
        let names: [String] = left.map { (x: Stop) -> String in x.n }
        text += "這 \(left.count) 站有訂位、休館日或班次，再查一次：\(names.joined(separator: "、"))。"
    }
    return text
}

/* ---------- 改完行程之後才出現的提醒 ---------- */

/// 改之前就有的不再講一次，只留改完才出現的，照原本的順序
func newLines(_ before: [String], _ after: [String]) -> [String] {
    let old: Set<String> = Set(before)
    return after.filter { (line: String) -> Bool in !old.contains(line) }
}

/// 這次改動才出現的：太滿、休館。沒有改到東西就是空的
func newWarnings(_ before: Trip, _ after: Trip, closed: ClosedCheck = closedByFacts) -> [String] {
    let old: [String] = warnings(before, closed: closed)
    let now: [String] = warnings(after, closed: closed)
    return newLines(old, now)
}

/// 這次改動才出現的休館
func newClosedNotes(_ before: Trip, _ after: Trip, closed: ClosedCheck = closedByFacts) -> [String] {
    let old: [String] = closedNotes(before, closed: closed)
    let now: [String] = closedNotes(after, closed: closed)
    return newLines(old, now)
}

/// 接在「改好了」後面的休館。超過兩條就只講幾站，沒有就是空的
func closedTail(_ notes: [String]) -> String {
    if notes.count > 2 { return "有 \(notes.count) 站那天休館，看每天最上面那一行。" }
    return notes.joined()
}

/* ---------- 跟著日期走的字 ---------- */

/// 這一條過了公告的期限了嗎（這趟到的那天在 until 之後）。過了就比別條急
func datedLate(_ id: String, _ start: String?, _ c: SeoulChecked = SeoulChecked.shared) -> Bool {
    guard let on = start else { return false }
    let hit: DatedText? = c.dated.first { (d: DatedText) -> Bool in d.id == id }
    guard let rule = hit else { return false }
    return on > rule.until
}
