// 排行程的本機規則，從原型第三版搬過來。純函式，不碰畫面，Tests/ 可以直接跑。
// 接上 AI 之後，第一版行程改由後端產生，這裡留著當離線與測試用的底。
// 照 mobile/src/domain/plan.ts 搬。generate 和它的私有幫手在 PlanGenerate.swift。
import Foundation

let PARTS: [Part] = [.am, .pm, .eve]
private let FOOD_KINDS: [FoodKind] = [.street, .local, .famous, .fine]
private let CATS: [Cat] = [.eat, .shop, .fun, .sight, .art, .nature, .cafe, .night, .kpop]

func defaultSettings() -> Settings {
    return Settings(
        stay: .cheap,
        base: .C,
        food: [.street: 2, .local: 3, .famous: 1, .fine: 0],
        allergy: [],
        avoid: [],
        meh: [],
        walk: .normal,
        body: [],
        learned: [],
        queue: .few,
        mealMax: 1500,
        budget: 1500,
        play: [.eat: 2],
        purposes: [],
        tags: [],
        wish: "",
        pace: .mid,
        wake: .normal,
        move: .transit,
        tuned: false
    )
}

/* ---------- 小工具（Swift 這邊才需要的） ---------- */

/// TS 的 Math.round：剛好 .5 的往正的方向進位
func planRound(_ x: Double) -> Int {
    guard x.isFinite else { return 0 }
    let r: Double = (x + 0.5).rounded(.down)
    if r > 9.0e18 { return Int.max }
    if r < -9.0e18 { return Int.min }
    return Int(r)
}

/// 千分位（TS 的 toLocaleString('en-US')）
private func grouped(_ n: Int) -> String {
    let digits: [Character] = Array(String(n.magnitude))
    var out: String = ""
    var i: Int = 0
    for ch in digits {
        let left: Int = digits.count - i
        if i > 0 && left % 3 == 0 { out.append(",") }
        out.append(ch)
        i += 1
    }
    return n < 0 ? "-" + out : out
}

/// 穩定排序：less 分不出前後的，照原本的位置排（TS 的 sort 是穩定的，Swift 的不保證）
func planStableSorted<T>(_ xs: [T], _ less: (T, T) -> Bool) -> [T] {
    var boxed: [(offset: Int, element: T)] = []
    var i: Int = 0
    for x in xs {
        boxed.append((offset: i, element: x))
        i += 1
    }
    let sorted: [(offset: Int, element: T)] = boxed.sorted { (x: (offset: Int, element: T), y: (offset: Int, element: T)) -> Bool in
        if less(x.element, y.element) { return true }
        if less(y.element, x.element) { return false }
        return x.offset < y.offset
    }
    return sorted.map { (x: (offset: Int, element: T)) -> T in x.element }
}

func money(_ n: Double) -> String {
    return "NT$ " + grouped(planRound(n))
}

func foodLv(_ st: Settings) -> [FoodKind: Int] {
    // 說過「以後都不排」的那幾種，當成不要
    let no: Set<FoodKind> = bannedFood(st)
    var f: [FoodKind: Int] = [:]
    var any: Bool = false
    for k in FOOD_KINDS {
        let v: Int = no.contains(k) ? 0 : (st.food[k] ?? 0)
        f[k] = v
        if v > 0 { any = true }
    }
    if any { return f }
    return [.street: 0, .local: 1, .famous: 0, .fine: 0]
}

func foodPct(_ st: Settings) -> [FoodKind: Int] {
    let f: [FoodKind: Int] = foodLv(st)
    var t: Int = 0
    for k in FOOD_KINDS { t += f[k] ?? 0 }
    var out: [FoodKind: Int] = [:]
    for k in FOOD_KINDS {
        let v: Int = f[k] ?? 0
        out[k] = t == 0 ? 0 : planRound(Double(v) / Double(t) * 100)
    }
    return out
}

/// 每一類的分數。generate 和 alternatives 都用
func planWeights(_ st: Settings) -> [Cat: Int] {
    var w: [Cat: Int] = [:]
    for k in CATS { w[k] = 1 + 2 * (st.play[k] ?? 0) }
    for purpose in st.purposes {
        switch purpose {
        case .rest:
            w[.nature] = (w[.nature] ?? 0) + 2
            w[.cafe] = (w[.cafe] ?? 0) + 1
        case .eat:
            w[.eat] = (w[.eat] ?? 0) + 2
        case .fun:
            w[.fun] = (w[.fun] ?? 0) + 2
        case .see:
            w[.sight] = (w[.sight] ?? 0) + 2
            w[.art] = (w[.art] ?? 0) + 1
        }
    }
    return w
}

/// TS 的 toStop：候選地點變成行程裡的一站
func planToStop(_ p: Place, _ why: String) -> Stop {
    return Stop(
        id: p.id, n: p.n, kr: p.kr, a: p.a, s: p.s, c: p.c, lat: p.lat, lng: p.lng,
        b: p.b, fee: p.fee, tip: p.tip, l: p.l, up: p.up, f: p.f, ic: p.ic,
        status: .kept, swaps: 0, why: why
    )
}

/* ---------- 那一天休不休館 ---------- */

/// 休館判斷：地點代號、YYYY-MM-DD → 不開的原因，有開或沒資料是 nil
typealias ClosedCheck = (String, String) -> String?

/// 平常用的那一個：照核對資料（SeoulFacts.swift）
func closedByFacts(_ id: String, _ iso: String) -> String? {
    return closedWhy(id, iso)
}

/// start 出發的第 day 天，這個地方不開的原因。沒有出發日就不知道，是 nil
func closedOnTripDay(_ start: String, _ day: Int, _ id: String, _ closed: ClosedCheck) -> String? {
    if start.isEmpty { return nil }
    return closed(id, addDays(start, day - 1))
}

/// 這趟排到休館那天的站，一站一句，照天數排：「第 2 天 12/1（二）「景福宮」休館：每週二休。」已經拔起來的不講
func closedNotes(_ t: Trip, closed: ClosedCheck = closedByFacts) -> [String] {
    var out: [String] = []
    for d in stride(from: 1, through: t.days, by: 1) {
        for x in dayStops(t, d) where x.it.status != .pulled {
            guard let why = closedOnTripDay(t.start, d, x.it.id, closed) else { continue }
            out.append("第 \(d) 天 \(tripDayLabel(t, d))「\(x.it.n)」休館：\(why)。")
        }
    }
    return out
}

private let CLOSED_DOW: [String] = ["日", "一", "二", "三", "四", "五", "六"]

private func closedDow(_ d: Int) -> String {
    return d >= 0 && d < CLOSED_DOW.count ? CLOSED_DOW[d] : ""
}

/// 給 AI 看的固定休，短的：「週二休」「週日、一休」「每月第 2 個週日休」「沒有固定休」。沒查到是 nil
func closedShort(_ f: PlaceFact) -> String? {
    if f.gone != nil { return "已經不開了" }
    var bits: [String] = []
    let weekly: [Int] = f.closed ?? []
    if !weekly.isEmpty {
        let names: [String] = weekly.map { (d: Int) -> String in closedDow(d) }
        bits.append("週" + names.joined(separator: "、") + "休")
    }
    let nth: [NthDay] = f.closedNth ?? []
    if !nth.isEmpty {
        let names: [String] = nth.map { (n: NthDay) -> String in "第 \(n.week) 個週\(closedDow(n.dow))" }
        bits.append("每月" + names.joined(separator: "、") + "休")
    }
    if !bits.isEmpty { return bits.joined(separator: "、") }
    return f.closed == nil ? nil : "沒有固定休"
}

/// 提示詞裡一個地方後面的休館：「,週二休,第 2、9 天不開」。國定假日、節日、整修都算在第幾天裡。沒有資料是空字串
func closedTag(_ t: Trip, _ id: String, closed: ClosedCheck = closedByFacts) -> String {
    let fact: PlaceFact? = factOf(id)
    var out: String = ""
    if let f = fact, let s = closedShort(f) { out += "," + s }
    if fact?.gone != nil { return out }
    var days: [String] = []
    for d in stride(from: 1, through: t.days, by: 1) {
        if closedOnTripDay(t.start, d, id, closed) != nil { days.append(String(d)) }
    }
    if days.isEmpty { return out }
    if days.count == t.days { return out + ",這趟每天都不開" }
    return out + ",第 " + days.joined(separator: "、") + " 天不開"
}

/// 須知那句核對到哪裡：「看過官方頁 11/25」「二手資料 11/25」「未核對」。資料包的那句一律未核對
func tipSourceLabel(_ it: Stop) -> String {
    guard let tip = tipOf(it), tip.status != FactStatus.none else { return factLabel(nil) }
    return factLabel(factOf(it.id))
}

/* ---------- 查詢 ---------- */

/// TS 的 { it, s }：一站和它所在的時段。si、ii 是在 t.slots 和 slots[si].items 裡的位置，要改就用位置去改
struct Found {
    let it: Stop
    let s: Slot
    let si: Int
    let ii: Int
}

func allItems(_ t: Trip) -> [Found] {
    var out: [Found] = []
    var si: Int = 0
    for s in t.slots {
        var ii: Int = 0
        for it in s.items {
            out.append(Found(it: it, s: s, si: si, ii: ii))
            ii += 1
        }
        si += 1
    }
    return out
}

func usedIds(_ t: Trip) -> Set<String> {
    var out: Set<String> = []
    for s in t.slots {
        for it in s.items { out.insert(it.id) }
    }
    return out
}

func halfDays(_ t: Trip) -> Int {
    var n: Int = 0
    for s in t.slots where s.off != true && s.part != .eve { n += 1 }
    return n
}

func findItem(_ t: Trip, _ id: String) -> Found? {
    let all: [Found] = allItems(t)
    return all.first { (x: Found) -> Bool in x.it.id == id }
}

/// 回 t.slots 的位置
func slotAt(_ t: Trip, _ day: Int, _ part: Part) -> Int? {
    return t.slots.firstIndex { (s: Slot) -> Bool in
        return s.day == day && s.part == part && s.off != true
    }
}

func bigCount(_ t: Trip, _ day: Int) -> Int {
    var n: Int = 0
    for s in t.slots where s.day == day {
        for it in s.items where it.s == .L { n += 1 }
    }
    return n
}

func areaOf(_ it: Stop) -> String {
    if let a = it.a { return AREA[need: a] }
    return it.mine == true ? "自己加的" : "AI 加的"
}

func dayStops(_ t: Trip, _ day: Int) -> [Found] {
    var out: [Found] = []
    var si: Int = 0
    for s in t.slots {
        if s.day == day && s.off != true {
            var ii: Int = 0
            for it in s.items {
                out.append(Found(it: it, s: s, si: si, ii: ii))
                ii += 1
            }
        }
        si += 1
    }
    return out
}

/// 這趟要提醒的：一天太多主要景點、排到休館那天
func warnings(_ t: Trip, closed: ClosedCheck = closedByFacts) -> [String] {
    var w: [String] = []
    for d in stride(from: 1, through: t.days, by: 1) {
        let n: Int = bigCount(t, d)
        if n > 2 { w.append("第 \(d) 天現在有 \(n) 個主要景點，會很累。") }
    }
    w.append(contentsOf: closedNotes(t, closed: closed))
    return w
}

/* ---------- 改行程（直接改傳進來的那一份；呼叫端負責先複製） ---------- */
private var planSeq: Int = 0

func newId(_ prefix: String) -> String {
    let ms: Int = Int(Date().timeIntervalSince1970 * 1000)
    let id: String = prefix + String(ms, radix: 36) + String(planSeq, radix: 36)
    planSeq += 1
    return id
}

func moveItem(_ t: inout Trip, _ id: String, _ day: Int, _ part: Part) -> String? {
    let found: Found? = findItem(t, id)
    let toIndex: Int? = slotAt(t, day, part)
    guard let x = found else { return "找不到那一站" }
    guard let to = toIndex else { return "第 \(day) 天\(PART[part] ?? "")你在路上，放不進去" }
    if to == x.si { return nil }
    t.slots[x.si].items.remove(at: x.ii)
    if t.slots[x.si].items.isEmpty { t.slots[x.si].rest = true }
    t.slots[to].items.append(x.it)
    if part != .eve { t.slots[to].rest = false }
    return nil
}

/// 兩個時段的站和留白整個對調
private func swapSlots(_ t: inout Trip, _ a: Int, _ b: Int) {
    if a == b { return }
    let itemsA: [Stop] = t.slots[a].items
    let restA: Bool = t.slots[a].rest
    let itemsB: [Stop] = t.slots[b].items
    let restB: Bool = t.slots[b].rest
    t.slots[a].items = itemsB
    t.slots[a].rest = restB
    t.slots[b].items = itemsA
    t.slots[b].rest = restA
}

func swapParts(_ t: inout Trip, _ day: Int, _ a: Part, _ b: Part) -> String? {
    let ia: Int? = slotAt(t, day, a)
    let ib: Int? = slotAt(t, day, b)
    guard let A = ia, let B = ib else { return "第 \(day) 天沒有兩個時段可以對調" }
    swapSlots(&t, A, B)
    return nil
}

func swapDays(_ t: inout Trip, _ a: Int, _ b: Int) -> String? {
    var moved: Int = 0
    for p in PARTS {
        let ia: Int? = slotAt(t, a, p)
        let ib: Int? = slotAt(t, b, p)
        if let A = ia, let B = ib {
            swapSlots(&t, A, B)
            moved += 1
        }
    }
    return moved > 0 ? nil : "這兩天沒有對得上的時段"
}

/// 拿掉一站，放進「下次再來」。整站留著，之後可以排回這趟
func seedOut(_ t: inout Trip, _ seeds: inout [Seed], _ id: String, _ why: String) -> Stop? {
    guard let x = findItem(t, id) else { return nil }
    let seed: Seed = Seed(
        id: newId("s"), n: x.it.n, a: areaOf(x.it), why: why, stop: x.it,
        from: SeedFrom(day: x.s.day, part: x.s.part)
    )
    seeds.insert(seed, at: 0)
    t.slots[x.si].items.remove(at: x.ii)
    if t.slots[x.si].items.isEmpty { t.slots[x.si].rest = true }
    return x.it
}

/// 把「下次再來」的一站排回這趟：先放回原本的時段，不行就找最空的白天。
/// 這趟已經有同一站就不加。now 有給（旅途中）時，過了的時段不放。沒排成的，那一站留在下次再來。
/// 有別天可以放，就不放它休館的那天；能放的日子全都休才照放，並且講出來
func restoreSeed(
    _ t: inout Trip, _ seeds: inout [Seed], _ seedId: String, _ now: TripNow? = nil,
    closed: ClosedCheck = closedByFacts
) -> String {
    let found: Int? = seeds.firstIndex { (s: Seed) -> Bool in s.id == seedId }
    guard let i = found else { return "找不到那一站" }
    let seed: Seed = seeds[i]
    // 下次再來是每一趟共用的，這趟可能早就排了同一站
    if let kept = seed.stop, let dup = findItem(t, kept.id) {
        return "「\(dup.it.n)」已經排在這趟第 \(dup.s.day) 天\(PART[need: dup.s.part])，沒有再排一次，先留在下次再來"
    }
    var stop: Stop
    if let kept = seed.stop {
        stop = kept
    } else {
        stop = Stop(
            id: newId("m"), n: seed.n, kr: "", a: nil, s: .S, c: .sight, lat: nil, lng: nil,
            status: .kept, swaps: 0, why: "你從「下次再來」排回來的", mine: true
        )
    }
    // 這一站哪幾天休館
    var shut: [Int: String] = [:]
    for d in stride(from: 1, through: t.days, by: 1) {
        if let why = closedOnTripDay(t.start, d, stop.id, closed) { shut[d] = why }
    }
    var toIndex: Int? = nil
    var passed: String = ""
    // 原本的時段還能放，只是那天休館
    var shutHome: Int? = nil
    if let from = seed.from, let home = slotAt(t, from.day, from.part) {
        if slotPast(now, from.day, from.part) {
            passed = "第 \(from.day) 天\(PART[need: from.part])已經過了，"
        } else if shut[from.day] != nil {
            shutHome = home
        } else {
            toIndex = home
        }
    }
    if toIndex == nil { toIndex = emptiestSlot(t, now, Set<Int>(shut.keys)) }
    // 能放的日子全都休館：照放，後面會講
    if toIndex == nil { toIndex = shutHome ?? emptiestSlot(t, now) }
    guard let to = toIndex else {
        if hasAnySlot(t) { return "這趟能排的時段都過了，「\(stop.n)」先留在下次再來" }
        return "這趟每個時段都在路上，排不進去"
    }
    stop.status = .kept
    t.slots[to].items.append(stop)
    let toDay: Int = t.slots[to].day
    let toPart: Part = t.slots[to].part
    if toPart != .eve { t.slots[to].rest = false }
    seeds.remove(at: i)
    let at: String = "第 \(toDay) 天\(PART[need: toPart])"
    if let why = shut[toDay] {
        let placed: String = passed.isEmpty ? "「\(stop.n)」排回\(at)了" : "\(passed)「\(stop.n)」改排在\(at)"
        return "\(placed)，但那天它休館（\(why)），能排的別天也都休"
    }
    if !passed.isEmpty { return "\(passed)「\(stop.n)」改排在\(at)" }
    if shutHome != nil, let from = seed.from, let why = shut[from.day] {
        return "第 \(from.day) 天「\(stop.n)」休館（\(why)），改排在\(at)"
    }
    return "「\(stop.n)」排回\(at)了"
}

/// 這趟有沒有不在路上的時段（不管過了沒）
private func hasAnySlot(_ t: Trip) -> Bool {
    return t.slots.contains { (s: Slot) -> Bool in s.off != true }
}

/// 還能排東西的時段：不在路上、還沒過。回 t.slots 的位置，照行程順序
private func openSlots(_ t: Trip, _ now: TripNow?) -> [Int] {
    var out: [Int] = []
    var si: Int = 0
    for s in t.slots {
        if s.off != true && !slotPast(now, s.day, s.part) { out.append(si) }
        si += 1
    }
    return out
}

/// 站最少的那個時段；一樣少就取前面的（TS 是穩定排序後拿第一個）
private func fewestSlot(_ t: Trip, _ pool: [Int]) -> Int? {
    var best: Int? = nil
    var bestCount: Int = 0
    for i in pool {
        let n: Int = t.slots[i].items.count
        if best == nil || n < bestCount {
            best = i
            bestCount = n
        }
    }
    return best
}

/// 第 day 天最空的時段：先看白天，白天沒有才是晚上。這天沒有能排的就回 nil
private func emptiestOnDay(_ t: Trip, _ day: Int, _ now: TripNow?) -> Int? {
    let open: [Int] = openSlots(t, now).filter { (i: Int) -> Bool in t.slots[i].day == day }
    let light: [Int] = open.filter { (i: Int) -> Bool in t.slots[i].part != .eve }
    return fewestSlot(t, light.isEmpty ? open : light)
}

/// 最空的白天時段，回 t.slots 的位置。now 有給（旅途中）時，過了的時段不算。
/// shut 是要跳過的那幾天（要放的那一站那天休館）
private func emptiestSlot(_ t: Trip, _ now: TripNow?, _ shut: Set<Int> = []) -> Int? {
    let open: [Int] = openSlots(t, now).filter { (i: Int) -> Bool in !shut.contains(t.slots[i].day) }
    let day: [Int] = open.filter { (i: Int) -> Bool in t.slots[i].part != .eve }
    let mid: [Int] = day.filter { (i: Int) -> Bool in
        let s: Slot = t.slots[i]
        return s.day > 1 && s.day < t.days && bigCount(t, s.day) < 2
    }
    let pool: [Int] = mid.isEmpty ? day : mid
    if let hit = fewestSlot(t, pool) { return hit }
    return open.first
}

/// 自己加一站。day 有給就先排那一天，那天沒有能排的時段才排別天（會講清楚）。
/// now 有給（旅途中）時，過了的時段不放；都不行就放到下次再來
func addOwn(
    _ t: inout Trip, _ seeds: inout [Seed], _ name: String, _ day: Int? = nil, _ now: TripNow? = nil
) -> String {
    var slot: Int? = nil
    if let d = day { slot = emptiestOnDay(t, d, now) }
    let moved: Bool = day != nil && slot == nil
    if slot == nil { slot = emptiestSlot(t, now) }
    let it: Stop = Stop(
        id: newId("m"), n: name, kr: "", a: nil, s: .L, c: .sight, lat: nil, lng: nil,
        status: .kept, swaps: 0, why: "你自己加的", mine: true
    )
    guard let to = slot else {
        let seed: Seed = Seed(id: newId("s"), n: name, a: "自己加的", why: "這趟排不進去", stop: it, from: nil)
        seeds.insert(seed, at: 0)
        if hasAnySlot(t) { return "這趟能排的時段都過了，「\(name)」先放到下次再來" }
        return "這趟排不進去，「\(name)」先放到下次再來"
    }
    t.slots[to].items.append(it)
    let toDay: Int = t.slots[to].day
    let toPart: Part = t.slots[to].part
    if toPart != .eve { t.slots[to].rest = false }
    if moved, let d = day {
        return "第 \(d) 天沒有能排的時段了，「\(name)」排在第 \(toDay) 天\(PART[need: toPart])"
    }
    return "「\(name)」排在第 \(toDay) 天\(PART[need: toPart])"
}

/// 同一帶、同大小的三個替代選項。這一站排在哪天，就跳過那天休館的
func alternatives(
    _ t: Trip, _ base: Settings, _ it: Stop, closed: ClosedCheck = closedByFacts
) -> [Place] {
    let day: Int? = findItem(t, it.id)?.s.day
    let st: Settings = tripSettings(base, t.tweaks)
    let noUp: Bool = st.body.contains(.stairs)
    let used: Set<String> = usedIds(t)
    let w: [Cat: Int] = planWeights(st)
    var ar: [AreaKey] = AreaKey.allCases
    if let a = it.a { ar = [a] + (ADJ[a] ?? []) }
    var pool: [Place] = []
    for p in PLACES {
        if used.contains(p.id) { continue }
        if banned(p, st) { continue }
        if noUp && p.up == true { continue }
        if !ar.contains(p.a) { continue }
        if p.s != it.s { continue }
        if it.c == .eat && p.c != .eat { continue }
        if let d = day, closedOnTripDay(t.start, d, p.id, closed) != nil { continue }
        pool.append(p)
    }
    let sorted: [Place] = planStableSorted(pool) { (x: Place, y: Place) -> Bool in
        return (w[x.c] ?? 0) > (w[y.c] ?? 0)
    }
    return Array(sorted.prefix(3))
}

func replaceWith(_ t: inout Trip, _ fromId: String, _ p: Place) -> String? {
    guard let x = findItem(t, fromId) else { return "找不到要換掉的那一站" }
    var next: Stop = planToStop(p, "你把「\(x.it.n)」換成這個")
    next.swaps = x.it.swaps + 1
    t.slots[x.si].items[x.ii] = next
    return nil
}

/// 順路可去：當天去的那幾帶裡，還沒排進來、那天沒休館的小站
func nearbyPool(
    _ t: Trip, _ day: Int, _ st: Settings? = nil, closed: ClosedCheck = closedByFacts
) -> [String] {
    let used: Set<String> = usedIds(t)
    var areas: Set<AreaKey> = []
    for x in dayStops(t, day) {
        if let a = x.it.a { areas.insert(a) }
    }
    var out: [String] = []
    for p in PLACES {
        if out.count >= 3 { break }
        if !areas.contains(p.a) { continue }
        if used.contains(p.id) { continue }
        if p.s != .S { continue }
        if let s = st, banned(p, s) { continue }
        if closedOnTripDay(t.start, day, p.id, closed) != nil { continue }
        out.append(p.n)
    }
    return out
}

/* ---------- 附近還有什麼（S10，線框 A12）：iOS 版才有，mobile/ 沒有對應的 TS ---------- */

/// 附近只看這麼遠以內（公里，直線加三成之後）。再遠就不算附近了
let NEARBY_MAX_KM: Double = 3
/// 一次給幾個
let NEARBY_PAGE: Int = 3

/// 從哪裡算附近
enum NearbyFrom: Equatable, Sendable {
    /// 這一天還沒拔的下一站
    case next
    /// 這一天的站都拔完了：最後拔起來的那一站
    case pulled
    /// 這一天沒有排站：住的地方
    case home
}

struct NearbyOrigin: Equatable, Sendable {
    var from: NearbyFrom
    /// 給人看的名字：站名，或「住的地方（明洞）」
    var name: String
    /// 起點是一站時才有
    var stopId: String?
    /// 起點那一站在哪個時段；住的地方是 nil
    var part: Part?
    var pt: GeoPt

    /// 起點有沒有座標。自己加的、AI 加的站可能沒有，就算不出附近
    var known: Bool {
        return pt.lat != nil && pt.lng != nil
    }
}

/// 附近的一個地方，和從起點怎麼去（估）
struct NearbyPick: Hashable, Sendable {
    var place: Place
    var leg: Leg
}

/// 附近要從哪裡算：這一天還沒拔的下一站；都拔完了就是最後一站；這天沒排站就是住的地方
func nearbyOrigin(_ t: Trip, _ base: Settings, _ day: Int) -> NearbyOrigin {
    let stops: [Found] = dayStops(t, day)
    let kept: Found? = stops.first { (x: Found) -> Bool in x.it.status == .kept }
    if let x = kept {
        return NearbyOrigin(from: .next, name: x.it.n, stopId: x.it.id, part: x.s.part, pt: GeoPt(x.it))
    }
    if let x = stops.last {
        return NearbyOrigin(from: .pulled, name: x.it.n, stopId: x.it.id, part: x.s.part, pt: GeoPt(x.it))
    }
    let h: HotelPt = hotelPt(tripSettings(base, t.tweaks), t)
    return NearbyOrigin(from: .home, name: "住的地方（\(h.n)）", stopId: nil, part: nil, pt: GeoPt(h))
}

/// 這趟還沒排的地方，照離起點的距離排（近的在前）。每一個都帶怎麼去：
/// 超過平常的我「一天能走多少」的走路上限，就是地鐵或公車（照 leg()）。
/// 跟 alternatives 一樣跳過不排的、要爬坡的、這天休館的；這天已經有 2 個大站就不給大站。起點沒有座標回空的
func nearbyRanked(
    _ t: Trip, _ base: Settings, _ day: Int, closed: ClosedCheck = closedByFacts
) -> [NearbyPick] {
    let st: Settings = tripSettings(base, t.tweaks)
    let origin: NearbyOrigin = nearbyOrigin(t, base, day)
    if !origin.known { return [] }
    let used: Set<String> = usedIds(t)
    let noUp: Bool = st.body.contains(.stairs)
    let bigFull: Bool = bigCount(t, day) >= 2
    var picks: [NearbyPick] = []
    for p in PLACES {
        if used.contains(p.id) { continue }
        if banned(p, st) { continue }
        if noUp && p.up == true { continue }
        if bigFull && p.s == .L { continue }
        if closedOnTripDay(t.start, day, p.id, closed) != nil { continue }
        guard let l = leg(origin.pt, GeoPt(p), st) else { continue }
        if l.km > NEARBY_MAX_KM { continue }
        picks.append(NearbyPick(place: p, leg: l))
    }
    return planStableSorted(picks) { (a: NearbyPick, b: NearbyPick) -> Bool in
        return a.leg.km < b.leg.km
    }
}

/// 第幾組三個（「再看三個」）。看完了從頭再來
func nearbyPage(_ ranked: [NearbyPick], _ page: Int) -> [NearbyPick] {
    if ranked.isEmpty { return [] }
    let pages: Int = (ranked.count + NEARBY_PAGE - 1) / NEARBY_PAGE
    let k: Int = ((page % pages) + pages) % pages
    let start: Int = k * NEARBY_PAGE
    let end: Int = min(start + NEARBY_PAGE, ranked.count)
    return Array(ranked[start..<end])
}

/// 排進這一天的哪個時段：起點那一站的時段；不行就現在這個時段；再不行就這天第一個還能排的。
/// 在路上的、已經過了的時段不排。都不行回 nil
func nearbyPart(_ t: Trip, _ day: Int, _ origin: NearbyOrigin, _ now: TripNow? = nil) -> Part? {
    let open: [Part] = PARTS.filter { (p: Part) -> Bool in
        return slotAt(t, day, p) != nil && !slotPast(now, day, p)
    }
    if let p = origin.part, open.contains(p) { return p }
    if let n = now, n.day == day, open.contains(n.part) { return n.part }
    return open.first
}

/// 把附近的一個地方排進第 day 天的 part。afterId 有給、而且在同一個時段，就排在它後面；不然排在最後。
/// 排好回 nil，排不進去回原因
func addNearby(_ t: inout Trip, _ p: Place, _ day: Int, _ part: Part, _ afterId: String? = nil) -> String? {
    if usedIds(t).contains(p.id) { return "「\(p.n)」已經排在這趟裡了" }
    guard let to = slotAt(t, day, part) else { return "第 \(day) 天\(PART[need: part])你在路上，放不進去" }
    let it: Stop = planToStop(p, "你從「附近還有什麼」排進來的")
    var at: Int = t.slots[to].items.count
    if let id = afterId {
        let hit: Int? = t.slots[to].items.firstIndex { (x: Stop) -> Bool in x.id == id }
        if let i = hit { at = i + 1 }
    }
    t.slots[to].items.insert(it, at: at)
    if part != .eve { t.slots[to].rest = false }
    return nil
}

/* ---------- 怎麼去、多遠、多久（估算） ---------- */

/// 地圖上的一個點。住的地方、候選地點、行程裡的站都可以轉成它
struct GeoPt: Hashable, Sendable {
    var lat: Double?
    var lng: Double?

    init(lat: Double?, lng: Double?) {
        self.lat = lat
        self.lng = lng
    }

    init(_ s: Stop) {
        self.lat = s.lat
        self.lng = s.lng
    }

    init(_ p: Place) {
        self.lat = p.lat
        self.lng = p.lng
    }

    init(_ h: HotelPt) {
        self.lat = h.lat
        self.lng = h.lng
    }
}

struct Leg: Hashable, Sendable {
    var mode: String
    var km: Double
    var min: Int
    var cost: Double
}

func km(_ a: GeoPt, _ b: GeoPt) -> Double? {
    guard let aLat = a.lat, let bLat = b.lat, let aLng = a.lng, let bLng = b.lng else { return nil }
    let R: Double = 6371
    let dLa: Double = (bLat - aLat) * Double.pi / 180
    let dLo: Double = (bLng - aLng) * Double.pi / 180
    let sLa: Double = sin(dLa / 2)
    let sLo: Double = sin(dLo / 2)
    let cosA: Double = cos(aLat * Double.pi / 180)
    let cosB: Double = cos(bLat * Double.pi / 180)
    let h: Double = sLa * sLa + cosA * cosB * sLo * sLo
    return 2 * R * asin(h.squareRoot()) * 1.3  // 直線距離加三成，當成實際要走的路
}

func leg(_ a: GeoPt, _ b: GeoPt, _ st: Settings) -> Leg? {
    guard let d = km(a, b) else { return nil }
    // 走路的上限（公里）：要少走的 0.5，能走的 2，其他 1
    var walkMax: Double = 1
    if st.walk == .less {
        walkMax = 0.5
    } else if st.move == .walk || st.walk == .lots {
        walkMax = 2
    }
    if d < 0.15 { return Leg(mode: "就在旁邊", km: d, min: 2, cost: 0) }
    if d <= walkMax { return Leg(mode: "走路", km: d, min: planRound(d * 13), cost: 0) }
    if d >= 25 { return Leg(mode: "火車或巴士", km: d, min: planRound(d * 1.3 + 25), cost: 250) }
    if st.move == .taxi { return Leg(mode: "計程車", km: d, min: planRound(d * 2.4 + 6), cost: d * 30 + 110) }
    return Leg(mode: "地鐵或公車", km: d, min: planRound(d * 2.6 + 10), cost: 35)
}

func baseOf(_ t: Trip?, _ st: Settings) -> BaseKey {
    return t?.base ?? st.base
}

func hotelPt(_ st: Settings, _ t: Trip? = nil) -> HotelPt {
    return HOTEL[need: baseOf(t, st)]
}

/// 重排時要帶回去的那幾項
func draftOf(_ t: Trip) -> TripDraft {
    return TripDraft(
        tweaks: t.tweaks, city: t.city, base: t.base, stayName: t.stayName, name: t.name, cover: t.cover,
        start: t.start, days: t.days, arrive: t.arrive, leave: t.leave, people: t.people
    )
}

/// 這一天每一段：住的地方 → 第 1 站 → … → 住的地方。長度是站數＋1
func dayLegs(_ t: Trip, _ base: Settings, _ day: Int) -> [Leg?] {
    let st: Settings = tripSettings(base, t.tweaks)
    let stops: [Found] = dayStops(t, day)
    if stops.isEmpty { return [] }
    let hotel: GeoPt = GeoPt(hotelPt(st, t))
    var pts: [GeoPt] = [hotel]
    for x in stops { pts.append(GeoPt(x.it)) }
    pts.append(hotel)
    var out: [Leg?] = []
    for i in 0..<(pts.count - 1) {
        out.append(leg(pts[i], pts[i + 1], st))
    }
    return out
}

func legText(_ l: Leg?) -> String {
    guard let x = l else { return "這一段距離不明，到時候查地圖" }
    return "\(x.mode)・約 \(String(format: "%.1f", x.km)) 公里・\(x.min) 分鐘（估）"
}

/* ---------- 花費（粗估） ---------- */
struct CostRow: Hashable, Sendable {
    var name: String
    var amount: Double
    var note: String
}

func cost(_ t: Trip, _ base: Settings) -> (rows: [CostRow], total: Double, people: Int) {
    let st: Settings = tripSettings(base, t.tweaks)
    let n: Int = t.people == 0 ? 1 : t.people
    let nights: Int = max(t.days - 1, 0)
    let perNight: Double = STAY[need: st.stay].perNight
    let stay: Double = Double(nights) * perNight / (n >= 2 ? 2.0 : 1.0)
    var fineExtra: Double = 0
    var ticket: Double = 0
    for x in allItems(t) {
        let fee: Double = x.it.fee ?? 0
        if x.it.c == .eat {
            fineExtra += fee
        } else {
            ticket += fee
        }
    }
    let food: Double = Double(t.days) * st.budget + fineExtra
    var move: Double = 600
    for d in stride(from: 1, through: t.days, by: 1) {
        // TS 這裡傳的是已經套過這趟調整的 st，照搬
        let legs: [Leg?] = dayLegs(t, st, d)
        for one in legs {
            guard let l = one else { continue }
            move += l.mode == "計程車" ? l.cost / Double(n) : l.cost
        }
    }
    let stayNote: String = "\(nights) 晚 × \(money(perNight))" + (n >= 2 ? "，兩人分" : "")
    let foodNote: String = "\(t.days) 天 × \(money(st.budget))" + (fineExtra != 0 ? "，名店另加 " + money(fineExtra) : "")
    let rows: [CostRow] = [
        CostRow(name: "住宿", amount: stay, note: stayNote),
        CostRow(name: "吃喝", amount: food, note: foodNote),
        CostRow(name: "門票與體驗", amount: ticket, note: "這趟要付費的站加總"),
        CostRow(name: "交通", amount: move, note: "市內移動＋機場來回"),
        CostRow(name: "行前", amount: 700, note: "網卡、旅遊險"),
        CostRow(name: "機票", amount: t.flight, note: t.flight != 0 ? "你自己填的" : "還沒填"),
    ]
    var total: Double = 0
    for r in rows { total += r.amount }
    return (rows: rows, total: total, people: n)
}

/// 每人粗估，講成一個區間
func costRange(_ t: Trip, _ st: Settings) -> String {
    let c: (rows: [CostRow], total: Double, people: Int) = cost(t, st)
    return "\(money(c.total * 0.85))–\(money(c.total * 1.15))"
}

/* ---------- 給人看的文字 ---------- */
func settingsSummary(_ st: Settings) -> String {
    let fp: [FoodKind: Int] = foodPct(st)
    let liked: [Cat] = CATS.filter { (k: Cat) -> Bool in (st.play[k] ?? 0) != 0 }
    let likedSorted: [Cat] = planStableSorted(liked) { (a: Cat, b: Cat) -> Bool in
        return (st.play[a] ?? 0) > (st.play[b] ?? 0)
    }
    let likes: [String] = likedSorted.map { (k: Cat) -> String in
        return CAT[need: k] + (st.play[k] == 2 ? "（最愛）" : "")
    }
    let foodKinds: [FoodKind] = FOOD_KINDS.filter { (k: FoodKind) -> Bool in (fp[k] ?? 0) != 0 }
    let foodBits: [String] = foodKinds.map { (k: FoodKind) -> String in
        return "\(FOOD[need: k].name) \(fp[k] ?? 0)%"
    }
    let food: String = foodBits.joined(separator: "、")
    var pace: String = ""
    switch st.pace {
    case .slow: pace = "輕鬆"
    case .mid: pace = "剛好"
    case .fast: pace = "排滿"
    }
    var want: String = ""
    if !st.purposes.isEmpty {
        let wants: [String] = st.purposes.map { (k: Purpose) -> String in PURPOSE[need: k] }
        want = "；旅行想" + wants.joined(separator: "、")
    }
    let moreBits: [String] = (st.tags + [st.wish]).filter { (s: String) -> Bool in !s.isEmpty }
    let more: String = moreBits.joined(separator: "、")
    var eatBits: [String] = []
    if !st.allergy.isEmpty { eatBits.append("過敏：" + st.allergy.joined(separator: "、")) }
    if !st.avoid.isEmpty { eatBits.append("絕對不吃" + st.avoid.joined(separator: "、")) }
    if !st.meh.isEmpty { eatBits.append("不愛吃" + st.meh.joined(separator: "、")) }
    let eat: String = eatBits.joined(separator: "，")
    var bodyBits: [String] = []
    if st.walk != .normal { bodyBits.append(WALK_TEXT[need: st.walk].name) }
    for k in st.body { bodyBits.append(BODY_TEXT[need: k]) }
    bodyBits = bodyBits.filter { (s: String) -> Bool in !s.isEmpty }
    let body: String = bodyBits.joined(separator: "、")
    let neverBits: [String] = st.learned.map { (l: Learned) -> String in learnedText(l) }
    let never: String = neverBits.joined(separator: "、")
    let likeText: String = likes.isEmpty ? "什麼都可以" : likes.joined(separator: "、")

    var out: String = "住\(STAY[need: st.stay].name)、\(HOTEL[need: st.base].n)一帶"
    out += "；吃的是\(food)，一天吃喝 \(money(st.budget))"
    if !eat.isEmpty { out += "，" + eat }
    out += "；喜歡\(likeText)"
    out += "；節奏\(pace)"
    if !body.isEmpty { out += "；體力：" + body }
    out += want
    if !never.isEmpty { out += "；以後都" + never }
    if !more.isEmpty { out += "；還想：" + more }
    return out
}

private func tweakLine(_ tweaks: [Tweak]?) -> String {
    let list: [Tweak] = tweaks ?? []
    let names: [String] = list.map { (k: Tweak) -> String in TWEAK_TEXT[need: k].name }
    return names.joined(separator: "、")
}

/// 這趟臨時調整，給人看的一行。沒有就是空字串
func tweakSummary(_ t: Trip) -> String {
    return tweakLine(t.tweaks)
}

func tweakSummary(_ t: TripDraft) -> String {
    return tweakLine(t.tweaks)
}

/// 整趟的純文字版，給 AI 看，也用來傳給旅伴
/// now 有給時（旅途中），過去的時段和拔起來的站會標出來，給 AI 看
func planText(_ t: Trip, _ withIds: Bool = false, _ fmtDate: ((Int) -> String)? = nil, _ now: TripNow? = nil) -> String {
    var s: String = ""
    for d in stride(from: 1, through: t.days, by: 1) {
        var head: String = "第 \(d) 天"
        if let fmt = fmtDate { head += " " + fmt(d) }
        if let n = now, n.day == d { head += "（今天）" }
        s += head + "\n"
        for p in PARTS {
            let found: Slot? = t.slots.first { (x: Slot) -> Bool in x.day == d && x.part == p }
            guard let sl = found else { continue }
            let partName: String = PART[need: p]
            if sl.off == true {
                s += "  \(partName)：在路上\n"
                continue
            }
            var items: [String] = []
            for i in sl.items {
                if withIds {
                    let size: String = i.s == .L ? "大" : "小"
                    let pulled: String = i.status == .pulled ? ",拔起來了" : ""
                    let shut: String = closedTag(t, i.id)
                    items.append("[\(i.id)] \(i.n)(\(size),\(CAT[need: i.c]),\(areaOf(i))\(shut)\(pulled))")
                } else {
                    items.append(i.n + (i.b == true ? "（要先訂）" : ""))
                }
            }
            var line: String = items.joined(separator: "、")
            if line.isEmpty { line = sl.rest ? "留白" : "空的" }
            if withIds && sl.rest { line += "；留白" }
            if slotPast(now, d, p) { line += "；已經過了" }
            s += "  \(partName)：\(line)\n"
        }
    }
    return s
}
