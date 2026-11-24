// 這一天的路線（S12，線框 A8）按「請 AI 提一個改法」之後，同一張半頁換成「這次會改」那一面。這個檔放它背後的規則：
// 1. 給 AI 的提示詞：只給這一天看，ops 只准 move（同一天換時段）和 swapParts（同一天兩個時段對調）
// 2. 回來的 ops 先在行程的複本上試套，用 dayLegs 算改前改後路上幾分鐘（估）；動到別天、套不上、沒有比較省的都不拿出來
// 3. 不能送 AI 的時候，手機自己試：對調兩個時段、把一站移到這天別的時段，挑最省、至少省 ROUTE_MIN_SAVE 分鐘的那一個
// 回 AI 的格式沿用 Chat.swift 的 {reply, ops}，套用也走同一個 applyOps。全部是純函式，畫面在 Radish/Sheets/MapSheet.swift。
// 這個檔是 SwiftUI 版才有的，mobile/ 沒有對應的 TS。
import Foundation

/// 手機算的改法至少要省這麼多分鐘（估）才拿出來講。分鐘數本來就是粗估，差一兩分鐘不值得動行程
let ROUTE_MIN_SAVE: Int = 5

/// 這個改法是誰提的。畫面上標「AI 提的」或「手機算的，沒有問 AI」
enum RouteBy: Equatable, Sendable {
    case ai
    case phone
}

/// 「這次會改」那一面的一列：哪一站從哪個時段換到哪個時段
struct RouteMove: Hashable, Sendable {
    var id: String
    var name: String
    var from: Part
    var to: Part
}

/// 在複本上試套過、確定比原本省的一個改法
struct RoutePlan {
    var by: RouteBy
    /// 按「照這樣改」時照樣交給 applyOps。AI 給的是 JSON 物件，手機算的是 Op
    var ops: [Any]
    var moves: [RouteMove]
    /// 改前、改後這一天路上大約幾分鐘（估），含從住的地方出發和回去
    var before: Int
    var after: Int
    /// AI 回的那一句。手機算的是空字串
    var reply: String

    var saved: Int {
        return before - after
    }
}

/// 試套的結果
enum RouteVerdict {
    /// 有比較省的改法
    case plan(RoutePlan)
    /// 這天已經算順，沒有更省的
    case smooth
    /// 套不上：動到別天、動到不能動的、用了不准用的動作、有一步做不成
    case broken
    /// 這天有站沒有位置，算不出改了會不會比較省
    case unknown
}

/// 要 AI 但這次沒問到（丟錯）時寫的那一句。細節（AskError 的 description）由畫面另外用小字寫
let ROUTE_ASK_FAILED: String = "這次沒問到，這天先不動。"

/// 沒同意過送資料給 AI 時寫的那一句。同意流程在問 AI 分頁，這裡不做
let ROUTE_NEED_CONSENT: String = "要先同意送資料給 AI，去問 AI 分頁講一句要 AI 幫忙的，就會問你。"

/// 同意過別的地方、現在會送去的這個地方還沒同意時寫的那一句
let ROUTE_NEW_DEST: String = "送給 AI 的地方跟你同意過的不一樣，要再同意一次。去問 AI 分頁講一句要 AI 幫忙的，就會問你。"

/// 沒有拿出改法時寫的那一句
func routeVerdictText(_ v: RouteVerdict, _ by: RouteBy) -> String {
    switch v {
    case .plan:
        return ""
    case .smooth:
        if by == .ai { return "AI 看過了，這天的順序已經算順，沒有更省的改法。" }
        return "手機算過了，這天的順序已經算順，沒有能省 \(ROUTE_MIN_SAVE) 分鐘以上的改法。"
    case .broken:
        if by == .ai { return "AI 提的改法套不上，這天先不動。" }
        return "手機算的改法套不上，這天先不動。"
    case .unknown:
        return "這天有站沒有位置，算不出改了會不會比較省，這天先不動。"
    }
}

/// 「這次會改」的一列，例：聖水洞咖啡廳：下午 → 上午
func routeMoveLine(_ m: RouteMove) -> String {
    return "\(m.name)：\(PART[need: m.from]) → \(PART[need: m.to])"
}

/* ---------- 分鐘數 ---------- */

/// 這一天路上大約幾分鐘（估），含從住的地方出發和回去。有一段距離不明就回 nil：少算一段的總數拿來比會騙人
func routeMinutes(_ t: Trip, _ base: Settings, _ day: Int) -> Int? {
    var total: Int = 0
    for l in dayLegs(t, base, day) {
        guard let l = l else { return nil }
        total += l.min
    }
    return total
}

/* ---------- 檢查 AI 回來的 ops ---------- */

/// JSON 來的整數。JSONSerialization 給的是 NSNumber，測試和 opJSON 給的是 Int
private func routeInt(_ v: Any?) -> Int? {
    if let n = v as? Int { return n }
    if let n = v as? NSNumber {
        let d: Double = n.doubleValue
        if d == d.rounded() && abs(d) < 10000 { return Int(d) }
    }
    return nil
}

private func routePart(_ v: Any?) -> Part? {
    guard let w = v as? String else { return nil }
    return Part(rawValue: w)
}

/// 一步 op 變成 JSON 物件。不是物件的回 nil
private func routeObj(_ raw: Any) -> [String: Any]? {
    if let typed = raw as? Op { return opJSON(typed) }
    return raw as? [String: Any]
}

/// 這串 ops 是不是全都只動這一天：只准 move（站本來就在這天、移到這天的某個時段）和 swapParts（這天的兩個不同時段）。
/// 有一步不是，整串都不要
func routeOpsInDay(_ t: Trip, _ day: Int, _ ops: [Any]) -> Bool {
    if ops.count > OPS_MAX { return false }
    for raw in ops {
        guard let o = routeObj(raw), let op = o["op"] as? String else { return false }
        if op == "move" {
            guard let id = o["id"] as? String, let x = findItem(t, id), x.s.day == day,
                routeInt(o["day"]) == day, routePart(o["part"]) != nil
            else { return false }
        } else if op == "swapParts" {
            guard routeInt(o["day"]) == day, let a = routePart(o["a"]), let b = routePart(o["b"]), a != b
            else { return false }
        } else {
            return false
        }
    }
    return true
}

/// 別天的時段有沒有一模一樣
private func routeOtherDaysSame(_ before: Trip, _ after: Trip, _ day: Int) -> Bool {
    let a: [Slot] = before.slots.filter { (s: Slot) -> Bool in s.day != day }
    let b: [Slot] = after.slots.filter { (s: Slot) -> Bool in s.day != day }
    return a == b
}

/// 改前改後，這一天哪幾站換了時段。照改完的順序排
func routeMoves(_ before: Trip, _ after: Trip, _ day: Int) -> [RouteMove] {
    var was: [String: Part] = [:]
    for x in dayStops(before, day) { was[x.it.id] = x.s.part }
    var out: [RouteMove] = []
    for x in dayStops(after, day) {
        guard let from = was[x.it.id], from != x.s.part else { continue }
        out.append(RouteMove(id: x.it.id, name: x.it.n, from: from, to: x.s.part))
    }
    return out
}

/// 在複本上試套一串 ops，跟原本比分鐘。minSave 是至少要省幾分鐘才算數：AI 提的 1（有比較省就好），手機算的 ROUTE_MIN_SAVE。
/// now 有給（旅途中）時，過去的時段不動；拔起來的站不管什麼時候都不動（applyOps 擋的）
func routeTry(
    _ t: Trip, _ base: Settings, _ day: Int, _ ops: [Any], _ now: TripNow?,
    by: RouteBy, reply: String = "", minSave: Int = 1
) -> RouteVerdict {
    if ops.isEmpty { return .smooth }
    guard routeOpsInDay(t, day, ops) else { return .broken }
    var copy: Trip = t
    var seeds: [Seed] = []
    // 這一面會把每一站從哪到哪列出來給他看，按「照這樣改」就是點頭了，所以動到自己加的站也照做（confirmed）
    let r: (changes: [String], notes: [String]) = applyOps(&copy, &seeds, ops, now, true)
    if !r.notes.isEmpty || !seeds.isEmpty { return .broken }
    guard routeOtherDaysSame(t, copy, day) else { return .broken }
    let moves: [RouteMove] = routeMoves(t, copy, day)
    if moves.isEmpty { return .smooth }
    guard let before = routeMinutes(t, base, day), let after = routeMinutes(copy, base, day) else { return .unknown }
    if before - after < max(minSave, 1) { return .smooth }
    return .plan(RoutePlan(by: by, ops: ops, moves: moves, before: before, after: after, reply: reply))
}

/* ---------- 手機自己算 ---------- */

/// 這個時段能不能動：不在路上、還沒過、裡面沒有拔起來的站
private func routeSlotOpen(_ t: Trip, _ day: Int, _ part: Part, _ now: TripNow?) -> Bool {
    guard let si = slotAt(t, day, part) else { return false }
    if slotPast(now, day, part) { return false }
    return !t.slots[si].items.contains { (it: Stop) -> Bool in it.status == .pulled }
}

/// 這一站放在這個時段合不合理：主要景點不放晚上（多半關了），夜生活只放晚上
private func routeFits(_ it: Stop, _ part: Part) -> Bool {
    if it.c == .night { return part == .eve }
    if it.s == .L { return part != .eve }
    return true
}

/// 改完之後，本來放得合理的站有沒有被換到不合理的時段
private func routeStillFits(_ before: Trip, _ after: Trip, _ day: Int) -> Bool {
    for m in routeMoves(before, after, day) {
        guard let x = findItem(after, m.id) else { continue }
        if routeFits(x.it, m.from) && !routeFits(x.it, m.to) { return false }
    }
    return true
}

/// 這一天手機能試的每一步：兩個時段對調在前，再來是把一站移到別的時段
private func routeCandidates(_ t: Trip, _ day: Int, _ now: TripNow?) -> [Op] {
    let open: [Part] = PARTS.filter { (p: Part) -> Bool in routeSlotOpen(t, day, p, now) }
    var out: [Op] = []
    for i in 0..<open.count {
        for j in (i + 1)..<open.count {
            let a: Part = open[i]
            let b: Part = open[j]
            guard let sa = slotAt(t, day, a), let sb = slotAt(t, day, b) else { continue }
            if t.slots[sa].items.isEmpty && t.slots[sb].items.isEmpty { continue }
            out.append(Op.swapParts(day: day, a: a, b: b))
        }
    }
    for x in dayStops(t, day) where open.contains(x.s.part) {
        for p in open where p != x.s.part {
            out.append(Op.move(id: x.it.id, day: day, part: p))
        }
    }
    return out
}

/// 不能送 AI 時，手機自己找一個改法。一天最多 2 個主要景點、在路上的時段不能排、第一天和最後一天只排小站：
/// 只在同一天裡換時段，這三條本來就不會變；在路上的時段 slotAt 找不到，不會被選到
func routePhone(_ t: Trip, _ base: Settings, _ day: Int, _ now: TripNow?) -> RouteVerdict {
    guard let before = routeMinutes(t, base, day) else { return .unknown }
    var best: Op? = nil
    var bestMin: Int = before
    for op in routeCandidates(t, day, now) {
        var copy: Trip = t
        var seeds: [Seed] = []
        let r: (changes: [String], notes: [String]) = applyOps(&copy, &seeds, [op] as [Any], now, true)
        if !r.notes.isEmpty || r.changes.isEmpty { continue }
        if !routeStillFits(t, copy, day) { continue }
        guard let mins = routeMinutes(copy, base, day) else { continue }
        // 一樣省的留先找到的（對調在前）
        if mins < bestMin {
            best = op
            bestMin = mins
        }
    }
    guard let pick = best, before - bestMin >= ROUTE_MIN_SAVE else { return .smooth }
    return routeTry(t, base, day, [pick] as [Any], now, by: .phone, minSave: ROUTE_MIN_SAVE)
}

/* ---------- 給 AI 的提示詞 ---------- */

/// 這一天每個時段排了什麼，方括號裡是 id
private func routeDayText(_ t: Trip, _ day: Int, _ now: TripNow?) -> String {
    var s: String = ""
    for p in PARTS {
        let found: Slot? = t.slots.first { (x: Slot) -> Bool in x.day == day && x.part == p }
        guard let sl = found else { continue }
        let partName: String = PART[need: p]
        if sl.off == true {
            s += "  \(partName)：在路上，不能排\n"
            continue
        }
        var items: [String] = []
        for i in sl.items {
            let size: String = i.s == .L ? "主要景點" : "順路的小地方"
            let pulled: String = i.status == .pulled ? ",拔起來了" : ""
            let mine: String = i.mine == true ? ",自己加的" : ""
            var at: String = ",位置不明"
            if let lat = i.lat, let lng = i.lng { at = ",約 " + String(format: "%.4f,%.4f", lat, lng) }
            items.append("[\(i.id)] \(i.n)(\(size),\(CAT[need: i.c]),\(areaOf(i))\(at)\(mine)\(pulled))")
        }
        var line: String = items.joined(separator: "、")
        if line.isEmpty { line = sl.rest ? "留白" : "空的" }
        if slotPast(now, day, p) { line += "；已經過了" }
        s += "  \(partName)：\(line)\n"
    }
    return s
}

/// 這一天每一段怎麼去、幾分鐘（估）
private func routeLegText(_ t: Trip, _ base: Settings, _ day: Int) -> String {
    let st: Settings = tripSettings(base, t.tweaks)
    let h: HotelPt = hotelPt(st, t)
    let home: String = "住的地方（\(h.n)）"
    var names: [String] = [home]
    for x in dayStops(t, day) { names.append(x.it.n) }
    names.append(home)
    let legs: [Leg?] = dayLegs(t, base, day)
    var s: String = ""
    for (i, l) in legs.enumerated() where i + 1 < names.count {
        s += "  \(names[i]) → \(names[i + 1])：\(legText(l))\n"
    }
    if let total = routeMinutes(t, base, day) {
        s += "  合計大約 \(total) 分鐘（估）\n"
    } else {
        s += "  有一段距離不明，合計算不出來\n"
    }
    return s
}

/// 只給「這一天的路線」用的提示詞。clock 是按下那一刻的「現在」，沒給就不講現在
func routePrompt(_ t: Trip, _ base: Settings, _ day: Int, _ clock: ChatClock? = nil) -> String {
    let st: Settings = tripSettings(base, t.tweaks)
    let h: HotelPt = hotelPt(st, t)
    let now: TripNow? = tripNow(clock)
    let date: String = t.start.isEmpty ? "" : " " + tripDayLabel(t, day)
    let nowText: String = nowLine(t, clock)

    let head: String = """
你是旅遊行程 app「蘿蔔旅行」裡的助手，幫一位台灣使用者看他首爾行程裡某一天的路線順不順。用繁體中文、口語、簡短回答（兩句內），不要用 markdown、不要用表情符號。

這次只做一件事：在第 \(day) 天裡調換時段，讓這天路上花的時間少一點。規則：
- 只准動第 \(day) 天。只能用兩種動作：把這天的一站移到這天別的時段（move，day 一定是 \(day)），或把這天兩個時段整個對調（swapParts，day 一定是 \(day)）。
- 不准加站、拿站、換成別的地方、整天對調、改留白、改這趟的調整，也不准動別天。
- 標「在路上」的時段不能排東西。標「已經過了」的時段、標「拔起來了」的站不能動，也不能把東西移進已經過了的時段。
- 主要景點不要移到晚上（多半關了），夜生活類的留在晚上。
- 分鐘數是 app 照直線距離加三成估的，你也只能估。你不知道即時交通、營業時間，不要講成確定的事。
- 真的會比較省才提。這天的順序已經算順、或你不確定，ops 給空陣列，reply 說這天已經算順。
- reply 回覆使用者時說「主要景點」「順路的小地方」，不要說「大站」「小站」。
"""

    var mid: String = "\n\n這一天：第 \(day) 天\(date)，從\(h.n)出發，回到\(h.n)。"
    if !nowText.isEmpty { mid += "\n" + nowText }
    mid += "\n\n第 \(day) 天排的（方括號裡是 id）：\n\(routeDayText(t, day, now))"
    mid += "\n現在每一段怎麼去：\n\(routeLegText(t, base, day))\n"

    let tail: String = """
只回一個 JSON 物件，不要有其他文字：
{"reply":"給使用者看的話","ops":[...]}
ops 只能用這兩種動作：
{"op":"move","id":"p3","day":\(day),"part":"am"}        把這天的一站移到這天的某個時段（part: am/pm/eve）
{"op":"swapParts","day":\(day),"a":"am","b":"pm"}       這天兩個時段對調
"""

    return head + mid + tail
}
