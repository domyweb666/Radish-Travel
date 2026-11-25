// 首爾地點的核對結果：休館日、最後入場、怎麼訂、什麼時候開賣、來源。
// 內容在 Resources/seoul-checked.json，是 AI 讀官方頁核對的，不是從 mobile/ 轉出來的。
// 它疊在 seoul.json 上面：facts 照地點代號查，drop 是拿掉的，add 是新加的真店。
// 核對狀態照實寫：official 讀過官方頁、second 只有二手來源、none 沒查到。沒查到的欄位就是 nil，不猜。
import Foundation

enum FactStatus: String, Codable, Sendable {
    case official, second, none
}

/// 固定休館日碰到韓國國定假日
enum HolidayShift: String, Codable, Sendable {
    /// 假日照開，改休假日之後第一個不是假日的日子
    case next
    /// 假日照開，不補休
    case open
}

/// 每月第幾個星期幾休（week 1 起算，dow 0 是星期日）
struct NthDay: Codable, Hashable, Sendable {
    var week: Int
    var dow: Int
}

/// 有一段時間不開（整修、季節停駛）。to 沒寫就是不知道到什麼時候
struct OffSpan: Codable, Hashable, Sendable {
    var from: String
    var to: String?
    var why: String
}

/// 怎麼訂。時間都是韓國時間
struct BookInfo: Codable, Hashable, Sendable {
    var how: String  // 怎麼訂，一句話
    var url: String?
    var opensDays: Int?  // 去的那天往前幾天開賣（去的那天不算）
    var opensMonths: Int?  // 或者：去的那個月往前幾個月的 opensDay 號開賣
    var opensDay: Int?
    var opensAt: String?  // "10:00"，韓國時間。有開賣日沒寫幾點就是 nil
    var decideDays: Int?  // 去的那天往前幾天還能免費取消。那天就是最晚要決定的日子
    var cancel: String?  // 取消規則，一句話
    var foreigner: String?  // 外國人訂不訂得到，一句話。不知道是 nil
}

struct FactSource: Codable, Hashable, Sendable {
    var name: String
    var url: String
}

struct PlaceFact: Codable, Hashable, Sendable {
    var status: FactStatus
    var checked: String  // 核對那一天 YYYY-MM-DD
    var src: [FactSource]
    var closed: [Int]?  // 每週固定休，0 是星期日。空陣列是查過、沒有固定休
    var closedNth: [NthDay]?
    var closedOn: [String]?  // "01-01"、"2026-12-24"，或 lunar 表裡的鍵（seollal、chuseok…）
    var shift: HolidayShift?
    var off: [OffSpan]?
    var hours: String?  // 開放時間，一句話
    var last: String?  // 最後入場或末班，一句話
    var price: String?  // 大人票價，韓元
    var addr: String?  // 韓文地址
    var tip: String?  // 核對過的須知，有寫就取代資料包那句
    var book: BookInfo?
    var gone: String?  // 歇業、搬走、長期不開，寫原因
}

/// 一行字跟著日期走：這趟到的那天在 until 當天或之前用 before，之後用 after
struct DatedText: Codable, Hashable, Sendable {
    var id: String
    var until: String
    var before: String
    var after: String
}

struct AddedPlace: Codable, Hashable, Sendable {
    var after: String  // 排在 seoul.json 的哪一個後面
    var place: Place
}

struct SeoulChecked: Codable, Sendable {
    var checked: String
    var facts: [String: PlaceFact]
    var drop: [String]
    var add: [AddedPlace]
    var lunar: [String: [String]]  // 農曆節日每年落在哪幾天
    var holidays: [String]  // 韓國國定假日（含替代假日）
    var dated: [DatedText]

    static let shared: SeoulChecked = load()

    private static func load() -> SeoulChecked {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "seoul-checked", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { fatalError("找不到 seoul-checked.json：核對資料沒有跟著 app 一起打包") }
        do {
            return try JSONDecoder().decode(SeoulChecked.self, from: data)
        } catch {
            fatalError("seoul-checked.json 讀不出來：\(error)")
        }
    }
}

/// 候選地點：seoul.json 拿掉 drop，add 接在它要接的那一個後面。順序固定，排行程同分時取前面的
func mergePlaces(_ base: [Place], _ checked: SeoulChecked) -> [Place] {
    let gone: Set<String> = Set(checked.drop)
    var out: [Place] = []
    for p in base {
        if !gone.contains(p.id) { out.append(p) }
        for x in checked.add where x.after == p.id { out.append(x.place) }
    }
    return out
}

func factOf(_ id: String) -> PlaceFact? {
    return SeoulChecked.shared.facts[id]
}

/* ---------- 這一天開不開 ---------- */

private let CLOSED_WEEK: [String] = ["日", "一", "二", "三", "四", "五", "六"]

/// 這一天這個地方不開的原因，例如「每週二休」。開、或沒有資料就是 nil
func closedWhy(_ f: PlaceFact, _ iso: String, _ c: SeoulChecked = SeoulChecked.shared) -> String? {
    if let g = f.gone { return g }
    for o in f.off ?? [] {
        // ISO 日期照字排就是照時間排
        let before: Bool = iso < o.from
        var after: Bool = false
        if let to = o.to { after = iso > to }
        if !before && !after { return o.why }
    }
    for key in f.closedOn ?? [] {
        if let days = c.lunar[key] {
            if days.contains(iso) { return "節日休" }
        } else if iso == key || iso.hasSuffix("-" + key) {
            return "節日休"
        }
    }
    let dow: Int = dowOf(iso)
    for n in f.closedNth ?? [] {
        let dom: Int = Int(iso.suffix(2)) ?? 0
        let week: Int = (dom - 1) / 7 + 1
        if dom > 0 && n.dow == dow && n.week == week {
            return "每月第 \(n.week) 個週\(CLOSED_WEEK[dow])休"
        }
    }
    let weekly: [Int] = f.closed ?? []
    if weekly.isEmpty { return nil }
    let holiday: Bool = f.shift != nil && c.holidays.contains(iso)
    if weekly.contains(dow) && !holiday { return "每週\(CLOSED_WEEK[dow])休" }
    if f.shift == .next && !holiday {
        var d: String = addDays(iso, -1)
        var back: Int = 0
        while back < 14 && c.holidays.contains(d) {
            if weekly.contains(dowOf(d)) { return "固定休館日碰到國定假日，改休這天" }
            d = addDays(d, -1)
            back += 1
        }
    }
    return nil
}

/// 照地點代號查。自己加的、AI 加的沒有資料，是 nil
func closedWhy(_ id: String, _ iso: String) -> String? {
    guard let f = factOf(id) else { return nil }
    return closedWhy(f, iso)
}

/// 這趟第 day 天這個地方不開的原因
func closedOnDay(_ t: Trip, _ id: String, _ day: Int) -> String? {
    return closedWhy(id, addDays(t.start, day - 1))
}

/// 給人看的固定休：「每週二」「每週日、一」「沒有固定休」；沒查到是 nil
func closedText(_ f: PlaceFact) -> String? {
    let nth: [NthDay] = f.closedNth ?? []
    let festival: Bool = !(f.closedOn ?? []).isEmpty
    guard let weekly = f.closed else {
        if nth.isEmpty { return festival ? "部分節日休" : nil }
        return nthText(nth)
    }
    var parts: [String] = []
    if !weekly.isEmpty {
        let names: [String] = weekly.map { (d: Int) -> String in
            return d >= 0 && d < CLOSED_WEEK.count ? CLOSED_WEEK[d] : ""
        }
        parts.append("每週" + names.joined(separator: "、"))
    }
    if !nth.isEmpty { parts.append(nthText(nth)) }
    if parts.isEmpty { return festival ? "平常沒有固定休，部分節日休" : "沒有固定休" }
    var text: String = parts.joined(separator: "，")
    if f.shift == .next { text += "，碰到國定假日改休之後的平日" }
    if f.shift == .open { text += "，碰到國定假日照開" }
    if festival { text += "，部分節日也休" }
    return text
}

private func nthText(_ nth: [NthDay]) -> String {
    let names: [String] = nth.map { (n: NthDay) -> String in
        let d: String = n.dow >= 0 && n.dow < CLOSED_WEEK.count ? CLOSED_WEEK[n.dow] : ""
        return "第 \(n.week) 個週\(d)"
    }
    return "每月" + names.joined(separator: "、")
}

/// 核對到哪裡，短的：「看過官方頁 11/25」「二手資料 11/25」「未核對」
func factLabel(_ f: PlaceFact?) -> String {
    guard let x = f, x.status != FactStatus.none else { return "未核對" }
    let md: String = factMonthDay(x.checked)
    return x.status == FactStatus.official ? "看過官方頁 \(md)" : "二手資料 \(md)"
}

private func factMonthDay(_ iso: String) -> String {
    let parts: [Int] = iso.components(separatedBy: "-").compactMap { (x: String) -> Int? in Int(x) }
    guard parts.count == 3 else { return iso }
    return "\(parts[1])/\(parts[2])"
}

/// 這一站的須知：核對過的那句優先，沒有才用資料包的
func tipOf(_ it: Stop) -> (text: String, status: FactStatus)? {
    if let f = factOf(it.id), let t = f.tip, !t.isEmpty { return (text: t, status: f.status) }
    if let t = it.tip, !t.isEmpty { return (text: t, status: FactStatus.none) }
    return nil
}

/* ---------- 跟著這趟日期走的字 ---------- */

/// 有跟日期走的版本就用它，沒有就用原本的。{start} 換成這趟到的那天，{minus3} 換成到的前三天
func datedText(_ id: String, _ plain: String, _ start: String?, _ c: SeoulChecked = SeoulChecked.shared) -> String {
    guard let on = start else { return plain }
    let hit: DatedText? = c.dated.first { (d: DatedText) -> Bool in d.id == id }
    guard let rule = hit else { return plain }
    let text: String = on <= rule.until ? rule.before : rule.after
    let first: String = text.replacingOccurrences(of: "{start}", with: fmtDay(on))
    return first.replacingOccurrences(of: "{minus3}", with: fmtDay(addDays(on, -3)))
}
